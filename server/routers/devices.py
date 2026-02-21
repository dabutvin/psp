"""
Devices API router for push notification registration.

Endpoints:
- POST /devices - Register a device token
- GET /devices/{token} - Get device subscription settings
- PATCH /devices/{token} - Update device preferences
- DELETE /devices/{token} - Unregister a device token
"""

import re
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from slowapi import Limiter
from slowapi.util import get_remote_address

from core.database import get_database
from core.logging import get_logger
from core.search import validate_search_filters

logger = get_logger(__name__)
limiter = Limiter(key_func=get_remote_address)

router = APIRouter()


class DeviceRegistration(BaseModel):
    """Request body for registering a device."""
    
    token: str = Field(..., description="APNs device token (hex string)")
    platform: str = Field(default="ios", description="Platform: 'ios' or 'macos'")
    environment: str = Field(default="production", description="APNs environment: 'production' or 'sandbox'")
    search_filters: list[str] | None = Field(
        default=None,
        description="Search terms to filter notifications (max 20, each max 100 chars)"
    )
    notify_all: bool = Field(
        default=False,
        description="If true, receive notifications for ALL new posts"
    )


class DeviceResponse(BaseModel):
    """Response with device settings."""
    
    token: str
    platform: str
    environment: str
    search_filters: list[str] | None
    notify_all: bool
    enabled: bool
    created_at: datetime
    updated_at: datetime


class DeviceUpdateRequest(BaseModel):
    """Request body for updating device preferences."""
    
    search_filters: list[str] | None = Field(
        default=None,
        description="Search terms to filter notifications (null = don't change, [] = clear)"
    )
    notify_all: bool | None = Field(
        default=None,
        description="If true, receive notifications for ALL new posts (null = don't change)"
    )
    enabled: bool | None = Field(
        default=None,
        description="Master on/off switch for notifications (null = don't change)"
    )


def _row_to_response(row) -> DeviceResponse:
    """Convert a database row to DeviceResponse."""
    return DeviceResponse(
        token=row["token"],
        platform=row["platform"],
        environment=row["environment"],
        search_filters=row["search_filters"],
        notify_all=row["notify_all"],
        enabled=row["enabled"],
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


@router.post("/devices", response_model=DeviceResponse)
@limiter.limit("30/minute")
async def register_device(request: Request, body: DeviceRegistration):
    """
    Register or update a device for push notifications.
    
    If the token already exists, updates the registration.
    
    **Notification behavior**:
    - `notify_all = true`: Receive notifications for ALL new posts
    - `notify_all = false` with `search_filters`: Only notify when posts match search terms
    - `notify_all = false` with no `search_filters`: No notifications
    
    Search filters use full-text search with English stemming, so "stroller" 
    will match posts containing "strollers", "stroller's", etc.
    """
    db = get_database()
    
    # Validate platform
    if body.platform not in ("ios", "macos"):
        raise HTTPException(status_code=400, detail="Platform must be 'ios' or 'macos'")
    
    # Validate environment
    if body.environment not in ("production", "sandbox"):
        raise HTTPException(status_code=400, detail="Environment must be 'production' or 'sandbox'")
    
    # Validate token format (APNs tokens are 64 hex characters)
    if not body.token or not re.match(r'^[0-9a-fA-F]{64}$', body.token):
        raise HTTPException(status_code=400, detail="Invalid token format: must be 64 hex characters")
    
    # Validate and normalize search filters
    try:
        search_filters = validate_search_filters(body.search_filters)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    
    now = datetime.now(timezone.utc)
    
    # Upsert the device token
    row = await db.fetchrow(
        """
        INSERT INTO device_tokens (token, platform, environment, search_filters, notify_all, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $6)
        ON CONFLICT (token) DO UPDATE SET
            platform = EXCLUDED.platform,
            environment = EXCLUDED.environment,
            search_filters = EXCLUDED.search_filters,
            notify_all = EXCLUDED.notify_all,
            updated_at = EXCLUDED.updated_at
        RETURNING token, platform, environment, search_filters, notify_all, enabled, created_at, updated_at
        """,
        body.token,
        body.platform,
        body.environment,
        search_filters,
        body.notify_all,
        now,
    )
    
    logger.info(
        "Device registered",
        extra={
            "token_prefix": body.token[:8],
            "platform": body.platform,
            "environment": body.environment,
            "notify_all": body.notify_all,
            "search_filter_count": len(search_filters) if search_filters else 0,
        },
    )
    
    return _row_to_response(row)


@router.get("/devices/{token}", response_model=DeviceResponse)
@limiter.limit("60/minute")
async def get_device(request: Request, token: str):
    """
    Get current device subscription settings.
    
    Use this to sync the app's local state with the server.
    """
    db = get_database()
    
    row = await db.fetchrow(
        """
        SELECT token, platform, environment, search_filters, notify_all, enabled, created_at, updated_at
        FROM device_tokens
        WHERE token = $1
        """,
        token,
    )
    
    if not row:
        raise HTTPException(status_code=404, detail="Device not found")
    
    return _row_to_response(row)


@router.patch("/devices/{token}", response_model=DeviceResponse)
@limiter.limit("30/minute")
async def update_device(request: Request, token: str, body: DeviceUpdateRequest):
    """
    Update device notification preferences.
    
    Only provided fields are updated; omitted fields remain unchanged.
    
    **To clear search filters**: Pass `search_filters: []`
    **To keep current filters**: Omit `search_filters` or pass `null`
    """
    db = get_database()
    
    # First, get current device to merge with updates
    current = await db.fetchrow(
        "SELECT * FROM device_tokens WHERE token = $1",
        token,
    )
    
    if not current:
        raise HTTPException(status_code=404, detail="Device not found")
    
    # Determine new values (use current if not provided)
    new_enabled = body.enabled if body.enabled is not None else current["enabled"]
    new_notify_all = body.notify_all if body.notify_all is not None else current["notify_all"]
    
    # Handle search_filters: None means don't change, [] means clear
    if body.search_filters is None:
        new_search_filters = current["search_filters"]
    else:
        try:
            new_search_filters = validate_search_filters(body.search_filters)
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e))
    
    now = datetime.now(timezone.utc)
    
    row = await db.fetchrow(
        """
        UPDATE device_tokens
        SET search_filters = $2,
            notify_all = $3,
            enabled = $4,
            updated_at = $5
        WHERE token = $1
        RETURNING token, platform, environment, search_filters, notify_all, enabled, created_at, updated_at
        """,
        token,
        new_search_filters,
        new_notify_all,
        new_enabled,
        now,
    )
    
    logger.info(
        "Device updated",
        extra={
            "token_prefix": token[:8],
            "enabled": new_enabled,
            "notify_all": new_notify_all,
            "search_filter_count": len(new_search_filters) if new_search_filters else 0,
        },
    )
    
    return _row_to_response(row)


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
        "Device unregistered",
        extra={"token_prefix": token[:8] if len(token) >= 8 else token},
    )
    
    return {"status": "ok", "message": "Device unregistered"}
