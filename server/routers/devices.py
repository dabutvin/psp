"""
Devices API router for push notification registration.

Endpoints:
- POST /devices - Register or update a device token
- DELETE /devices/{token} - Unregister a device token
"""

from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field
from slowapi import Limiter
from slowapi.util import get_remote_address

from core.database import get_database
from core.logging import get_logger

logger = get_logger(__name__)
limiter = Limiter(key_func=get_remote_address)

router = APIRouter()


class DeviceRegistration(BaseModel):
    """Request body for registering a device."""
    
    token: str = Field(..., description="APNs device token (hex string)")
    platform: str = Field(default="ios", description="Platform: 'ios' or 'macos'")
    environment: str = Field(default="production", description="APNs environment: 'production' or 'sandbox'")
    hashtag_filters: list[str] | None = Field(
        default=None,
        description="Hashtags to filter notifications (null = all posts)"
    )


class DeviceResponse(BaseModel):
    """Response after device registration."""
    
    token: str
    platform: str
    environment: str
    hashtag_filters: list[str] | None
    enabled: bool
    created_at: datetime
    updated_at: datetime


class DeviceUpdateRequest(BaseModel):
    """Request body for updating device preferences."""
    
    hashtag_filters: list[str] | None = Field(
        default=None,
        description="Hashtags to filter notifications (null = all posts)"
    )
    enabled: bool = Field(default=True, description="Enable or disable notifications")


@router.post("/devices", response_model=DeviceResponse)
@limiter.limit("30/minute")
async def register_device(request: Request, body: DeviceRegistration):
    """
    Register or update a device for push notifications.
    
    If the token already exists, updates the registration.
    
    **Hashtag filters**: 
    - Pass `null` or omit to receive notifications for ALL new posts
    - Pass an array like `["ForSale", "ISO"]` to only get those categories
    """
    db = get_database()
    
    # Validate platform
    if body.platform not in ("ios", "macos"):
        raise HTTPException(status_code=400, detail="Platform must be 'ios' or 'macos'")
    
    # Validate environment
    if body.environment not in ("production", "sandbox"):
        raise HTTPException(status_code=400, detail="Environment must be 'production' or 'sandbox'")
    
    # Validate token format (should be hex string, typically 64 chars for APNs)
    if not body.token or len(body.token) < 32:
        raise HTTPException(status_code=400, detail="Invalid token format")
    
    now = datetime.now(timezone.utc)
    
    # Upsert the device token
    row = await db.fetchrow(
        """
        INSERT INTO device_tokens (token, platform, environment, hashtag_filters, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $5)
        ON CONFLICT (token) DO UPDATE SET
            platform = EXCLUDED.platform,
            environment = EXCLUDED.environment,
            hashtag_filters = EXCLUDED.hashtag_filters,
            updated_at = EXCLUDED.updated_at
        RETURNING token, platform, environment, hashtag_filters, enabled, created_at, updated_at
        """,
        body.token,
        body.platform,
        body.environment,
        body.hashtag_filters,
        now,
    )
    
    logger.info(
        f"Device registered",
        extra={
            "token_prefix": body.token[:8],
            "platform": body.platform,
            "environment": body.environment,
            "has_filters": body.hashtag_filters is not None,
        },
    )
    
    return DeviceResponse(
        token=row["token"],
        platform=row["platform"],
        environment=row["environment"],
        hashtag_filters=row["hashtag_filters"],
        enabled=row["enabled"],
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


@router.patch("/devices/{token}", response_model=DeviceResponse)
@limiter.limit("30/minute")
async def update_device(request: Request, token: str, body: DeviceUpdateRequest):
    """
    Update device notification preferences.
    
    Use this to change hashtag filters or enable/disable notifications.
    """
    db = get_database()
    
    now = datetime.now(timezone.utc)
    
    row = await db.fetchrow(
        """
        UPDATE device_tokens
        SET hashtag_filters = $2,
            enabled = $3,
            updated_at = $4
        WHERE token = $1
        RETURNING token, platform, environment, hashtag_filters, enabled, created_at, updated_at
        """,
        token,
        body.hashtag_filters,
        body.enabled,
        now,
    )
    
    if not row:
        raise HTTPException(status_code=404, detail="Device not found")
    
    logger.info(
        f"Device updated",
        extra={
            "token_prefix": token[:8],
            "enabled": body.enabled,
            "has_filters": body.hashtag_filters is not None,
        },
    )
    
    return DeviceResponse(
        token=row["token"],
        platform=row["platform"],
        environment=row["environment"],
        hashtag_filters=row["hashtag_filters"],
        enabled=row["enabled"],
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


@router.delete("/devices/{token}")
@limiter.limit("30/minute")
async def unregister_device(request: Request, token: str):
    """
    Unregister a device from push notifications.
    
    Call this when the user logs out or uninstalls the app.
    """
    db = get_database()
    
    result = await db.execute(
        "DELETE FROM device_tokens WHERE token = $1",
        token,
    )
    
    # Check if a row was deleted
    if result == "DELETE 0":
        raise HTTPException(status_code=404, detail="Device not found")
    
    logger.info(
        f"Device unregistered",
        extra={"token_prefix": token[:8] if len(token) >= 8 else token},
    )
    
    return {"status": "ok", "message": "Device unregistered"}
