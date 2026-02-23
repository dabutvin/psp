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
from core.search import get_devices_matching_post, remove_device_token

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


@dataclass
class NotificationResult:
    """Result of a notification send attempt."""
    token: str
    success: bool
    expired: bool = False


class APNsClient:
    """
    Apple Push Notification service client using HTTP/2.
    
    Uses JWT-based authentication (token-based, not certificate-based).
    Reuses HTTP/2 connection for efficiency.
    """
    
    PRODUCTION_URL = "https://api.push.apple.com"
    SANDBOX_URL = "https://api.sandbox.push.apple.com"
    
    # JWT tokens are valid for up to 1 hour, we refresh at 50 minutes
    TOKEN_REFRESH_INTERVAL = 50 * 60
    
    # Concurrency limit for parallel notifications
    MAX_CONCURRENT_SENDS = 10
    
    def __init__(self, config: APNsConfig):
        self.config = config
        self._token: str | None = None
        self._token_created_at: float = 0
        self._private_key = config.get_private_key()
        self._http_client: httpx.AsyncClient | None = None
    
    async def __aenter__(self) -> "APNsClient":
        """Enter async context - create HTTP/2 client."""
        self._http_client = httpx.AsyncClient(http2=True, timeout=30.0)
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb) -> None:
        """Exit async context - close HTTP/2 client."""
        if self._http_client:
            await self._http_client.aclose()
            self._http_client = None
    
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
    ) -> NotificationResult:
        """
        Send a push notification to a single device.
        
        Args:
            device_token: APNs device token (hex string)
            title: Notification title
            body: Notification body text
            data: Custom data payload (will be in notification userInfo)
            environment: 'production' or 'sandbox'
        
        Returns:
            NotificationResult with success status and whether token expired
        """
        if not self._http_client:
            raise RuntimeError("APNsClient must be used as async context manager")
        
        base_url = self.PRODUCTION_URL if environment == "production" else self.SANDBOX_URL
        url = f"{base_url}/3/device/{device_token}"
        
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
            response = await self._http_client.post(url, json=payload, headers=headers)
            
            if response.status_code == 200:
                return NotificationResult(token=device_token, success=True)
            
            if response.status_code == 410:
                logger.warning(
                    "Device token expired/invalid",
                    extra={"token_prefix": device_token[:8], "status": 410},
                )
                return NotificationResult(token=device_token, success=False, expired=True)
            
            if response.status_code == 400:
                error_body = response.json() if response.content else {}
                logger.error(
                    "APNs bad request",
                    extra={"token_prefix": device_token[:8], "error": error_body},
                )
            else:
                logger.error(
                    "APNs request failed",
                    extra={
                        "token_prefix": device_token[:8],
                        "status": response.status_code,
                        "body": response.text[:200] if response.text else None,
                    },
                )
            
            return NotificationResult(token=device_token, success=False)
                
        except Exception as e:
            logger.error(f"APNs request exception: {e}", extra={"token_prefix": device_token[:8]})
            return NotificationResult(token=device_token, success=False)


async def send_new_post_notifications(messages: list[dict]) -> int:
    """
    Send push notifications for new posts to registered devices.
    
    Uses full-text search matching (same as the search API) to determine
    which devices should receive notifications based on their search_filters.
    
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
    
    db = get_database()
    await db.connect()
    
    logger.info(f"Processing notifications for {len(messages)} new posts")
    
    # Collect all notification tasks: (device, title, body, data)
    notification_tasks: list[tuple[dict, str, str, dict]] = []
    
    for message in messages:
        msg_id = message["id"]
        subject = message.get("subject", "New Post")
        msg_hashtags = {h.lower() for h in message.get("hashtags", [])}
        
        devices = await get_devices_matching_post(db, msg_id)
        
        if not devices:
            continue
        
        title = subject[:100] if subject else "New Post"
        body = "Tap to view"
        
        if "forsale" in msg_hashtags:
            body = "New item for sale"
        elif "forfree" in msg_hashtags:
            body = "New free item"
        elif "iso" in msg_hashtags:
            body = "Someone is looking for something"
        
        for device in devices:
            notification_tasks.append((device, title, body, {"post_id": msg_id}))
    
    if not notification_tasks:
        logger.info("No devices to notify")
        return 0
    
    logger.info(f"Sending {len(notification_tasks)} notifications")
    
    sent_count = 0
    expired_tokens: list[str] = []
    
    async with APNsClient(config) as client:
        # Process in batches to limit concurrency
        semaphore = asyncio.Semaphore(APNsClient.MAX_CONCURRENT_SENDS)
        
        async def send_one(device: dict, title: str, body: str, data: dict) -> NotificationResult:
            async with semaphore:
                return await client.send_notification(
                    device_token=device["token"],
                    title=title,
                    body=body,
                    data=data,
                    environment=device["environment"],
                )
        
        results = await asyncio.gather(*[
            send_one(device, title, body, data)
            for device, title, body, data in notification_tasks
        ])
        
        for result in results:
            if result.success:
                sent_count += 1
            elif result.expired:
                expired_tokens.append(result.token)
    
    # Remove expired tokens from database
    if expired_tokens:
        logger.info(f"Removing {len(expired_tokens)} expired device tokens")
        for token in expired_tokens:
            await remove_device_token(db, token)
    
    logger.info(f"Sent {sent_count} notifications")
    return sent_count


def send_new_post_notifications_sync(messages: list[dict]) -> int:
    """
    Synchronous wrapper for send_new_post_notifications.
    
    Use this from synchronous code (like fetch.py).
    """
    try:
        loop = asyncio.get_running_loop()
        # We're in an async context - this shouldn't happen in CLI fetch
        logger.warning("Cannot run async notification from running loop")
        return 0
    except RuntimeError:
        # No running loop - safe to use asyncio.run()
        return asyncio.run(send_new_post_notifications(messages))


async def get_summary_devices(db) -> list[dict]:
    """
    Get all devices that have summary notifications enabled.
    
    Returns:
        List of dicts with 'token' and 'environment' keys
    """
    rows = await db.fetch("""
        SELECT token, environment
        FROM device_tokens
        WHERE enabled = TRUE AND notify_summary = TRUE
    """)
    return [{"token": row["token"], "environment": row["environment"]} for row in rows]


def _build_summary_body(messages: list[dict], max_length: int = 100) -> str:
    """
    Build a summary body text from a list of messages.
    
    Truncates subjects and adds ellipsis if the combined text exceeds max_length.
    
    Args:
        messages: List of message dicts with 'subject' key
        max_length: Maximum length of the resulting body text
    
    Returns:
        Summary body like "FS: Stroller, FF: Books, ISO: Crib..."
    """
    if not messages:
        return "Tap to view"
    
    subjects = []
    current_length = 0
    
    for msg in messages:
        subject = msg.get("subject", "New Post")
        # Truncate individual subjects to keep them reasonable
        if len(subject) > 40:
            subject = subject[:37] + "..."
        
        # Check if adding this subject would exceed the limit
        separator = ", " if subjects else ""
        needed_length = len(separator) + len(subject)
        
        if current_length + needed_length > max_length - 3:  # -3 for "..."
            break
        
        subjects.append(subject)
        current_length += needed_length
    
    result = ", ".join(subjects)
    
    # Add ellipsis if we didn't include all messages
    if len(subjects) < len(messages):
        result += "..."
    
    return result if result else "Tap to view"


async def send_summary_notifications(messages: list[dict]) -> int:
    """
    Send summary push notifications to devices with notify_summary enabled.
    
    Sends a single notification per device containing a summary of all new posts.
    
    Args:
        messages: List of message dicts with keys: id, subject, hashtags (list of names)
    
    Returns:
        Number of notifications sent successfully
    """
    if not messages:
        return 0
    
    config = APNsConfig.from_settings()
    if not config:
        logger.debug("APNs not configured, skipping summary notifications")
        return 0
    
    db = get_database()
    await db.connect()
    
    devices = await get_summary_devices(db)
    
    if not devices:
        logger.debug("No devices subscribed to summary notifications")
        return 0
    
    logger.info(f"Sending summary notifications to {len(devices)} devices for {len(messages)} posts")
    
    # Build the summary notification content
    count = len(messages)
    title = f"{count} new post{'s' if count != 1 else ''}"
    body = _build_summary_body(messages)
    
    # Include all post IDs in the data payload
    post_ids = [msg["id"] for msg in messages]
    data = {
        "type": "summary",
        "post_ids": post_ids,
    }
    
    sent_count = 0
    expired_tokens: list[str] = []
    
    async with APNsClient(config) as client:
        semaphore = asyncio.Semaphore(APNsClient.MAX_CONCURRENT_SENDS)
        
        async def send_one(device: dict) -> NotificationResult:
            async with semaphore:
                return await client.send_notification(
                    device_token=device["token"],
                    title=title,
                    body=body,
                    data=data,
                    environment=device["environment"],
                )
        
        results = await asyncio.gather(*[send_one(device) for device in devices])
        
        for result in results:
            if result.success:
                sent_count += 1
            elif result.expired:
                expired_tokens.append(result.token)
    
    # Remove expired tokens from database
    if expired_tokens:
        logger.info(f"Removing {len(expired_tokens)} expired device tokens")
        for token in expired_tokens:
            await remove_device_token(db, token)
    
    logger.info(f"Sent {sent_count} summary notifications")
    return sent_count


def send_summary_notifications_sync(messages: list[dict]) -> int:
    """
    Synchronous wrapper for send_summary_notifications.
    
    Use this from synchronous code (like fetch.py).
    """
    try:
        loop = asyncio.get_running_loop()
        logger.warning("Cannot run async summary notification from running loop")
        return 0
    except RuntimeError:
        return asyncio.run(send_summary_notifications(messages))


async def _send_all_notifications(messages: list[dict]) -> tuple[int, int]:
    """Send both individual and summary notifications in a single async context."""
    individual_sent = await send_new_post_notifications(messages)
    summary_sent = await send_summary_notifications(messages)
    return individual_sent, summary_sent


def send_all_notifications_sync(messages: list[dict]) -> tuple[int, int]:
    """
    Send both individual and summary notifications from synchronous code.
    
    Runs both in a single asyncio.run() so they share the same event loop
    and database connection pool.
    """
    try:
        asyncio.get_running_loop()
        logger.warning("Cannot run async notifications from running loop")
        return 0, 0
    except RuntimeError:
        return asyncio.run(_send_all_notifications(messages))
