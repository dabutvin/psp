"""
Tests for price extraction logic.
"""

import pytest

from core.price import extract_price


class TestExtractPrice:
    """Tests for extract_price function."""

    def test_dollar_sign_price(self):
        """Should extract prices with dollar sign."""
        assert extract_price("Selling chair for $50", None) == "$50"
        assert extract_price("$100 OBO", None) == "$100"
        assert extract_price(None, "Great condition, asking $25") == "asking $25"

    def test_price_with_decimals(self):
        """Should extract prices with decimal amounts."""
        assert extract_price("Only $19.99!", None) == "$19.99"
        assert extract_price("$1,000.00 firm", None) == "$1,000.00"

    def test_price_with_commas(self):
        """Should extract prices with thousand separators."""
        assert extract_price("Asking $1,500", None) == "$1,500"
        assert extract_price("$2,000 or best offer", None) == "$2,000"

    def test_asking_price_format(self):
        """Should extract 'asking X' format (without dollar sign)."""
        # When there's a $, the $ pattern matches first
        assert extract_price("asking $50", None) == "$50"
        # Without $, the 'asking' pattern matches
        assert extract_price("Asking 100 for it", None) == "Asking 100"

    def test_dollars_word(self):
        """Should extract prices with 'dollars' word."""
        assert extract_price("50 dollars", None) == "50 dollars"
        assert extract_price("100 Dollars OBO", None) == "100 Dollars"

    def test_obo_format(self):
        """Should extract prices with OBO."""
        assert extract_price("40 obo", None) == "40 obo"
        assert extract_price("$75 OBO", None) == "$75"

    def test_price_in_body_fallback(self):
        """Should find price in body if not in subject."""
        assert extract_price("For Sale: Chair", "Nice chair, $50") == "$50"

    def test_no_price(self):
        """Should return None when no price found."""
        assert extract_price("Free baby clothes", "Giving away") is None
        assert extract_price("ISO: Double stroller", "Looking for one") is None

    def test_none_inputs(self):
        """Should handle None inputs."""
        assert extract_price(None, None) is None
        assert extract_price("", "") is None


class TestExtractPriceMultiplePrices:
    """Tests for extract_price when multiple prices appear in text."""

    # (subject, body, expected_price)
    CASES = [
        # Retail price first, asking price last - should prefer asking price
        (
            None,
            "Refurbished same model retails >$550. Asking $300",
            "Asking $300",
        ),
        (
            None,
            "Originally paid $200, selling for $75",
            "selling for $75",
        ),
        (
            None,
            "Worth $100, asking $40",
            "asking $40",
        ),
        # Asking price first, retail price last - should still get asking price
        (
            None,
            "Asking $300. Refurbished same model retails >$550",
            "Asking $300",
        ),
        (
            None,
            "Selling for $75, originally paid $200",
            "Selling for $75",
        ),
        (
            None,
            "Asking $40, worth $100 new",
            "Asking $40",
        ),
        # Multiple items with prices - takes first asking
        (
            None,
            "iPhone 15 Pro Max retails >$550 Asking $300. iPhone 14 retails >$275 Asking $150",
            "Asking $300",
        ),
        # Price in subject should still work
        (
            "FS: Stroller $200",
            "Retail price was $400, great condition",
            "$200",
        ),
        # OBO pattern
        (
            None,
            "Paid $500 new. $150 OBO",
            "$150 OBO",
        ),
        # Single price still works
        (
            "Selling for $50",
            None,
            "$50",
        ),
        # No keyword, 2 prices - should return lower (selling price)
        (
            None,
            "Retail $100. $40",
            "$40",
        ),
        # No keyword, 2 prices reversed - should still return lower
        (
            None,
            "$40. Retail $100",
            "$40",
        ),
        # 3+ prices with no keyword - should bail out (return None)
        (
            None,
            "Item 1 $50, Item 2 $75, Item 3 $100",
            None,
        ),
        # 3+ prices but subject has price - use subject
        (
            "Bundle $200",
            "Item 1 $50, Item 2 $75, Item 3 $100",
            "$200",
        ),
        # Real example: "hoping for" implies asking price, paid price is higher
        (
            "FS: Armadillo baby carrier",
            "We bought it for $275 and barely used it, hoping for $200. Pick up only",
            "hoping for $200",
        ),
        # Recurring price (rental) should take precedence over one-time fee
        (
            "Great Barrington Rental",
            "The rate is $349 per evening + $160 cleaning fee",
            "$349 per evening",
        ),
    ]

    @pytest.mark.parametrize("subject,body,expected", CASES)
    def test_multiple_prices(self, subject, body, expected):
        """Should extract the correct price when multiple prices appear."""
        assert extract_price(subject, body) == expected
