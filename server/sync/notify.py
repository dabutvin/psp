"""
Push notification module for PSP server.
Sends APNs notifications when new posts are fetched.
"""

import asyncio
import json
import time
from dataclasses import dataclass
from pathlib import Path

import httpx
import jwt

from core.config import get_settings
from core.database import get_database
from core.logging import get_logger

logger = get_logger(__name__)


@dataclass
class APNsConfig:
    """APNs configuration from environment."""
    
    key_id: str           # 10-character key ID from Apple
    team_id: str          # 10-character team ID from Apple
    key_path: str | None  # Path to .p8 key file
    key_content: str | None  # Or the key content directly (for secrets)
    bundle_id: str        # App bundle ID (e.g., com.psp.classifieds)
    
    @classmethod
    def from_settings(cls) -> "APNsConfig | None":
        """Load APNs config from settings. Returns None if not configured."""
        settings = get_settings()
        
        key_id = getattr(settings, "apns_key_id", None)
        team_id = getattr(settings, "apns_team_id", None)
        bundle_id = getattr(settings, "apns_bundle_id", None)
        
        if not all([key_id, team_id, bundle_id]):
            return None
        
        return cls(
            key_id=key_id,
            team_id=team_id,
            key_path=getattr(settings, "apns_key_path", None),
            key_content=getattr(settings, "apns_key_content", None),
            bundle_id=bundle_id,
        )
    
    def get_private_key(self) -> str:
        """Get the private key content."""
        if self.key_content:
            return self.key_content
        if self.key_path:
            return Path(self.key_path).read_text()
        raise ValueError("No APNs key configured (set APNS_KEY_PATH or APNS_KEY_CONTENT)")


class APNsClient:
    """
    Apple Push Notification service client using HTTP/2.
    
    Uses JWT-based authentication (token-based, not certificate-based).
    """
    
    PRODUCTION_URL = "https://api.push.apple.com"
    SANDBOX_URL = "https://api.sandbox.push.apple.com"
    
    # JWT tokens are valid for up to 1 hour, we refresh at 50 minutes
    TOKEN_REFRESH_INTERVAL = 50 * 60
    
    def __init__(self, config: APNsConfig):
        self.config = config
        self._token: str | None = None
        self._token_created_at: float = 0
        self._private_key = config.get_private_key()
    
    def _generate_token(self) -> str:
        """Generate a new JWT token for APNs authentication."""
        now = int(time.time())
        
        headers = {
            "alg": "ES256",
            "kid": self.config.key_id,
        }
        
        payload = {
            "iss": self.config.team_id,
            "iat": now,
        }
        
        token = jwt.encode(payload, self._private_key, algorithm="ES256", headers=headers)
        self._token = token
        self._token_created_at = now
        
        return token
    
    def _get_token(self) -> str:
        """Get a valid JWT token, refreshing if needed."""
        now = time.time()
        
        if self._token and (now - self._token_created_at) < self.TOKEN_REFRESH_INTERVAL:
            return self._token
        
        return self._generate_token()
    
    async def send_notification(
        self,
        device_token: str,
        title: str,
        body: str,
        data: dict | None = None,
        environment: str = "production",
    ) -> bool:
        """
        Send a push notification to a single device.
        
        Args:
            device_token: APNs device token (hex string)
            title: Notification title
            body: Notification body text
            data: Custom data payload (will be in notification userInfo)
            environment: 'production' or 'sandbox'
        
        Returns:
            True if successful, False otherwise
        """
        base_url = self.PRODUCTION_URL if environment == "production" else self.SANDBOX_URL
        url = f"{base_url}/3/device/{device_token}"
        
        # Build the APNs payload
        payload = {
            "aps": {
                "alert": {
                    "title": title,
                    "body": body,
                },
                "sound": "default",
                "badge": 1,
            }
        }
        
        if data:
            payload.update(data)
        
        headers = {
            "authorization": f"bearer {self._get_token()}",
            "apns-topic": self.config.bundle_id,
            "apns-push-type": "alert",
            "apns-priority": "10",
        }
        
        try:
            async with httpx.AsyncClient(http2=True) as client:
                response = await client.post(
                    url,
                    json=payload,
                    headers=headers,
                    timeout=30.0,
                )
                
                if response.status_code == 200:
                    return True
                
                # Handle specific error codes
                if response.status_code == 410:
                    # Device token is no longer valid - should be removed
                    logger.warning(
                        f"Device token expired/invalid, should remove",
                        extra={"token_prefix": device_token[:8], "status": 410},
                    )
                elif response.status_code == 400:
                    error_body = response.json() if response.content else {}
                    logger.error(
                        f"APNs bad request",
                        extra={"token_prefix": device_token[:8], "error": error_body},
                    )
                else:
                    logger.error(
                        f"APNs request failed",
                        extra={
                            "token_prefix": device_token[:8],
                            "status": response.status_code,
                            "body": response.text[:200] if response.text else None,
                        },
                    )
                
                return False
                
        except Exception as e:
            logger.error(f"APNs request exception: {e}", extra={"token_prefix": device_token[:8]})
            return False


async def send_new_post_notifications(messages: list[dict]) -> int:
    """
    Send push notifications for new posts to registered devices.
    
    Args:
        messages: List of message dicts with keys: id, subject, hashtags (list of names)
    
    Returns:
        Number of notifications sent successfully
    """
    if not messages:
        return 0
    
    config = APNsConfig.from_settings()
    if not config:
        logger.debug("APNs not configured, skipping notifications")
        return 0
    
    client = APNsClient(config)
    db = get_database()
    
    # Ensure database is connected
    await db.connect()
    
    # Get all enabled device tokens
    devices = await db.fetch(
        """
        SELECT token, environment, hashtag_filters
        FROM device_tokens
        WHERE enabled = TRUE
        """
    )
    
    if not devices:
        logger.debug("No devices registered for notifications")
        return 0
    
    logger.info(f"Sending notifications for {len(messages)} new posts to {len(devices)} devices")
    
    sent_count = 0
    invalid_tokens = []
    
    for message in messages:
        msg_id = message["id"]
        subject = message.get("subject", "New Post")
        msg_hashtags = {h.lower() for h in message.get("hashtags", [])}
        
        # Truncate subject for notification
        title = subject[:100] if subject else "New Post"
        body = "Tap to view"
        
        # Determine category for the notification body
        if "forsale" in msg_hashtags:
            body = "New item for sale"
        elif "forfree" in msg_hashtags:
            body = "New free item"
        elif "iso" in msg_hashtags:
            body = "Someone is looking for something"
        
        for device in devices:
            token = device["token"]
            environment = device["environment"]
            filters = device["hashtag_filters"]
            
            # Check if this device wants this notification
            if filters:
                # Device has filters - check if any match
                filter_set = {f.lower() for f in filters}
                if not filter_set.intersection(msg_hashtags):
                    continue  # Skip - no matching hashtags
            
            # Send the notification
            success = await client.send_notification(
                device_token=token,
                title=title,
                body=body,
                data={"post_id": msg_id},
                environment=environment,
            )
            
            if success:
                sent_count += 1
            else:
                # Track potentially invalid tokens for cleanup
                # (In production, you'd want more sophisticated handling)
                pass
    
    logger.info(f"Sent {sent_count} notifications")
    return sent_count


def send_new_post_notifications_sync(messages: list[dict]) -> int:
    """
    Synchronous wrapper for send_new_post_notifications.
    
    Use this from synchronous code (like fetch.py).
    """
    try:
        # Try to get existing event loop
        loop = asyncio.get_event_loop()
        if loop.is_running():
            # We're in an async context, create a new task
            # This shouldn't happen in the CLI fetch context
            logger.warning("Cannot run async notification from running loop")
            return 0
        return loop.run_until_complete(send_new_post_notifications(messages))
    except RuntimeError:
        # No event loop, create one
        return asyncio.run(send_new_post_notifications(messages))
