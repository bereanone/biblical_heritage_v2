package com.deanbowen.bibleappmac

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.android.gms.auth.blockstore.Blockstore
import com.google.android.gms.auth.blockstore.RetrieveBytesRequest
import com.google.android.gms.auth.blockstore.StoreBytesData

/** Same-device recovery requires device Backup enabled for uninstall retention.
 * Cloud upload is disabled; Google may also transfer this marker during a user
 * initiated device restore. This cannot recover an unenrolled install. */
class PlayLegacyBlockStore(context: Context) : PlayLegacyAccessStore {
    private val appContext = context.applicationContext
    private val client by lazy { Blockstore.getClient(appContext) }
    private val handler = Handler(Looper.getMainLooper())
    private val key = "${context.packageName}.existing_free_access_v1"

    override fun read(found: (ByteArray?) -> Unit, unavailable: () -> Unit) {
        val finish = once<ByteArray?>({ unavailable() }, found)
        try {
            client.retrieveBytes(RetrieveBytesRequest.Builder().setKeys(listOf(key)).build())
                .addOnSuccessListener { response -> finish(true, response.blockstoreDataMap[key]?.bytes) }
                .addOnFailureListener { finish(false, null) }
                .addOnCanceledListener { finish(false, null) }
        } catch (_: Exception) { finish(false, null) }
    }

    override fun write(marker: ByteArray, complete: (Boolean) -> Unit) {
        val finish = once<Boolean>({ complete(false) }, complete)
        try {
            val request = StoreBytesData.Builder().setKey(key).setBytes(marker)
                .setShouldBackupToCloud(false).build()
            client.storeBytes(request)
                .addOnSuccessListener { stored -> finish(true, stored == marker.size) }
                .addOnFailureListener { finish(false, null) }
                .addOnCanceledListener { finish(false, null) }
        } catch (_: Exception) { finish(false, null) }
    }

    private fun <T> once(failed: () -> Unit, success: (T) -> Unit): (Boolean, T?) -> Unit {
        var settled = false
        val timeout = Runnable {
            if (!settled) { settled = true; failed() }
        }
        handler.postDelayed(timeout, 5_000)
        return { ok, value ->
            if (!settled) {
                settled = true
                handler.removeCallbacks(timeout)
                if (ok) {
                    @Suppress("UNCHECKED_CAST")
                    success(value as T)
                } else failed()
            }
        }
    }
}
