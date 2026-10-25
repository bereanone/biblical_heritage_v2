package com.deanbowen.bibleappmac

import org.junit.Assert.*
import org.junit.Test

class PlayLegacyAccessPolicyTest {
    @Test fun oldFreeInstallBeforeCutoffKeepsAccess() {
        assertTrue(PlayLegacyAccessPolicy.allows(false, false, 100, 400, 200))
    }
    @Test fun oldFreeInstallDuringUploadAndReviewKeepsAccess() {
        assertTrue(PlayLegacyAccessPolicy.allows(false, false, 300, 400, 200))
    }
    @Test fun freshPaidEditionInstallDoesNotGetFreePermanentAccess() {
        assertFalse(PlayLegacyAccessPolicy.allows(false, false, 300, 300, 200))
    }
    @Test fun laterUpdateDoesNotUnlockAnExistingTrialOrExpiredTrial() {
        assertFalse(PlayLegacyAccessPolicy.allows(true, false, 300, 500, 200))
    }
    @Test fun migratedFreeAccessPersistsOnSubsequentLaunches() {
        assertTrue(PlayLegacyAccessPolicy.allows(true, true, 300, 500, 200))
    }
    @Test fun missingInstallTimeDoesNotImplyAnUpdate() {
        assertFalse(PlayLegacyAccessPolicy.allows(false, false, 0, 500, 0))
    }
    @Test fun missingInstallTimeCannotQualifyAgainstAConfiguredCutoff() {
        assertFalse(PlayLegacyAccessPolicy.allows(false, false, 0, 500, 200))
        assertFalse(PlayLegacyAccessPolicy.allows(false, false, -1, 500, 200))
    }
    @Test fun freeUpgradeCapturedWithFirstBillingWriteSurvivesRestart() {
        // First write can be Google's no-purchase result, before snapshot runs.
        val capturedLegacy = PlayLegacyAccessPolicy.allows(false, false, 300, 400, 200)
        // The restarted process now sees a saved state file.
        assertTrue(PlayLegacyAccessPolicy.allows(true, capturedLegacy, 300, 400, 200))
    }
    @Test fun freshInstallAtCutoffIsNotAnOriginalFreeInstall() {
        assertFalse(PlayLegacyAccessPolicy.allows(false, false, 200, 200, 200))
    }
    @Test fun reinstallWithoutRecoverableEvidenceDoesNotInventLegacyRights() {
        assertFalse(PlayLegacyAccessPolicy.allows(false, false, 600, 600, 200))
    }
}
