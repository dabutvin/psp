"""
Tests for core/models.py utility functions.
"""

import pytest

from core.models import extract_email


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
