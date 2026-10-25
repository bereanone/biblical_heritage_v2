package com.deanbowen.bibleappmac

/** App-private persistence; never a study-data export or a Google purchase. */
interface PlayLegacyAccessStore {
    fun read(found: (ByteArray?) -> Unit, unavailable: () -> Unit)
    fun write(marker: ByteArray, complete: (Boolean) -> Unit)
}

data class PlayLegacyRecoveryResult(val legacy: Boolean, val unavailable: Boolean = false) {
    fun useKnownLocalAccess(method: String, hasLocalAccess: Boolean): Boolean =
        unavailable && hasLocalAccess && method != "restore" && method != "purchase"
}

/** Only already-established free access can enroll. Missing/invalid data grants nothing. */
class PlayLegacyAccessRecovery(private val store: PlayLegacyAccessStore) {
    private var enrolled = false
    private var enrolling = false

    fun enrollEstablishedLegacy(knownLegacy: Boolean, saveLocal: () -> Unit) {
        if (!knownLegacy) return
        saveLocal()
        enroll()
    }

    fun resolve(knownLegacy: Boolean, complete: (PlayLegacyRecoveryResult) -> Unit) {
        if (knownLegacy) {
            // A recovery-service outage must never revoke known local access.
            complete(PlayLegacyRecoveryResult(true))
            enroll()
            return
        }
        store.read({ bytes ->
            val restored = bytes?.contentEquals(marker()) == true
            if (restored) enrolled = true
            complete(PlayLegacyRecoveryResult(restored))
        }, { complete(PlayLegacyRecoveryResult(false, unavailable = true)) })
    }

    private fun enroll() {
        if (enrolled || enrolling) return
        enrolling = true
        store.write(marker()) { saved ->
            enrolled = saved
            enrolling = false // A failed write may be retried on the next refresh.
        }
    }

    companion object {
        // A versioned format marker, not a secret. Google checks package/signature
        // before returning it. Never accept this marker from user-selected files.
        private fun marker() = "StudyBible:existing-free-access:v1".toByteArray(Charsets.UTF_8)
    }
}
