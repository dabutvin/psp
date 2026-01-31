"""
Tests for core/models.py utility functions.
"""

import pytest

from core.models import extract_email, extract_price


class TestExtractEmail:
    """Tests for extract_email function."""

    def test_email_in_angle_brackets(self):
        """Should extract email from 'Display Name <email>' format."""
        assert extract_email("Ben Smith <ben@example.com>") == "ben@example.com"
        assert extract_email("coolguy23 <coolguy23@example.com>") == "coolguy23@example.com"
        assert extract_email("jane doe <janedoe@example.org>") == "janedoe@example.org"

    def test_plain_email_address(self):
        """Should return the name if it's just an email address."""
        assert extract_email("someone@example.com") == "someone@example.com"
        assert extract_email("user123@example.org") == "user123@example.org"
        assert extract_email("TestUser@example.net") == "TestUser@example.net"

    def test_email_with_whitespace(self):
        """Should handle emails with leading/trailing whitespace."""
        assert extract_email("  someone@example.com  ") == "someone@example.com"
        assert extract_email("\tsomeone@example.com\n") == "someone@example.com"

    def test_plain_name_no_email(self):
        """Should return None for plain names without email."""
        assert extract_email("Ben Smith") is None
        assert extract_email("Claire Bourgeois") is None
        assert extract_email("Some Random Name") is None

    def test_none_input(self):
        """Should return None for None input."""
        assert extract_email(None) is None

    def test_empty_string(self):
        """Should return None for empty string."""
        assert extract_email("") is None
        assert extract_email("   ") is None

    def test_malformed_email(self):
        """Should return None for malformed email-like strings."""
        assert extract_email("notanemail") is None
        assert extract_email("missing@tld") is None
        assert extract_email("@nodomain.com") is None

    def test_complex_display_names(self):
        """Should handle complex display names with special characters."""
        assert extract_email("O'Brien, Mary <mary@example.com>") == "mary@example.com"
        assert extract_email("Dr. John Smith III <john@example.org>") == "john@example.org"

    def test_email_with_subdomain(self):
        """Should handle emails with subdomains."""
        assert extract_email("user@mail.example.com") == "user@mail.example.com"
        assert extract_email("Name <user@sub.domain.org>") == "user@sub.domain.org"

    def test_email_with_plus_sign(self):
        """Should handle emails with plus signs."""
        assert extract_email("user+tag@example.com") == "user+tag@example.com"
        assert extract_email("Name <user+tag@example.com>") == "user+tag@example.com"


class TestExtractPrice:
    """Tests for extract_price function."""

    def test_dollar_sign_price(self):
        """Should extract prices with dollar sign."""
        assert extract_price("Selling chair for $50", None) == "$50"
        assert extract_price("$100 OBO", None) == "$100"
        assert extract_price(None, "Great condition, asking $25") == "$25"

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
