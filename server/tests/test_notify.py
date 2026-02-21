"""
Tests for sync/notify.py push notification module.
"""

import pytest
from unittest.mock import patch, AsyncMock, MagicMock

from sync.notify import send_new_post_notifications, NotificationResult


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
