package com.example.studybible2

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Log
import android.view.Surface
import org.json.JSONArray
import org.json.JSONObject
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity(), EventChannel.StreamHandler, SensorEventListener {
    private val motionChannel = "studybible/reader_tilt_motion"
    private val documentPickerChannel = "studybible/android_document_picker"
    private val documentPickerRequestCode = 4817
    private val libraryTreeRequestCode = 4818
    private val libraryRootChannel = "studybible/library_root"
    private val autoscrollFrameRateChannel = "studybible/reader_autoscroll_frame_rate"
    private val pickerPreferences = "studybible_document_picker"
    private val lastCloudDocumentUriKey = "last_cloud_document_uri"
    private val libraryTreeUriKey = "library_tree_uri"
    private val libraryReconnectTimestampKey = "library_reconnect_timestamp"
    private val libraryAuthorizationErrorKey = "library_authorization_error"
    private val librarySnapshotKey = "library_tree_snapshot_v1"
    private val storageLogTag = "StudyBibleStorage"
    private var sensorManager: SensorManager? = null
    private var rotationSensor: Sensor? = null
    private var eventSink: EventChannel.EventSink? = null
    // Rotation-vector delivery runs on this dedicated background thread instead of
    // the Android main/platform thread. That thread also hosts Choreographer's
    // vsync callback that drives Flutter's frame scheduling on Android, and
    // SENSOR_DELAY_GAME is only a hint: on this hardware it delivers an uncapped,
    // unevenly paced stream (measured ~50Hz with individual gaps alternating
    // between ~12ms and ~28ms). Left on the main thread, that irregular load
    // periodically delayed a vsync just enough to visibly stall the reader's
    // per-frame autoscroll tick. Sampling is capped to 60Hz to match iOS's
    // CMMotionManager rate (AppDelegate.swift), which produces smooth motion.
    private var sensorHandlerThread: HandlerThread? = null
    private var sensorHandler: Handler? = null
    private val sensorSamplingPeriodUs = 16_667
    // Flutter composites its own content on this surface without ever
    // invalidating the Activity's DecorView, so it — not the DecorView — is
    // the correct target for a per-frame-renewing frame-rate vote. See
    // setReaderAutoscrollFrameRateBoost for why this matters.
    private var flutterSurfaceView: FlutterSurfaceView? = null
    private var pendingDocumentPickerResult: MethodChannel.Result? = null
    private var pendingLibraryTreeResult: MethodChannel.Result? = null
    private var pendingLibraryTreeRequiresExisting = false
    private val storageExecutor = Executors.newSingleThreadExecutor()

    override fun onFlutterSurfaceViewCreated(flutterSurfaceView: FlutterSurfaceView) {
        super.onFlutterSurfaceViewCreated(flutterSurfaceView)
        this.flutterSurfaceView = flutterSurfaceView
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        rotationSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            motionChannel,
        ).setStreamHandler(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            documentPickerChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFile" -> openRememberedDocumentPicker(result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            libraryRootChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickAndroidLibraryTree" -> openLibraryTreePicker(
                    result,
                    call.argument<Boolean>("requireExisting") ?: false,
                )
                "validateAndroidLibraryTree" -> validateSavedLibraryTree(result)
                "syncAndroidLibraryTree" -> syncSavedLibraryTree(result)
                "scanAndroidLibraryTree" -> scanSavedLibraryTree(
                    result,
                    call.argument<Boolean>("force") ?: false,
                )
                "clearAndroidLibraryTree" -> {
                    getSharedPreferences(pickerPreferences, Context.MODE_PRIVATE)
                        .edit().remove(libraryTreeUriKey).apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            autoscrollFrameRateChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setActive" -> {
                    setReaderAutoscrollFrameRateBoost(call.argument<Boolean>("active") ?: false)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Requests (or releases) a sustained high display refresh rate for the
    // duration of programmatic reader autoscroll. Without this, autoscroll's
    // jumpTo() calls generate no touch input, so Android's adaptive refresh
    // rate drops the window's touch-boosted high refresh rate ~3s after the
    // last touch and instead delivers ticker frames at an irregular ~26-29Hz
    // (measured on-device), producing visible stall/lurch stepping even
    // though the scroll math itself is correct. Manual finger-drag scrolling
    // is unaffected because active touch keeps the boost alive on its own.
    //
    // Three mechanisms were tried, in order, each measured on-device via the
    // reader's diagnostic capture before moving to the next:
    // 1. WindowManager.LayoutParams.preferredRefreshRate selects the 90Hz
    //    display *mode* (confirmed via `dumpsys window`), but does not stop
    //    Android's separate adaptive vsync-delivery throttle from skipping
    //    Choreographer callbacks; measured ticker cadence was unchanged.
    // 2. View.setRequestedFrameRate (API 35+), first tried on the DecorView,
    //    then on the FlutterSurfaceView itself once it was clear the vote
    //    decays ~100ms after the View holding it last drew/invalidated (the
    //    DecorView never invalidates - Flutter composites via its own
    //    Surface). Cadence was still unchanged either way: this API votes
    //    through Android's HWUI/RenderNode draw pipeline, which Flutter's
    //    Surface-level rendering never participates in, so the vote is
    //    logged but has no effect on a SurfaceView Flutter is driving.
    // 3. Surface.setFrameRate, applied directly to the FlutterSurfaceView's
    //    underlying Surface (its actual SurfaceFlinger buffer queue) rather
    //    than through any View-level voting system. This is the mechanism
    //    that actually moved the measured cadence.
    private var frameRateReassertHandler: Handler? = null
    private val frameRateReassertRunnable = object : Runnable {
        override fun run() {
            applyReaderAutoscrollFrameRateBoost(true)
            frameRateReassertHandler?.postDelayed(this, 500)
        }
    }

    private fun setReaderAutoscrollFrameRateBoost(active: Boolean) {
        frameRateReassertHandler?.removeCallbacks(frameRateReassertRunnable)
        applyReaderAutoscrollFrameRateBoost(active)
        if (active) {
            // DIAGNOSTIC: test whether a one-time vote is being silently
            // cleared by Android's own 3s touch-boost-timeout event, versus
            // the API itself having no effect on this surface regardless of
            // call frequency. Re-asserting every 500ms is not the intended
            // final shape of this fix either way.
            val handler = frameRateReassertHandler ?: Handler(mainLooper).also {
                frameRateReassertHandler = it
            }
            handler.postDelayed(frameRateReassertRunnable, 500)
        }
    }

    private fun applyReaderAutoscrollFrameRateBoost(active: Boolean) {
        val window = window ?: return
        val targetHz = if (!active) {
            0f // 0 = no preference; releases the request.
        } else {
            val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            }
            display?.supportedModes?.maxOfOrNull { it.refreshRate } ?: 0f
        }
        if (targetHz > 0f || !active) {
            window.attributes = window.attributes.also { it.preferredRefreshRate = targetHz }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            flutterSurfaceView?.holder?.surface?.let { surface ->
                if (surface.isValid) {
                    surface.setFrameRate(targetHz, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
                }
            }
        }
    }

    private fun openLibraryTreePicker(
        result: MethodChannel.Result,
        requireExisting: Boolean,
    ) {
        Log.i(storageLogTag, "library_root_picker_opened")
        if (pendingLibraryTreeResult != null) {
            result.error("picker_busy", "A library folder picker is already open.", null)
            return
        }
        // No EXTRA_INITIAL_URI hint here: this same picker is reused for
        // multiple purposes (app library root, Pioneer source folder, etc.),
        // and hardcoding a hint toward the app's own internal library folder
        // sent users into the wrong place (and confused some document
        // providers) when picking an unrelated external folder.
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
            )
            putExtra("studybible_require_existing", requireExisting)
        }
        pendingLibraryTreeResult = result
        pendingLibraryTreeRequiresExisting = requireExisting
        try {
            startActivityForResult(intent, libraryTreeRequestCode)
        } catch (error: Exception) {
            pendingLibraryTreeResult = null
            pendingLibraryTreeRequiresExisting = false
            result.error("picker_unavailable", error.localizedMessage, null)
        }
    }

    private fun openRememberedDocumentPicker(result: MethodChannel.Result) {
        if (pendingDocumentPickerResult != null) {
            result.error("picker_busy", "A document picker is already open.", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val rememberedUri = getSharedPreferences(
                    pickerPreferences,
                    Context.MODE_PRIVATE,
                ).getString(lastCloudDocumentUriKey, null)
                if (!rememberedUri.isNullOrBlank()) {
                    putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(rememberedUri))
                }
            }
        }
        pendingDocumentPickerResult = result
        try {
            startActivityForResult(intent, documentPickerRequestCode)
        } catch (error: Exception) {
            pendingDocumentPickerResult = null
            result.error("picker_unavailable", error.localizedMessage, null)
        }
    }

    @Deprecated("Uses the activity result API required by FlutterActivity integration.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == libraryTreeRequestCode) {
            finishLibraryTreePicker(resultCode, data)
            return
        }
        if (requestCode != documentPickerRequestCode) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingDocumentPickerResult
        pendingDocumentPickerResult = null
        if (result == null) return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            val destinationDirectory = File(cacheDir, "FilesProviderImports").apply {
                mkdirs()
            }
            val destination = File(
                destinationDirectory,
                "${System.currentTimeMillis()}-${sanitizeFileName(documentDisplayName(uri))}",
            )
            contentResolver.openInputStream(uri).use { input ->
                requireNotNull(input) { "The selected cloud file could not be opened." }
                destination.outputStream().use { output -> input.copyTo(output) }
            }
            getSharedPreferences(pickerPreferences, Context.MODE_PRIVATE)
                .edit()
                .putString(lastCloudDocumentUriKey, uri.toString())
                .apply()
            result.success(destination.absolutePath)
        } catch (error: Exception) {
            result.error(
                "provider_file_copy_failed",
                "The selected cloud file could not be copied into StudyBible storage.",
                error.localizedMessage,
            )
        }
    }

    private fun finishLibraryTreePicker(resultCode: Int, data: Intent?) {
        val result = pendingLibraryTreeResult
        pendingLibraryTreeResult = null
        val requireExisting = pendingLibraryTreeRequiresExisting
        pendingLibraryTreeRequiresExisting = false
        if (result == null) return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            Log.i(storageLogTag, "library_root_picker_cancelled")
            result.success(mapOf("cancelled" to true))
            return
        }
        val requestedFlags = data.flags and (
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        try {
            contentResolver.takePersistableUriPermission(uri, requestedFlags)
            Log.i(storageLogTag, "library_root_permission_persisted uri=$uri")
        } catch (error: SecurityException) {
            Log.e(storageLogTag, "library_root_permission_persist_failed", error)
            result.error(
                "persist_permission_failed",
                "StudyBible could not retain access to that folder.",
                error.localizedMessage,
            )
            return
        }
        storageExecutor.execute {
            try {
                val validation = inspectTree(
                    uri,
                    materialize = true,
                    requireExisting = requireExisting,
                )
                if (validation["validFolder"] != true) {
                    Log.w(storageLogTag, "library_root_wrong_folder_selected uri=$uri")
                    try {
                        contentResolver.releasePersistableUriPermission(uri, requestedFlags)
                    } catch (_: SecurityException) {
                        // The provider may already have revoked the temporary grant.
                    }
                    rememberAuthorizationError(
                        validation["validationError"]?.toString()
                            ?: "The selected folder is not a StudyBible library.",
                    )
                    runOnUiThread {
                        result.error(
                            "wrong_library_folder",
                            validation["validationError"]?.toString()
                                ?: "Select the existing StudyBible folder itself.",
                            validation,
                        )
                    }
                    return@execute
                }
                getSharedPreferences(pickerPreferences, Context.MODE_PRIVATE)
                    .edit()
                    .putString(libraryTreeUriKey, uri.toString())
                    .putLong(libraryReconnectTimestampKey, System.currentTimeMillis())
                    .remove(libraryAuthorizationErrorKey)
                    .apply()
                Log.i(storageLogTag, "library_root_reconnected files=${validation["fileCount"]}")
                runOnUiThread { result.success(validation) }
            } catch (error: Exception) {
                rememberAuthorizationError(
                    error.localizedMessage ?: error.javaClass.simpleName,
                )
                runOnUiThread {
                    result.error(
                        "library_tree_validation_failed",
                        "StudyBible could not read that folder.",
                        error.localizedMessage,
                    )
                }
            }
        }
    }

    private fun validateSavedLibraryTree(result: MethodChannel.Result) {
        Log.i(storageLogTag, "library_root_validation_started")
        val saved = getSharedPreferences(pickerPreferences, Context.MODE_PRIVATE)
            .getString(libraryTreeUriKey, null)
        if (saved.isNullOrBlank()) {
            Log.w(storageLogTag, "library_root_reconnect_required")
            rememberAuthorizationError("No saved Android document-tree URI.")
            result.success(
                mapOf(
                    "authorized" to false,
                    "authorizationState" to "libraryRootAuthorizationMissing",
                    "validationError" to "No saved Android document-tree URI.",
                    "lastAuthorizationError" to "No saved Android document-tree URI.",
                ),
            )
            return
        }
        storageExecutor.execute {
            try {
                val validation = inspectTree(Uri.parse(saved), materialize = false)
                if (validation["authorized"] == true) {
                    Log.i(storageLogTag, "library_root_validation_succeeded")
                } else {
                    Log.w(storageLogTag, "library_root_validation_failed")
                    rememberAuthorizationError(
                        validation["validationError"]?.toString()
                            ?: "The saved library authorization is incomplete.",
                    )
                }
                runOnUiThread { result.success(validation) }
            } catch (error: Exception) {
                Log.e(storageLogTag, "library_root_validation_failed", error)
                rememberAuthorizationError(
                    error.localizedMessage ?: error.javaClass.simpleName,
                )
                runOnUiThread {
                    result.success(
                        mapOf(
                            "treeUri" to saved,
                            "authorized" to false,
                            "authorizationState" to "libraryRootAuthorizationMissing",
                            "validationError" to (error.localizedMessage ?: error.javaClass.simpleName),
                        ),
                    )
                }
            }
        }
    }

    private fun syncSavedLibraryTree(result: MethodChannel.Result) {
        val saved = getSharedPreferences(pickerPreferences, Context.MODE_PRIVATE)
            .getString(libraryTreeUriKey, null)
        if (saved.isNullOrBlank()) {
            result.error(
                "library_root_authorization_missing",
                "Reconnect the existing StudyBible folder to continue.",
                null,
            )
            return
        }
        storageExecutor.execute {
            try {
                val uri = Uri.parse(saved)
                val validation = inspectTree(uri, materialize = false)
                if (validation["authorized"] != true) {
                    throw SecurityException("The saved library grant is no longer valid.")
                }
                val rootId = DocumentsContract.getTreeDocumentId(uri)
                val mirror = File(validation["path"].toString())
                val counts = syncMirrorToTree(uri, rootId, mirror)
                runOnUiThread {
                    result.success(
                        mapOf(
                            "created" to counts.first,
                            "existing" to counts.second,
                        ),
                    )
                }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "library_tree_sync_failed",
                        "Completed files could not be saved to the authorized library folder.",
                        error.localizedMessage,
                    )
                }
            }
        }
    }

    private fun syncMirrorToTree(
        treeUri: Uri,
        parentDocumentId: String,
        source: File,
    ): Pair<Int, Int> {
        if (!source.exists()) return Pair(0, 0)
        var created = 0
        var existing = 0
        val childrenByName = listChildren(treeUri, parentDocumentId)
            .associateBy { it.name }
            .toMutableMap()
        for (local in source.listFiles().orEmpty()) {
            if (local.name.endsWith(".downloading") ||
                local.name.endsWith(".saf_importing")
            ) {
                continue
            }
            val remote = childrenByName[local.name]
            if (local.isDirectory) {
                val directoryId = if (
                    remote != null &&
                    remote.mimeType == DocumentsContract.Document.MIME_TYPE_DIR
                ) {
                    remote.documentId
                } else if (remote == null) {
                    val parentUri = DocumentsContract.buildDocumentUriUsingTree(
                        treeUri,
                        parentDocumentId,
                    )
                    val createdUri = DocumentsContract.createDocument(
                        contentResolver,
                        parentUri,
                        DocumentsContract.Document.MIME_TYPE_DIR,
                        local.name,
                    ) ?: throw IllegalStateException("Cannot create ${local.name}")
                    created += 1
                    DocumentsContract.getDocumentId(createdUri)
                } else {
                    existing += 1
                    continue
                }
                val nested = syncMirrorToTree(treeUri, directoryId, local)
                created += nested.first
                existing += nested.second
                continue
            }
            if (remote != null) {
                existing += 1
                continue
            }
            val parentUri = DocumentsContract.buildDocumentUriUsingTree(
                treeUri,
                parentDocumentId,
            )
            val mime = when (local.extension.lowercase()) {
                "epub" -> "application/epub+zip"
                "pdf" -> "application/pdf"
                "json" -> "application/json"
                else -> "application/octet-stream"
            }
            val createdUri = DocumentsContract.createDocument(
                contentResolver,
                parentUri,
                mime,
                local.name,
            ) ?: throw IllegalStateException("Cannot create ${local.name}")
            contentResolver.openOutputStream(createdUri, "w").use { output ->
                requireNotNull(output) { "Cannot write ${local.name}" }
                local.inputStream().use { input -> input.copyTo(output) }
            }
            created += 1
        }
        return Pair(created, existing)
    }

    private fun inspectTree(
        uri: Uri,
        materialize: Boolean,
        requireExisting: Boolean = true,
    ): Map<String, Any?> {
        val preferences = getSharedPreferences(pickerPreferences, Context.MODE_PRIVATE)
        val persisted = contentResolver.persistedUriPermissions
            .firstOrNull { it.uri == uri }
        val read = persisted?.isReadPermission == true
        val write = persisted?.isWritePermission == true
        val rootDocumentId = DocumentsContract.getTreeDocumentId(uri)
        val rootUri = DocumentsContract.buildDocumentUriUsingTree(uri, rootDocumentId)
        val displayName = queryDisplayName(rootUri)
        val broadName = displayName.equals("Documents", true) ||
            displayName.equals("Download", true) ||
            displayName.equals("Downloads", true) ||
            displayName.equals("DCIM", true) ||
            displayName.equals("Pictures", true) ||
            rootDocumentId.equals("primary:", true)
        val dedicatedName = displayName.equals("StudyBible", true)
        val children = listChildren(uri, rootDocumentId)
        val childNames = children.map { it.name.lowercase() }.toSet()
        val markers = childNames.any {
            it in setOf("epubs", "databases", "indexes", "commentaries", "research")
        }
        val empty = children.isEmpty()
        val validFolder = !broadName &&
            dedicatedName &&
            (markers || (!requireExisting && empty))
        val validationError = when {
            broadName -> "Select the dedicated Documents/StudyBible folder, not $displayName."
            !dedicatedName -> "Expected a folder named StudyBible; selected $displayName."
            !markers && requireExisting ->
                "That folder does not contain an existing StudyBible library structure."
            !markers && !empty ->
                "That StudyBible folder does not contain recognized library folders."
            else -> null
        }
        var fileCount = 0
        val mirror = File(
            getExternalFilesDir(null) ?: filesDir,
            "StudyBibleMirror_${uri.toString().hashCode()}",
        )
        if (validFolder && read && materialize) {
            mirror.mkdirs()
            fileCount = copyTreeToMirror(uri, rootDocumentId, mirror)
        } else if (validFolder && read) {
            // Authorization validation must remain constant-depth. Recursively
            // counting every SAF document here used to block Flutter startup
            // for tens of seconds on large libraries.
            fileCount = preferences.getString(librarySnapshotKey, null)
                ?.let { runCatching { JSONObject(it).optInt("fileCount", 0) }.getOrNull() }
                ?: 0
        }
        val authorized = validFolder && read && write
        return mapOf(
            "treeUri" to uri.toString(),
            "path" to mirror.absolutePath,
            "displayName" to displayName,
            "persistedRead" to read,
            "persistedWrite" to write,
            "enumerates" to true,
            "expectedMarkersFound" to markers,
            "validFolder" to validFolder,
            "authorized" to authorized,
            "fileCount" to fileCount,
            "authorizationState" to if (authorized) "authorized" else "libraryRootAuthorizationMissing",
            "validationError" to validationError,
            "authorizationTimestamp" to System.currentTimeMillis(),
            "lastReconnect" to preferences.getLong(
                libraryReconnectTimestampKey,
                0L,
            ).takeIf { it > 0L },
            "lastAuthorizationError" to preferences.getString(
                libraryAuthorizationErrorKey,
                null,
            ),
        )
    }

    private fun rememberAuthorizationError(message: String) {
        getSharedPreferences(pickerPreferences, Context.MODE_PRIVATE)
            .edit()
            .putString(libraryAuthorizationErrorKey, message)
            .apply()
    }

    private data class TreeChild(
        val documentId: String,
        val name: String,
        val mimeType: String,
        val size: Long,
        val modified: Long,
    )

    private fun listChildren(treeUri: Uri, parentDocumentId: String): List<TreeChild> {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            parentDocumentId,
        )
        val children = mutableListOf<TreeChild>()
        contentResolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            )
            val nameIndex = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            )
            val mimeIndex = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
            val sizeIndex = cursor.getColumnIndex(
                DocumentsContract.Document.COLUMN_SIZE,
            )
            val modifiedIndex = cursor.getColumnIndex(
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            )
            while (cursor.moveToNext()) {
                children += TreeChild(
                    cursor.getString(idIndex),
                    cursor.getString(nameIndex) ?: "unnamed",
                    cursor.getString(mimeIndex) ?: "",
                    if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                        cursor.getLong(sizeIndex)
                    } else {
                        -1L
                    },
                    if (modifiedIndex >= 0 && !cursor.isNull(modifiedIndex)) {
                        cursor.getLong(modifiedIndex)
                    } else {
                        0L
                    },
                )
            }
        } ?: throw SecurityException("The selected folder cannot be enumerated.")
        return children
    }

    private fun copyTreeToMirror(
        treeUri: Uri,
        parentDocumentId: String,
        destination: File,
    ): Int {
        var count = 0
        for (child in listChildren(treeUri, parentDocumentId)) {
            val target = File(destination, sanitizeFileName(child.name))
            if (child.mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                target.mkdirs()
                count += copyTreeToMirror(treeUri, child.documentId, target)
            } else {
                val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                    treeUri,
                    child.documentId,
                )
                if (!target.exists() ||
                    target.length() <= 0L ||
                    (child.size >= 0L && target.length() != child.size)
                ) {
                    val temporary = File(target.parentFile, "${target.name}.saf_importing")
                    contentResolver.openInputStream(documentUri).use { input ->
                        requireNotNull(input) { "Cannot open ${child.name}" }
                        FileOutputStream(temporary).use { output -> input.copyTo(output) }
                    }
                    if (!temporary.renameTo(target)) {
                        temporary.copyTo(target, overwrite = false)
                        temporary.delete()
                    }
                }
                count += 1
            }
        }
        return count
    }

    private fun countTreeFiles(treeUri: Uri, parentDocumentId: String): Int {
        var count = 0
        for (child in listChildren(treeUri, parentDocumentId)) {
            count += if (child.mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                countTreeFiles(treeUri, child.documentId)
            } else {
                1
            }
        }
        return count
    }

    private data class LibrarySnapshotEntry(
        val relativePath: String,
        val documentId: String,
        val size: Long,
        val modified: Long,
    )

    private fun scanSavedLibraryTree(result: MethodChannel.Result, force: Boolean) {
        val preferences = getSharedPreferences(pickerPreferences, Context.MODE_PRIVATE)
        val saved = preferences.getString(libraryTreeUriKey, null)
        if (saved.isNullOrBlank()) {
            result.success(mapOf("skipped" to true, "reason" to "no_authorized_tree"))
            return
        }
        storageExecutor.execute {
            val startedAt = System.currentTimeMillis()
            try {
                val uri = Uri.parse(saved)
                val rootId = DocumentsContract.getTreeDocumentId(uri)
                val mirror = File(
                    getExternalFilesDir(null) ?: filesDir,
                    "StudyBibleMirror_${uri.toString().hashCode()}",
                )
                mirror.mkdirs()
                val current = mutableListOf<LibrarySnapshotEntry>()
                collectTreeSnapshot(uri, rootId, "", current)
                val previousJson = if (force) null else preferences.getString(librarySnapshotKey, null)
                val previous = parseLibrarySnapshot(previousJson)
                val previousByPath = previous.associateBy { it.relativePath }
                val currentByPath = current.associateBy { it.relativePath }
                var changed = 0
                var unchanged = 0
                var removed = 0
                for (entry in current) {
                    val old = previousByPath[entry.relativePath]
                    if (!force && old != null && old.size == entry.size && old.modified == entry.modified) {
                        unchanged += 1
                        continue
                    }
                    copySnapshotEntry(uri, entry, mirror)
                    changed += 1
                }
                for (entry in previous) {
                    if (currentByPath.containsKey(entry.relativePath)) continue
                    val rootName = entry.relativePath.substringBefore('/').lowercase()
                    if (rootName !in setOf(
                            "epubs", "pdfs", "commentaries", "research",
                            "images", "media", "translations", "books",
                        )
                    ) continue
                    val stale = File(mirror, entry.relativePath)
                    if (stale.exists() && stale.isFile) stale.delete()
                    removed += 1
                }
                val snapshot = JSONObject()
                    .put("schema", 1)
                    .put("treeUri", saved)
                    .put("completedAt", System.currentTimeMillis())
                    .put("fileCount", current.size)
                    .put("totalSize", current.sumOf { if (it.size > 0) it.size else 0L })
                    .put("entries", JSONArray().apply {
                        current.forEach { entry ->
                            put(JSONObject()
                                .put("path", entry.relativePath)
                                .put("documentId", entry.documentId)
                                .put("size", entry.size)
                                .put("modified", entry.modified))
                        }
                    })
                // Commit only after every copy/removal succeeds. An interrupted
                // scan therefore leaves the previous valid manifest authoritative.
                preferences.edit().putString(librarySnapshotKey, snapshot.toString()).commit()
                val elapsed = System.currentTimeMillis() - startedAt
                Log.i(storageLogTag, "library_background_scan_complete elapsedMs=$elapsed changed=$changed unchanged=$unchanged removed=$removed force=$force")
                runOnUiThread {
                    result.success(mapOf(
                        "elapsedMs" to elapsed,
                        "changed" to changed,
                        "unchanged" to unchanged,
                        "removed" to removed,
                        "fileCount" to current.size,
                        "fullScan" to (force || previousJson == null),
                    ))
                }
            } catch (error: Exception) {
                Log.e(storageLogTag, "library_background_scan_failed", error)
                runOnUiThread {
                    result.error("library_tree_scan_failed", "Library verification failed; the previous index remains available.", error.localizedMessage)
                }
            }
        }
    }

    private fun collectTreeSnapshot(
        treeUri: Uri,
        parentDocumentId: String,
        relativeParent: String,
        output: MutableList<LibrarySnapshotEntry>,
    ) {
        val contentRoots = setOf(
            "epubs", "pdfs", "commentaries", "research", "images",
            "media", "translations", "books",
        )
        for (child in listChildren(treeUri, parentDocumentId)) {
            val relativePath = if (relativeParent.isEmpty()) child.name else "$relativeParent/${child.name}"
            if (child.mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                // Writable databases, markup, tags, history, backups, and
                // indexes are already authoritative in the local mirror. They
                // must never be overwritten by background discovery.
                if (relativeParent.isEmpty() && child.name.lowercase() !in contentRoots) continue
                collectTreeSnapshot(treeUri, child.documentId, relativePath, output)
            } else if (!child.name.endsWith(".downloading") && !child.name.endsWith(".saf_importing")) {
                output += LibrarySnapshotEntry(relativePath, child.documentId, child.size, child.modified)
            }
        }
    }

    private fun parseLibrarySnapshot(raw: String?): List<LibrarySnapshotEntry> {
        if (raw.isNullOrBlank()) return emptyList()
        return runCatching {
            val root = JSONObject(raw)
            if (root.optInt("schema") != 1) return@runCatching emptyList()
            val entries = root.getJSONArray("entries")
            buildList {
                for (index in 0 until entries.length()) {
                    val item = entries.getJSONObject(index)
                    add(LibrarySnapshotEntry(
                        item.getString("path"),
                        item.getString("documentId"),
                        item.optLong("size", -1L),
                        item.optLong("modified", 0L),
                    ))
                }
            }
        }.getOrDefault(emptyList())
    }

    private fun copySnapshotEntry(treeUri: Uri, entry: LibrarySnapshotEntry, mirror: File) {
        val target = File(mirror, entry.relativePath)
        target.parentFile?.mkdirs()
        val temporary = File(target.parentFile, "${target.name}.saf_importing")
        val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, entry.documentId)
        contentResolver.openInputStream(documentUri).use { input ->
            requireNotNull(input) { "Cannot open ${entry.relativePath}" }
            FileOutputStream(temporary).use { output -> input.copyTo(output) }
        }
        if (target.exists() && !target.delete()) throw IllegalStateException("Cannot replace ${entry.relativePath}")
        if (!temporary.renameTo(target)) {
            temporary.copyTo(target, overwrite = true)
            temporary.delete()
        }
    }

    private fun queryDisplayName(uri: Uri): String {
        contentResolver.query(
            uri,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                )
                if (index >= 0) return cursor.getString(index) ?: "Unknown"
            }
        }
        return "Unknown"
    }

    private fun documentDisplayName(uri: Uri): String {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) {
                    val value = cursor.getString(index)?.trim()
                    if (!value.isNullOrEmpty()) return value
                }
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/')?.ifBlank { null }
            ?: "selected_file"
    }

    private fun sanitizeFileName(value: String): String =
        value.replace("/", "_").replace("\\", "_")

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        val sensor = rotationSensor
        if (sensor == null) {
            events?.error(
                "motion_unavailable",
                "Tilt mode is unavailable because this device has no orientation sensor.",
                null,
            )
            return
        }
        eventSink = events
        val thread = HandlerThread("StudyBibleReaderTiltSensor").apply { start() }
        sensorHandlerThread = thread
        val handler = Handler(thread.looper)
        sensorHandler = handler
        sensorManager?.registerListener(this, sensor, sensorSamplingPeriodUs, handler)
    }

    override fun onCancel(arguments: Any?) {
        sensorManager?.unregisterListener(this)
        eventSink = null
        sensorHandler = null
        sensorHandlerThread?.quitSafely()
        sensorHandlerThread = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_ROTATION_VECTOR) return
        val rotationMatrix = FloatArray(9)
        val orientation = FloatArray(3)
        SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)
        SensorManager.getOrientation(rotationMatrix, orientation)
        val payload = mapOf(
            "attitudePitch" to orientation[1].toDouble(),
            "attitudeRoll" to orientation[2].toDouble(),
            "orientation" to readerOrientationName(),
        )
        // EventChannel delivery must happen on the platform thread; this hop is the
        // only work this stream now does on that thread, at the capped 60Hz rate.
        runOnUiThread { eventSink?.success(payload) }
    }

    @Suppress("DEPRECATION")
    private fun readerOrientationName(): String = when (windowManager.defaultDisplay.rotation) {
        Surface.ROTATION_90 -> "landscapeLeft"
        Surface.ROTATION_180 -> "portraitUpsideDown"
        Surface.ROTATION_270 -> "landscapeRight"
        else -> "portrait"
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        sensorManager?.unregisterListener(this)
        eventSink = null
        sensorHandler = null
        sensorHandlerThread?.quitSafely()
        sensorHandlerThread = null
        pendingDocumentPickerResult?.success(null)
        pendingDocumentPickerResult = null
        pendingLibraryTreeResult?.success(mapOf("cancelled" to true))
        pendingLibraryTreeResult = null
        storageExecutor.shutdown()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
