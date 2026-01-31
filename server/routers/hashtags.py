"""
Hashtags API router.

Endpoints:
- GET /hashtags - List all hashtags with message counts
"""

from fastapi import APIRouter, Request
from pydantic import BaseModel
from slowapi import Limiter
from slowapi.util import get_remote_address

from db import get_database
from logging_config import get_logger

logger = get_logger(__name__)
limiter = Limiter(key_func=get_remote_address)

router = APIRouter()


class HashtagCount(BaseModel):
    """Hashtag with message count."""
    
    name: str
    color_hex: str | None = None
    count: int


class HashtagsResponse(BaseModel):
    """List of hashtags with counts."""
    
    hashtags: list[HashtagCount]
    total_unique: int


@router.get("/hashtags", response_model=HashtagsResponse)
@limiter.limit("30/minute")
async def list_hashtags(request: Request):
    """
    List all hashtags with their message counts.
    
    Returns hashtags sorted by count (most popular first).
    Useful for showing category filters in the app.
    """
    db = get_database()
    
    # Get hashtags with counts
    rows = await db.fetch(
        """
        SELECT name, color_hex, COUNT(*) as count
        FROM hashtags
        GROUP BY name, color_hex
        ORDER BY count DESC
        """
    )
    
    hashtags = [
        HashtagCount(
            name=row["name"],
            color_hex=row["color_hex"],
            count=row["count"],
        )
        for row in rows
    ]
    
    logger.info(
        f"Listed {len(hashtags)} unique hashtags",
        extra={"unique_count": len(hashtags)},
    )
    
    return HashtagsResponse(
        hashtags=hashtags,
        total_unique=len(hashtags),
    )
