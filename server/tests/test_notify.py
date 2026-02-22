"""
Tests for sync/notify.py push notification module.
"""

import pytest
from unittest.mock import patch, AsyncMock, MagicMock

from sync.notify import send_new_post_notifications, NotificationResult, _build_summary_body


class TestSendNewPostNotifications:
    """Tests for send_new_post_notifications function."""

    @pytest.mark.asyncio
    async def test_returns_zero_for_empty_messages(self):
        """Should return 0 when no messages are provided."""
        result = await send_new_post_notifications([])
        
        assert result == 0

    @pytest.mark.asyncio
    async def test_sends_notifications_to_matching_devices(self):
        """Should send notifications and return count of successful sends."""
        mock_config = MagicMock()
        mock_config.get_private_key.return_value = "fake-key"
        
        mock_db = MagicMock()
        mock_db.connect = AsyncMock()
        
        mock_client = MagicMock()
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=None)
        mock_client.send_notification = AsyncMock(
            return_value=NotificationResult(token="abc123", success=True)
        )
        
        mock_apns_class = MagicMock(return_value=mock_client)
        mock_apns_class.MAX_CONCURRENT_SENDS = 10
        
        with patch("sync.notify.APNsConfig.from_settings", return_value=mock_config), \
             patch("sync.notify.get_database", return_value=mock_db), \
             patch("sync.notify.get_devices_matching_post", new_callable=AsyncMock) as mock_get_devices, \
             patch("sync.notify.APNsClient", mock_apns_class):
            
            mock_get_devices.return_value = [{"token": "abc123", "environment": "production"}]
            
            result = await send_new_post_notifications([
                {"id": 1, "subject": "For Sale: Chair", "hashtags": ["forsale"]}
            ])
        
        assert result == 1


class TestBuildSummaryBody:
    """Tests for _build_summary_body function."""

    def test_empty_messages_returns_tap_to_view(self):
        """Should return 'Tap to view' for empty message list."""
        assert _build_summary_body([]) == "Tap to view"

    def test_single_message(self):
        """Should return just the subject for a single message."""
        messages = [{"subject": "FS: Stroller"}]
        assert _build_summary_body(messages) == "FS: Stroller"

    def test_multiple_messages(self):
        """Should join multiple subjects with commas."""
        messages = [
            {"subject": "FS: Stroller"},
            {"subject": "FF: Books"},
        ]
        assert _build_summary_body(messages) == "FS: Stroller, FF: Books"

    def test_truncates_long_subjects(self):
        """Should truncate individual subjects longer than 40 chars."""
        messages = [{"subject": "A" * 50}]
        result = _build_summary_body(messages)
        assert len(result) <= 40
        assert result.endswith("...")

    def test_adds_ellipsis_when_truncated(self):
        """Should add ellipsis when not all messages fit."""
        messages = [
            {"subject": "FS: Item One"},
            {"subject": "FF: Item Two"},
            {"subject": "ISO: Item Three"},
            {"subject": "FS: Item Four"},
            {"subject": "FF: Item Five"},
        ]
        result = _build_summary_body(messages, max_length=50)
        assert result.endswith("...")

    def test_respects_max_length(self):
        """Should not exceed max_length."""
        messages = [
            {"subject": "FS: Stroller"},
            {"subject": "FF: Books"},
            {"subject": "ISO: Crib"},
        ]
        result = _build_summary_body(messages, max_length=30)
        assert len(result) <= 30
