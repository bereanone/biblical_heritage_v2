package com.deanbowen.bibleappmac

/** Installation-local migration rights, separate from Google purchase ownership. */
object PlayLegacyAccessPolicy {
    fun allows(
        hadSavedAccessState: Boolean,
        savedLegacy: Boolean,
        firstInstallTime: Long,
        lastUpdateTime: Long,
        originalCutoff: Long,
    ): Boolean = savedLegacy ||
        (originalCutoff > 0 && firstInstallTime > 0 && firstInstallTime < originalCutoff) ||
        (!hadSavedAccessState && firstInstallTime > 0 && lastUpdateTime > firstInstallTime)
}
