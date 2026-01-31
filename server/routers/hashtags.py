"""
Hashtags API router.

Endpoints:
- GET /hashtags - List all hashtags with message counts
"""

import hashlib
from typing import Annotated

from fastapi import APIRouter, Header, Request, Response
from pydantic import BaseModel
from slowapi import Limiter
from slowapi.util import get_remote_address

from core.database import get_database
from core.logging import get_logger

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


def _generate_etag(data: str) -> str:
    """Generate an ETag from string data."""
    return f'"{hashlib.md5(data.encode()).hexdigest()}"'


@router.get("/hashtags", response_model=HashtagsResponse)
@limiter.limit("30/minute")
async def list_hashtags(
    request: Request,
    response: Response,
    if_none_match: Annotated[str | None, Header()] = None,
):
    """
    List all hashtags with their message counts.
    
    Returns hashtags sorted by count (most popular first).
    Useful for showing category filters in the app.
    
    **Caching**: Returns ETag header. Hashtag counts change slowly,
    so this endpoint can be cached aggressively.
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
    
    # Generate ETag based on hashtag names and counts
    etag_data = "|".join(f"{h.name}:{h.count}" for h in hashtags[:20])  # Top 20 for efficiency
    etag = _generate_etag(etag_data)
    
    # Check if client has current version
    if if_none_match and if_none_match.strip('"') == etag.strip('"'):
        return Response(status_code=304, headers={"ETag": etag})
    
    response.headers["ETag"] = etag
    # Hashtag counts change slowly, cache for 5 minutes
    response.headers["Cache-Control"] = "private, max-age=300"
    
    logger.info(
        f"Listed {len(hashtags)} unique hashtags",
        extra={"unique_count": len(hashtags)},
    )
    
    return HashtagsResponse(
        hashtags=hashtags,
        total_unique=len(hashtags),
    )
