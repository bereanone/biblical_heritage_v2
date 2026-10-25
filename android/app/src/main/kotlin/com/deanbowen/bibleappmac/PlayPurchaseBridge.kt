package com.deanbowen.bibleappmac

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.util.AtomicFile
import android.util.Base64
import com.android.billingclient.api.*
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec

/** Android-only billing. Never consumes the permanent unlock. The trial is local
 * to this installation; it is not a Google purchase or subscription. */
class PlayPurchaseBridge(private val activity: Activity, engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "studybible/play_purchases")
    private val handler = Handler(Looper.getMainLooper())
    private val stateFile = AtomicFile(File(activity.noBackupFilesDir, "play_access_v1.json"))
    private val hadSavedAccessState = stateFile.baseFile.exists()
    private val state: JSONObject = try {
        if (stateFile.baseFile.exists()) JSONObject(stateFile.openRead().bufferedReader().use { it.readText() }) else JSONObject()
    } catch (_: Exception) { JSONObject().put("unreadable", true) }
    private val legacyRecovery = PlayLegacyAccessRecovery(PlayLegacyBlockStore(activity))
    private var closed = false
    private var legacyRecoveryUnavailable = false
    private val unlockId = "studybible_full_access"
    private var details: ProductDetails? = null
    private var ministryId: String? = null
    private var purchaseReply: MethodChannel.Result? = null
    private val waiting = mutableListOf<Pair<() -> Unit, (String) -> Unit>>()
    private var connecting = false
    private val client = BillingClient.newBuilder(activity)
        .setListener { result, purchases -> onPurchases(result, purchases.orEmpty()) }
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection().build()

    init {
        channel.setMethodCallHandler { call, reply ->
            try {
                check(!state.optBoolean("unreadable"))
                ministryId = call.argument<String>("ministryId")
                if (call.method !in setOf("initialize", "refresh", "restore", "startTrial", "purchase")) {
                    reply.notImplemented()
                    return@setMethodCallHandler
                }
                withRecoveredLegacy(call.method, reply) {
                    when (call.method) {
                        "initialize", "refresh", "restore" -> refresh(reply)
                        "startTrial" -> {
                            if (!state.has("trialEndsAt")) {
                                state.put("trialEndsAt", now() + 14L * 24 * 60 * 60 * 1000)
                                persist()
                            }
                            reply.success(snapshot())
                        }
                        "purchase" -> purchase(reply)
                    }
                }
            } catch (_: Exception) {
                reply.error("access_unavailable", "Saved access could not be checked. Please try again.", null)
            }
        }
        // Record established free users even in a build whose Dart payment gate
        // is disabled. New installs remain untouched; no billing connection opens.
        try {
            if (!state.optBoolean("unreadable")) {
                legacyRecovery.enrollEstablishedLegacy(legacyFromInstallation()) {
                    state.put("legacy", true)
                    persist()
                }
            }
        } catch (_: Exception) {
            // A later access request retries; enrollment must not break startup.
        }
    }
    private fun withRecoveredLegacy(method: String, reply: MethodChannel.Result, proceed: () -> Unit) {
        // Capture upgrade eligibility before any asynchronous store operation.
        val local = snapshot()
        legacyRecovery.resolve(local["legacy"] == true) { recovered ->
            if (closed) {
                reply.error("closed", "Access check closed. Please try again.", null)
            } else try {
                legacyRecoveryUnavailable = recovered.unavailable
                when {
                    recovered.legacy -> {
                        state.put("legacy", true)
                        reply.success(snapshot())
                    }
                    recovered.unavailable && method == "purchase" -> {
                        reply.error("legacy_recovery_unavailable",
                            "Previous free access could not be checked. Please try again before purchasing.", null)
                    }
                    recovered.useKnownLocalAccess(method, local["paid"] == true || state.optLong("trialEndsAt") > now()) -> {
                        reply.success(snapshot())
                    }
                    // An outage neither grants legacy rights nor prevents an
                    // explicit temporary trial or a normal paid-purchase restore.
                    else -> proceed()
                }
            } catch (_: Exception) {
                reply.error("access_unavailable", "Saved access could not be checked. Please try again.", null)
            }
        }
    }
    private fun now(): Long {
        val value = maxOf(System.currentTimeMillis(), state.optLong("lastSeen"))
        state.put("lastSeen", value)
        return value
    }
    private fun legacyFromInstallation(): Boolean {
        val installation = activity.packageManager.getPackageInfo(activity.packageName, 0)
        return PlayLegacyAccessPolicy.allows(
            hadSavedAccessState, state.optBoolean("legacy"),
            installation.firstInstallTime, installation.lastUpdateTime,
            BuildConfig.PLAY_LEGACY_CUTOFF_MS,
        )
    }
    private fun persist() {
        // Capture migration rights in every atomic billing write, even if the
        // process stops after queryOwned/startTrial and before snapshot.
        state.put("legacy", legacyFromInstallation())
        val output = stateFile.startWrite()
        try {
            output.write(state.toString().toByteArray(Charsets.UTF_8))
            stateFile.finishWrite(output)
        } catch (error: Exception) { stateFile.failWrite(output); throw error }
    }
    private fun snapshot(outcome: String? = null): Map<String, Any?> {
        val current = now()
        val verified = state.optLong("verifiedAt", 0)
        // Keep a previously verified permanent purchase usable offline. A
        // successful authoritative query revokes it after a refund/revocation.
        val paid = state.optBoolean("paid") && verified > 0
        persist()
        val legacy = state.optBoolean("legacy")
        return mapOf("paid" to paid, "legacy" to legacy, "checkedAt" to current,
            "trialEndsAt" to if (state.has("trialEndsAt")) state.getLong("trialEndsAt") else null,
            "trialAvailable" to !state.has("trialEndsAt"),
            "price" to if (legacyRecoveryUnavailable) null else selectedOffer()?.formattedPrice,
            "accessWarning" to if (legacyRecoveryUnavailable)
                "Previous free access could not be checked. Try again before purchasing." else null,
            "outcome" to outcome)
    }
    private fun connect(ready: () -> Unit, failed: (String) -> Unit) {
        if (client.isReady) { ready(); return }
        waiting.add(ready to failed)
        if (connecting) return
        connecting = true
        handler.postDelayed({
            if (connecting) {
                connecting = false
                val callbacks = waiting.toList(); waiting.clear()
                callbacks.forEach { it.second("Google Play did not respond. Please try again.") }
            }
        }, 20_000)
        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                connecting = false
                val callbacks = waiting.toList(); waiting.clear()
                callbacks.forEach { if (result.responseCode == BillingClient.BillingResponseCode.OK)
                    it.first() else it.second("Google Play is unavailable. Please try again.") }
            }
            override fun onBillingServiceDisconnected() {
                connecting = false
                val callbacks = waiting.toList(); waiting.clear()
                callbacks.forEach { it.second("Google Play disconnected. Please try again.") }
            }
        })
    }
    private fun refresh(reply: MethodChannel.Result) {
        connect({
            val product = QueryProductDetailsParams.Product.newBuilder()
                .setProductId(unlockId).setProductType(BillingClient.ProductType.INAPP).build()
            client.queryProductDetailsAsync(QueryProductDetailsParams.newBuilder()
                .setProductList(listOf(product)).build()) { result, response ->
                details = if (result.responseCode == BillingClient.BillingResponseCode.OK)
                    response.productDetailsList.firstOrNull { it.productId == unlockId } else null
                queryOwned { ok ->
                    if (ok) reply.success(snapshot()) else reply.error("store_unavailable",
                        "Google Play could not verify purchases. Please try again.", null)
                }
            }
        }, { reply.success(snapshot()) }) // Offline trial/legacy/cached ownership only.
    }
    private fun valid(purchase: Purchase): Boolean {
        if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED ||
            !purchase.products.contains(unlockId) || purchase.packageName != activity.packageName) return false
        return try {
            val encoded = BuildConfig.PLAY_LICENSE_PUBLIC_KEY
            if (encoded.isBlank()) return false
            val key = KeyFactory.getInstance("RSA").generatePublic(
                X509EncodedKeySpec(Base64.decode(encoded, Base64.DEFAULT)))
            Signature.getInstance("SHA1withRSA").run {
                initVerify(key); update(purchase.originalJson.toByteArray(Charsets.UTF_8))
                verify(Base64.decode(purchase.signature, Base64.DEFAULT))
            }
        } catch (_: Exception) { false }
    }
    private fun queryOwned(done: (Boolean) -> Unit) {
        client.queryPurchasesAsync(QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.INAPP).build()) { result, purchases ->
            if (result.responseCode != BillingClient.BillingResponseCode.OK) { done(false); return@queryPurchasesAsync }
            val owned = purchases.firstOrNull { valid(it) }
            if (owned != null && !owned.isAcknowledged) {
                client.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder()
                    .setPurchaseToken(owned.purchaseToken).build()) { acknowledgment ->
                    val ok = acknowledgment.responseCode == BillingClient.BillingResponseCode.OK
                    if (ok) { state.put("paid", true); state.put("verifiedAt", now()); persist() }
                    done(ok)
                }
            } else {
                state.put("paid", owned != null)
                state.put("verifiedAt", now()); persist(); done(true)
            }
        }
    }
    private fun selectedOffer(): ProductDetails.OneTimePurchaseOfferDetails? {
        val offers = details?.oneTimePurchaseOfferDetailsList.orEmpty()
        val index = PlayOfferSelector.select(offers.map {
            PlayOfferCandidate(it.purchaseOptionId, it.offerId, it.offerToken.orEmpty())
        }, ministryId)
        return index?.let { offers[it] }
    }
    private fun purchase(reply: MethodChannel.Result) {
        if (purchaseReply != null) { reply.error("purchase_pending", "A purchase is already open.", null); return }
        val product = details
        val offer = selectedOffer()
        if (product == null || offer == null || !client.isReady || BuildConfig.PLAY_LICENSE_PUBLIC_KEY.isBlank()) {
            reply.error("product_unavailable", "The permanent unlock is not available yet. Please try again.", null); return
        }
        purchaseReply = reply
        val params = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(product)
            .setOfferToken(requireNotNull(offer.offerToken)).build()
        val result = client.launchBillingFlow(activity,
            BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(params)).build())
        if (result.responseCode != BillingClient.BillingResponseCode.OK) {
            purchaseReply = null
            reply.error("purchase_failed", "Google Play could not open the purchase. Please try again.", null)
        }
    }
    private fun onPurchases(result: BillingResult, purchases: List<Purchase>) {
        handler.post {
            val reply = purchaseReply; purchaseReply = null
            when (result.responseCode) {
                BillingClient.BillingResponseCode.USER_CANCELED -> reply?.success(snapshot("cancelled"))
                BillingClient.BillingResponseCode.OK -> {
                    if (purchases.any { it.products.contains(unlockId) && it.purchaseState == Purchase.PurchaseState.PENDING }) {
                        reply?.success(snapshot("pending"))
                    } else queryOwned { ok ->
                        if (ok) {
                            val current = snapshot("purchased")
                            reply?.success(current); channel.invokeMethod("accessChanged", current)
                        } else reply?.error("verification_failed", "The purchase could not be verified. Use Restore Purchases to retry.", null)
                    }
                }
                else -> reply?.error("purchase_failed", "The purchase was not completed. Please try again.", null)
            }
        }
    }
    fun close() {
        closed = true
        purchaseReply?.error("closed", "Purchase connection closed. Use Restore Purchases when you return.", null)
        purchaseReply = null; channel.setMethodCallHandler(null); client.endConnection()
    }
}
