"""
Shared full-text search utilities.

Used by both the messages API and notification system to ensure
consistent search behavior (stemming, stop words, etc.).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from core.logging import get_logger

if TYPE_CHECKING:
    from core.database import Database

logger = get_logger(__name__)

MAX_SEARCH_FILTERS = 20
MAX_SEARCH_TERM_LENGTH = 100


def build_search_condition(param_index: int) -> str:
    """
    Build the SQL condition for full-text search.
    
    Uses PostgreSQL's plainto_tsquery with English stemming, which means:
    - "stroller" matches "strollers", "stroller's", etc.
    - "running" matches "run", "runs", "ran"
    - Common stop words are ignored
    
    Args:
        param_index: The positional parameter index (e.g., 1 for $1, 2 for $2)
    
    Returns:
        SQL condition string like "search_vector @@ plainto_tsquery('english', $1)"
    
    Raises:
        ValueError: If param_index is less than 1
    """
    if param_index < 1:
        raise ValueError("Parameter index must be >= 1")
    return f"search_vector @@ plainto_tsquery('english', ${param_index})"


def normalize_search_term(term: str) -> str:
    """
    Normalize a search term for storage.
    
    - Strips leading/trailing whitespace
    - Converts to lowercase
    - Truncates to MAX_SEARCH_TERM_LENGTH
    """
    return term.strip().lower()[:MAX_SEARCH_TERM_LENGTH]


def validate_search_filters(filters: list[str] | None) -> list[str] | None:
    """
    Validate and normalize search filters.
    
    Args:
        filters: List of search terms or None
    
    Returns:
        Normalized list with duplicates removed, or None if empty
    
    Raises:
        ValueError: If too many filters provided
    """
    if filters is None:
        return None
    
    if len(filters) > MAX_SEARCH_FILTERS:
        raise ValueError(f"Maximum {MAX_SEARCH_FILTERS} search filters allowed")
    
    # Normalize and remove empty strings
    normalized = [normalize_search_term(f) for f in filters if f.strip()]
    
    # Remove duplicates while preserving order
    seen = set()
    unique = []
    for term in normalized:
        if term not in seen:
            seen.add(term)
            unique.append(term)
    
    # Return None instead of empty list
    return unique if unique else None


async def get_devices_matching_post(db: "Database", post_id: int) -> list[dict]:
    """
    Find all devices that should be notified for a given post.
    
    Uses the same full-text search logic as the messages API to ensure
    consistent matching (stemming, stop words, etc.).
    
    Notification logic:
    - If enabled = FALSE → no notification
    - If the post is an ISO (In Search Of) post → no keyword-match notification
    - If enabled = TRUE AND notify_all = TRUE → notify
    - If enabled = TRUE AND notify_all = FALSE → notify only if post matches any search term
    
    ISO posts are excluded from keyword-match notifications because they represent
    someone *looking for* an item, not offering one. Users with keyword alerts like
    "high chair" want to see items for sale, not other people also searching.
    notify_all devices still receive ISO posts.
    
    Args:
        db: Database connection (core.database.Database instance)
        post_id: The message ID to match against
    
    Returns:
        List of dicts with 'token' and 'environment' keys
    """
    rows = await db.fetch("""
        SELECT DISTINCT d.token, d.environment
        FROM device_tokens d
        WHERE d.enabled = TRUE
        AND (
            -- Notify all posts (including ISO)
            d.notify_all = TRUE
            OR
            -- Or has search filters, at least one matches, and post is NOT an ISO
            (
                d.search_filters IS NOT NULL 
                AND array_length(d.search_filters, 1) > 0
                AND EXISTS (
                    SELECT 1 FROM messages m, unnest(d.search_filters) AS filter_term
                    WHERE m.id = $1
                    AND m.search_vector @@ plainto_tsquery('english', filter_term)
                )
                AND NOT EXISTS (
                    SELECT 1 FROM hashtags h
                    WHERE h.message_id = $1
                    AND LOWER(h.name) = 'iso'
                )
            )
        )
    """, post_id)
    
    return [{"token": row["token"], "environment": row["environment"]} for row in rows]


async def remove_device_token(db: "Database", token: str) -> None:
    """Remove an invalid/expired device token from the database."""
    await db.execute("DELETE FROM device_tokens WHERE token = $1", token)
    logger.info("Removed expired device token", extra={"token_prefix": token[:8]})
