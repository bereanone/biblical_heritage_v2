package com.deanbowen.bibleappmac

import org.junit.Assert.*
import org.junit.Test

class ClipboardImageReaderTest {
    private val image = byteArrayOf(1, 2, 3)

    @Test fun emptyClipboardDoesNotReadAnything() {
        assertNull(firstReadableClipboardImage(0) { error("No items") })
    }
    @Test fun textBeforeImageDoesNotHideTheImage() {
        assertArrayEquals(image, firstReadableClipboardImage(2) { if (it == 1) image else null })
    }
    @Test fun inaccessibleFirstItemDoesNotHideLaterImage() {
        assertArrayEquals(image, firstReadableClipboardImage(2) {
            if (it == 0) throw SecurityException("No permission") else image
        })
    }
    @Test fun deletedItemDoesNotHideLaterImage() {
        assertArrayEquals(image, firstReadableClipboardImage(2) {
            if (it == 0) throw java.io.FileNotFoundException() else image
        })
    }
    @Test fun emptyOrUndecodableItemsDoNotPretendToBeImages() {
        assertNull(firstReadableClipboardImage(2) { if (it == 0) byteArrayOf() else null })
    }
    @Test fun firstValidImageWinsWithoutReadingRemainingItems() {
        assertArrayEquals(image, firstReadableClipboardImage(3) {
            if (it > 0) error("Should stop after first image") else image
        })
    }
}
