package com.deanbowen.bibleappmac

/** A mixed clip may start with text or an unreadable URI; try each item. */
internal fun firstReadableClipboardImage(
    itemCount: Int,
    read: (Int) -> ByteArray?,
): ByteArray? {
    for (index in 0 until itemCount) {
        val bytes = try {
            read(index)
        } catch (_: java.io.IOException) {
            null
        } catch (_: SecurityException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }
        if (bytes != null && bytes.isNotEmpty()) return bytes
    }
    return null
}
