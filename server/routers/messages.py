"""
Messages API router.

Endpoints:
- GET /messages - List messages with pagination, filtering, search
- GET /messages/{id} - Get single message with full body
- GET /topics/{topic_id}/messages - Get all messages in a thread
"""

import hashlib
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Header, HTTPException, Query, Request, Response
from pydantic import BaseModel, Field
from slowapi import Limiter
from slowapi.util import get_remote_address

from core.database import get_database
from core.logging import get_logger
from core.models import Attachment, Hashtag, extract_price

logger = get_logger(__name__)
limiter = Limiter(key_func=get_remote_address)

router = APIRouter()


def _generate_etag(*args) -> str:
    """Generate an ETag from arbitrary arguments."""
    content = ":".join(str(a) for a in args)
    return f'"{hashlib.md5(content.encode()).hexdigest()}"'


def _check_etag(request_etag: str | None, current_etag: str) -> bool:
    """Check if client's ETag matches (return True if match = 304)."""
    if not request_etag:
        return False
    # Handle both quoted and unquoted ETags
    return request_etag.strip('"') == current_etag.strip('"')


# Response models
class MessageSummary(BaseModel):
    """Message summary for list views (excludes full body)."""
    
    id: int
    subject: str | None = None
    snippet: str | None = None
    created: datetime | None = None
    name: str | None = None
    sender_email: str | None = None
    hashtags: list[Hashtag] = Field(default_factory=list)
    attachments: list[Attachment] = Field(default_factory=list)
    price: str | None = None
    category: str | None = None
    is_reply: bool = False


class MessageDetail(MessageSummary):
    """Full message detail including body."""
    
    body: str | None = None
    topic_id: int | None = None
    msg_num: int | None = None
    reply_to: str | None = None


class MessagesResponse(BaseModel):
    """Paginated messages response."""
    
    messages: list[MessageSummary]
    has_more: bool
    next_cursor: str | None = None


class TopicMessagesResponse(BaseModel):
    """All messages in a topic/thread."""
    
    topic_id: int
    messages: list[MessageDetail]
    count: int


def _derive_category(hashtags: list[Hashtag]) -> str | None:
    """Derive category from hashtags."""
    names = {h.name.lower() for h in hashtags}
    if "forsale" in names:
        return "ForSale"
    elif "forfree" in names:
        return "ForFree"
    elif "iso" in names:
        return "ISO"
    return None


async def _fetch_related_data(
    db, message_ids: list[int]
) -> tuple[dict[int, list[Hashtag]], dict[int, list[Attachment]]]:
    """Fetch hashtags and attachments for a list of messages."""
    if not message_ids:
        return {}, {}

    # Fetch hashtags
    hashtag_rows = await db.fetch(
        """
        SELECT message_id, name, color_hex
        FROM hashtags
        WHERE message_id = ANY($1)
        ORDER BY message_id, id
        """,
        message_ids,
    )
    
    hashtags_by_msg: dict[int, list[Hashtag]] = {}
    for row in hashtag_rows:
        msg_id = row["message_id"]
        if msg_id not in hashtags_by_msg:
            hashtags_by_msg[msg_id] = []
        hashtags_by_msg[msg_id].append(
            Hashtag(name=row["name"], color_hex=row["color_hex"])
        )

    # Fetch attachments
    attachment_rows = await db.fetch(
        """
        SELECT message_id, attachment_index, download_url, thumbnail_url, filename, media_type
        FROM attachments
        WHERE message_id = ANY($1)
        ORDER BY message_id, attachment_index
        """,
        message_ids,
    )
    
    attachments_by_msg: dict[int, list[Attachment]] = {}
    for row in attachment_rows:
        msg_id = row["message_id"]
        if msg_id not in attachments_by_msg:
            attachments_by_msg[msg_id] = []
        attachments_by_msg[msg_id].append(
            Attachment(
                attachment_index=row["attachment_index"],
                download_url=row["download_url"],
                thumbnail_url=row["thumbnail_url"],
                filename=row["filename"],
                media_type=row["media_type"],
            )
        )

    return hashtags_by_msg, attachments_by_msg


@router.get("/messages", response_model=MessagesResponse)
@limiter.limit("60/minute")
async def list_messages(
    request: Request,
    response: Response,
    limit: Annotated[int, Query(ge=1, le=100, description="Number of messages to return")] = 20,
    cursor: Annotated[str | None, Query(description="Pagination cursor (message ID)")] = None,
    since: Annotated[datetime | None, Query(description="Return messages after this date")] = None,
    hashtags: Annotated[str | None, Query(description="Filter by hashtags (comma-separated)")] = None,
    search: Annotated[str | None, Query(description="Full-text search query")] = None,
    if_none_match: Annotated[str | None, Header()] = None,
):
    """
    List messages with pagination and filtering.
    
    **Pagination**: Uses cursor-based pagination for stable results during infinite scroll.
    Pass the `next_cursor` from the response to get the next page.
    
    **Filtering**:
    - `hashtags`: Filter by hashtags (comma-separated, returns posts matching ANY)
    - `search`: Full-text search in subject and body
    - `since`: Only messages created after this timestamp
    
    **Caching**: Returns ETag header based on the first message ID in results.
    """
    db = get_database()
    
    # Build query dynamically
    conditions = []
    params = []
    param_idx = 1
    
    # Cursor pagination (fetch older messages)
    if cursor:
        try:
            cursor_id = int(cursor)
            conditions.append(f"m.id < ${param_idx}")
            params.append(cursor_id)
            param_idx += 1
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid cursor format")
    
    # Filter by date
    if since:
        conditions.append(f"m.created > ${param_idx}")
        params.append(since)
        param_idx += 1
    
    # Filter by hashtags (comma-separated, OR logic)
    hashtag_join = ""
    if hashtags:
        hashtag_list = [h.strip().lower() for h in hashtags.split(",") if h.strip()]
        if hashtag_list:
            hashtag_join = "JOIN hashtags h ON h.message_id = m.id"
            conditions.append(f"LOWER(h.name) = ANY(${param_idx})")
            params.append(hashtag_list)
            param_idx += 1
    
    # Full-text search
    if search:
        conditions.append(f"m.search_vector @@ plainto_tsquery('english', ${param_idx})")
        params.append(search)
        param_idx += 1
    
    # Build WHERE clause
    where_clause = ""
    if conditions:
        where_clause = "WHERE " + " AND ".join(conditions)
    
    # Fetch one extra to determine has_more
    fetch_limit = limit + 1
    params.append(fetch_limit)
    
    # Build and execute query
    query = f"""
        SELECT DISTINCT m.id, m.subject, m.snippet, m.created, m.name, m.sender_email,
               m.is_reply, m.body
        FROM messages m
        {hashtag_join}
        {where_clause}
        ORDER BY m.id DESC
        LIMIT ${param_idx}
    """
    
    logger.debug(f"Query: {query}, params: {params}")
    rows = await db.fetch(query, *params)
    
    # Check if there are more results
    has_more = len(rows) > limit
    if has_more:
        rows = rows[:limit]
    
    # Get message IDs for related data fetch
    message_ids = [row["id"] for row in rows]
    hashtags_by_msg, attachments_by_msg = await _fetch_related_data(db, message_ids)
    
    # Build response
    messages = []
    for row in rows:
        msg_hashtags = hashtags_by_msg.get(row["id"], [])
        messages.append(
            MessageSummary(
                id=row["id"],
                subject=row["subject"],
                snippet=row["snippet"],
                created=row["created"],
                name=row["name"],
                sender_email=row["sender_email"],
                is_reply=row["is_reply"],
                hashtags=msg_hashtags,
                attachments=attachments_by_msg.get(row["id"], []),
                price=extract_price(row["subject"], row["body"]),
                category=_derive_category(msg_hashtags),
            )
        )
    
    # Next cursor is the ID of the last message
    next_cursor = str(messages[-1].id) if messages and has_more else None
    
    # Generate ETag based on first message ID and query params
    if messages:
        etag = _generate_etag(messages[0].id, cursor, hashtags, search, limit)
        
        # Check if client has current version
        if _check_etag(if_none_match, etag):
            return Response(status_code=304, headers={"ETag": etag})
        
        response.headers["ETag"] = etag
    
    # Cache for 30 seconds (list can change frequently)
    response.headers["Cache-Control"] = "private, max-age=30"
    
    logger.info(
        f"Listed {len(messages)} messages",
        extra={
            "count": len(messages),
            "has_more": has_more,
            "hashtags": hashtags,
            "search": search is not None,
        },
    )
    
    return MessagesResponse(
        messages=messages,
        has_more=has_more,
        next_cursor=next_cursor,
    )


@router.get("/messages/{message_id}", response_model=MessageDetail)
@limiter.limit("120/minute")
async def get_message(
    request: Request,
    response: Response,
    message_id: int,
    if_none_match: Annotated[str | None, Header()] = None,
):
    """
    Get a single message with full body content.
    
    Use this for the detail view when user taps on a message.
    
    **Caching**: Returns ETag header. Send `If-None-Match` with the ETag
    to get a 304 Not Modified if the message hasn't changed.
    """
    db = get_database()
    
    row = await db.fetchrow(
        """
        SELECT id, topic_id, subject, body, snippet, created, updated, name, sender_email,
               msg_num, is_reply, reply_to
        FROM messages
        WHERE id = $1
        """,
        message_id,
    )
    
    if not row:
        raise HTTPException(status_code=404, detail="Message not found")
    
    # Generate ETag based on message ID and updated timestamp
    etag = _generate_etag(message_id, row["updated"] or row["created"])
    
    # Check if client has current version
    if _check_etag(if_none_match, etag):
        return Response(status_code=304, headers={"ETag": etag})
    
    # Set ETag header
    response.headers["ETag"] = etag
    response.headers["Cache-Control"] = "private, max-age=60"
    
    # Fetch related data
    hashtags_by_msg, attachments_by_msg = await _fetch_related_data(db, [message_id])
    msg_hashtags = hashtags_by_msg.get(message_id, [])
    
    return MessageDetail(
        id=row["id"],
        topic_id=row["topic_id"],
        subject=row["subject"],
        body=row["body"],
        snippet=row["snippet"],
        created=row["created"],
        name=row["name"],
        sender_email=row["sender_email"],
        msg_num=row["msg_num"],
        is_reply=row["is_reply"],
        reply_to=row["reply_to"],
        hashtags=msg_hashtags,
        attachments=attachments_by_msg.get(message_id, []),
        price=extract_price(row["subject"], row["body"]),
        category=_derive_category(msg_hashtags),
    )


@router.get("/topics/{topic_id}/messages", response_model=TopicMessagesResponse)
@limiter.limit("60/minute")
async def get_topic_messages(request: Request, topic_id: int):
    """
    Get all messages in a topic/thread.
    
    Use this for conversation view to show the full thread.
    Messages are ordered by creation date (oldest first).
    """
    db = get_database()
    
    rows = await db.fetch(
        """
        SELECT id, topic_id, subject, body, snippet, created, name, sender_email,
               msg_num, is_reply, reply_to
        FROM messages
        WHERE topic_id = $1
        ORDER BY created ASC
        """,
        topic_id,
    )
    
    if not rows:
        raise HTTPException(status_code=404, detail="Topic not found")
    
    # Fetch related data
    message_ids = [row["id"] for row in rows]
    hashtags_by_msg, attachments_by_msg = await _fetch_related_data(db, message_ids)
    
    messages = []
    for row in rows:
        msg_hashtags = hashtags_by_msg.get(row["id"], [])
        messages.append(
            MessageDetail(
                id=row["id"],
                topic_id=row["topic_id"],
                subject=row["subject"],
                body=row["body"],
                snippet=row["snippet"],
                created=row["created"],
                name=row["name"],
                sender_email=row["sender_email"],
                msg_num=row["msg_num"],
                is_reply=row["is_reply"],
                reply_to=row["reply_to"],
                hashtags=msg_hashtags,
                attachments=attachments_by_msg.get(row["id"], []),
                price=extract_price(row["subject"], row["body"]),
                category=_derive_category(msg_hashtags),
            )
        )
    
    return TopicMessagesResponse(
        topic_id=topic_id,
        messages=messages,
        count=len(messages),
    )
