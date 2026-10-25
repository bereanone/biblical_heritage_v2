package com.deanbowen.bibleappmac
import org.junit.Assert.*
import org.junit.Test
class PlayOfferSelectorTest {
    private val offers = listOf(
        PlayOfferCandidate("permanent-access", "hh", "hh-token"),
        PlayOfferCandidate("permanent-access", "adl", "adl-token"),
        PlayOfferCandidate("permanent-access", null, "regular-token")
    )
    @Test fun matchingMinistryOnly() {
        assertEquals(1, PlayOfferSelector.select(offers, "adl"))
        assertEquals(0, PlayOfferSelector.select(offers, "heritage_and_hope"))
        assertEquals(2, PlayOfferSelector.select(offers, null))
        assertEquals(2, PlayOfferSelector.select(offers, "unknown"))
    }
    @Test fun missingDiscountFallsBackToRegularNotOtherMinistry() {
        assertEquals(1, PlayOfferSelector.select(listOf(offers[0], offers[2]), "adl"))
        assertNull(PlayOfferSelector.select(listOf(offers[0]), "adl"))
    }
    @Test fun incorrectPurchaseOptionAndEmptyTokenCannotBeSelected() {
        assertNull(PlayOfferSelector.select(listOf(
            PlayOfferCandidate("rent", "adl", "token"),
            PlayOfferCandidate("permanent-access", "adl", "")
        ), "adl"))
    }
}
