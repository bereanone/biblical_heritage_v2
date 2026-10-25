package com.deanbowen.bibleappmac

import org.junit.Assert.*
import org.junit.Test

class PlayLegacyAccessRecoveryTest {
    private class Store : PlayLegacyAccessStore {
        var bytes: ByteArray? = null
        var reads = 0
        var writes = 0
        var failRead = false
        var failWrite = false
        var deferredRead: (() -> Unit)? = null
        var defer = false
        override fun read(found: (ByteArray?) -> Unit, unavailable: () -> Unit) {
            reads++
            val action = { if (failRead) unavailable() else found(bytes) }
            if (defer) deferredRead = action else action()
        }
        override fun write(marker: ByteArray, complete: (Boolean) -> Unit) {
            writes++
            if (!failWrite) bytes = marker.copyOf()
            complete(!failWrite)
        }
    }
    private fun resolve(recovery: PlayLegacyAccessRecovery, legacy: Boolean): PlayLegacyRecoveryResult {
        var result: PlayLegacyRecoveryResult? = null
        recovery.resolve(legacy) { result = it }
        return requireNotNull(result)
    }
    @Test fun existingFreeUserEnrollsOnlyTheEntitlementMarker() {
        val store = Store()
        assertTrue(resolve(PlayLegacyAccessRecovery(store), true).legacy)
        assertEquals(0, store.reads)
        assertEquals("StudyBible:existing-free-access:v1", String(requireNotNull(store.bytes)))
        // No trial date, purchase token, study records, or account data is accepted by this API.
        assertEquals(1, store.writes)
    }
    @Test fun reinstallCanRecoverWithoutAnyLocalAccessState() {
        val store = Store()
        resolve(PlayLegacyAccessRecovery(store), true)
        assertTrue(resolve(PlayLegacyAccessRecovery(store), false).legacy)
        assertEquals(1, store.writes)
    }
    @Test fun freshInstallDoesNotGrantOrEnroll() {
        val store = Store()
        assertFalse(resolve(PlayLegacyAccessRecovery(store), false).legacy)
        assertEquals(0, store.writes)
    }
    @Test fun trialsAndPaidOnlyUsersDoNotEnroll() {
        val store = Store()
        repeat(3) { assertFalse(resolve(PlayLegacyAccessRecovery(store), false).legacy) }
        assertNull(store.bytes)
        assertEquals(0, store.writes)
    }
    @Test fun invalidOrFutureMarkersNeverUnlock() {
        val store = Store()
        for (value in listOf("", "true", "StudyBible:existing-free-access:v2", "{\"legacy\":true}", "StudyBible:existing-free-access:v1\n")) {
            store.bytes = value.toByteArray()
            val result = resolve(PlayLegacyAccessRecovery(store), false)
            assertFalse(result.legacy)
            assertFalse(result.unavailable)
        }
        assertEquals(0, store.writes)
    }
    @Test fun readFailureIsUnknownNotAFreeGrantOrConfirmedNewUser() {
        val store = Store().apply { failRead = true }
        val result = resolve(PlayLegacyAccessRecovery(store), false)
        assertFalse(result.legacy)
        assertTrue(result.unavailable)
        assertEquals(0, store.writes)
    }
    @Test fun storageFailureDoesNotRevokeExistingAccessAndCanRetry() {
        val store = Store().apply { failWrite = true }
        val recovery = PlayLegacyAccessRecovery(store)
        assertTrue(resolve(recovery, true).legacy)
        assertNull(store.bytes)
        store.failWrite = false
        assertTrue(resolve(recovery, true).legacy)
        assertNotNull(store.bytes)
        assertEquals(2, store.writes)
    }
    @Test fun successfulEnrollmentIsNotWrittenOnEveryRefresh() {
        val store = Store()
        val recovery = PlayLegacyAccessRecovery(store)
        repeat(3) { assertTrue(resolve(recovery, true).legacy) }
        assertEquals(1, store.writes)
    }
    @Test fun accessDecisionWaitsForRecoveryRead() {
        val store = Store()
        resolve(PlayLegacyAccessRecovery(store), true)
        store.defer = true
        var result: PlayLegacyRecoveryResult? = null
        PlayLegacyAccessRecovery(store).resolve(false) { result = it }
        assertNull(result)
        requireNotNull(store.deferredRead).invoke()
        assertTrue(requireNotNull(result).legacy)
    }
    @Test fun startupEnrollsEstablishedLegacyWithoutReadingOrBilling() {
        val store = Store()
        var localSaved = false
        PlayLegacyAccessRecovery(store).enrollEstablishedLegacy(true) { localSaved = true }
        assertTrue(localSaved)
        assertEquals(0, store.reads)
        assertEquals(1, store.writes)
    }
    @Test fun startupLeavesNewUserStateAndRecoveryStoreUntouched() {
        val store = Store()
        PlayLegacyAccessRecovery(store).enrollEstablishedLegacy(false) { fail("Must not write new-user state") }
        assertEquals(0, store.reads)
        assertEquals(0, store.writes)
    }
    @Test fun failedLocalEnrollmentDoesNotPublishRecoveryMarker() {
        val store = Store()
        try {
            PlayLegacyAccessRecovery(store).enrollEstablishedLegacy(true) { throw IllegalStateException("disk full") }
            fail("Expected failed persistence")
        } catch (_: IllegalStateException) { }
        assertEquals(0, store.writes)
    }
    @Test fun outagePreservesAccessButNeverInterceptsExplicitPaidRestore() {
        val unavailable = PlayLegacyRecoveryResult(false, unavailable = true)
        assertTrue(unavailable.useKnownLocalAccess("initialize", true))
        assertTrue(unavailable.useKnownLocalAccess("refresh", true))
        assertFalse(unavailable.useKnownLocalAccess("restore", true))
        assertFalse(unavailable.useKnownLocalAccess("purchase", true))
        assertFalse(unavailable.useKnownLocalAccess("initialize", false))
    }
}
