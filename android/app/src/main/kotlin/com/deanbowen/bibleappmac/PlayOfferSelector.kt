package com.deanbowen.bibleappmac

internal data class PlayOfferCandidate(val purchaseOptionId: String?, val offerId: String?, val token: String)

/** Choose only the saved ministry's offer, never the cheapest unrelated offer.
 * Play already filters country, dates and purchase limits. Ministry codes are
 * local promotional eligibility, not proof of purchase or authenticated membership. */
internal object PlayOfferSelector {
    fun select(offers: List<PlayOfferCandidate>, ministryId: String?): Int? {
        val wanted = when (ministryId) {
            "adl" -> "adl"
            "heritage_and_hope" -> "hh"
            else -> null
        }
        fun eligible(offer: PlayOfferCandidate) =
            offer.purchaseOptionId == "permanent-access" && offer.token.isNotBlank()
        if (wanted != null) {
            val matched = offers.indexOfFirst { eligible(it) && it.offerId == wanted }
            if (matched >= 0) return matched
        }
        return offers.indexOfFirst { eligible(it) && it.offerId == null }.takeIf { it >= 0 }
    }
}
