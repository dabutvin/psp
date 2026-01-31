"""
Stats API router.

Endpoints:
- GET /stats - Get system statistics
"""

from datetime import datetime

from fastapi import APIRouter, Request, Response
from pydantic import BaseModel
from slowapi import Limiter
from slowapi.util import get_remote_address

from core.database import get_database
from core.logging import get_logger

logger = get_logger(__name__)
limiter = Limiter(key_func=get_remote_address)

router = APIRouter()


class StatsResponse(BaseModel):
    """System statistics."""
    
    total_messages: int
    newest_message_date: datetime | None = None
    oldest_message_date: datetime | None = None
    last_sync: datetime | None = None
    backfill_in_progress: bool = False


@router.get("/stats", response_model=StatsResponse)
@limiter.limit("30/minute")
async def get_stats(request: Request, response: Response):
    """
    Get system statistics.
    
    Returns total message count, date range, and sync status.
    Useful for showing "Last updated" in the app.
    
    **Caching**: Returns `Last-Modified` header based on last sync time.
    """
    db = get_database()
    
    # Get message stats
    msg_row = await db.fetchrow(
        """
        SELECT COUNT(*) as total, MIN(created) as oldest, MAX(created) as newest
        FROM messages
        """
    )
    
    # Get sync state
    sync_row = await db.fetchrow(
        """
        SELECT last_fetch_at, backfill_page_token
        FROM sync_state
        WHERE id = 1
        """
    )
    
    # Set Last-Modified header if we have a sync time
    last_sync = sync_row["last_fetch_at"] if sync_row else None
    if last_sync:
        response.headers["Last-Modified"] = last_sync.strftime("%a, %d %b %Y %H:%M:%S GMT")
    
    # Cache for 60 seconds
    response.headers["Cache-Control"] = "private, max-age=60"
    
    return StatsResponse(
        total_messages=msg_row["total"],
        newest_message_date=msg_row["newest"],
        oldest_message_date=msg_row["oldest"],
        last_sync=last_sync,
        backfill_in_progress=bool(sync_row["backfill_page_token"]) if sync_row else False,
    )
