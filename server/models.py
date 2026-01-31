"""
Data models for PSP server.
Pydantic models for validation and serialization.
"""

import re
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, computed_field


class Hashtag(BaseModel):
    """Hashtag associated with a message."""

    id: int | None = None
    message_id: int | None = None
    name: str
    color_hex: str | None = None


class Attachment(BaseModel):
    """File attachment on a message."""

    id: int | None = None
    message_id: int | None = None
    attachment_index: int = 0
    download_url: str | None = None
    thumbnail_url: str | None = None
    filename: str | None = None
    media_type: str | None = None


class Message(BaseModel):
    """
    Message from groups.io.
    Core data model for the system.
    """

    id: int
    topic_id: int | None = None
    group_id: int | None = None
    created: datetime | None = None
    updated: datetime | None = None
    subject: str | None = None
    body: str | None = None
    snippet: str | None = None
    name: str | None = None  # sender display name
    sender_email: str | None = None  # extracted from name field
    msg_num: int | None = None
    is_reply: bool = False
    is_plain_text: bool = False
    reply_to: str | None = None
    fetched_at: datetime | None = None

    # Related data
    hashtags: list[Hashtag] = Field(default_factory=list)
    attachments: list[Attachment] = Field(default_factory=list)

    @computed_field
    @property
    def price(self) -> str | None:
        """Extract price from subject or body."""
        return extract_price(self.subject, self.body)

    @computed_field
    @property
    def category(self) -> str | None:
        """Derive category from hashtags."""
        hashtag_names = {h.name.lower() for h in self.hashtags}
        if "forsale" in hashtag_names:
            return "ForSale"
        elif "forfree" in hashtag_names:
            return "ForFree"
        elif "iso" in hashtag_names:
            return "ISO"
        return None


class MessageSummary(BaseModel):
    """
    Lightweight message for list views.
    Excludes full body to reduce payload size.
    """

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


class HashtagCount(BaseModel):
    """Hashtag with message count for /hashtags endpoint."""

    name: str
    color_hex: str | None = None
    count: int


class SyncState(BaseModel):
    """Sync state for tracking polling/backfill progress."""

    id: int = 1
    last_fetch_at: datetime | None = None
    newest_message_id: int | None = None
    oldest_message_id: int | None = None
    backfill_page_token: int | None = None


class PaginatedResponse(BaseModel):
    """Generic paginated response wrapper."""

    messages: list[MessageSummary]
    has_more: bool
    next_cursor: str | None = None


class StatsResponse(BaseModel):
    """Response for /stats endpoint."""

    total_messages: int
    newest_message_date: datetime | None = None
    last_sync: datetime | None = None


# Utility functions for field extraction


def extract_price(subject: str | None, body: str | None) -> str | None:
    """
    Extract first price found in subject or body.

    Matches patterns like:
    - $40, $40.00, $1,000
    - asking $50, asking 50
    - 50 dollars, 40 obo
    """
    text = f"{subject or ''} {body or ''}"

    patterns = [
        r"\$[\d,]+(?:\.\d{2})?",  # $40, $40.00, $1,000
        r"asking\s*\$?[\d,]+",  # asking $50, asking 50
        r"[\d,]+\s*(?:dollars|obo)",  # 50 dollars, 40 obo
    ]

    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            return match.group(0)

    return None


def extract_email(name: str | None) -> str | None:
    """
    Extract email from 'Display Name <email@example.com>' format.
    """
    if not name:
        return None

    match = re.search(r"<([^>]+@[^>]+)>", name)
    return match.group(1) if match else None


# Groups.io API response models


class GroupsIOMessage(BaseModel):
    """
    Raw message from groups.io API.
    Maps API field names to our internal model.
    """

    id: int
    topic_id: int | None = None
    group_id: int | None = None
    created: datetime | None = None
    updated: datetime | None = None
    subject: str | None = None
    body: str | None = None
    snippet: str | None = None
    name: str | None = None  # may contain email in brackets
    msg_num: int | None = None
    is_reply: bool = False
    is_plain_text: bool = False
    reply_to: str | None = None
    hashtags: list[dict] | None = None  # API returns null instead of []
    attachments: list[dict] | None = None  # API returns null instead of []

    def to_message(self) -> Message:
        """Convert to internal Message model."""
        return Message(
            id=self.id,
            topic_id=self.topic_id,
            group_id=self.group_id,
            created=self.created,
            updated=self.updated,
            subject=self.subject,
            body=self.body,
            snippet=self.snippet,
            name=self.name,
            sender_email=extract_email(self.name),
            msg_num=self.msg_num,
            is_reply=self.is_reply,
            is_plain_text=self.is_plain_text,
            reply_to=self.reply_to,
            hashtags=[
                Hashtag(name=h.get("name", ""), color_hex=h.get("color"))
                for h in (self.hashtags or [])
            ],
            attachments=[
                Attachment(
                    attachment_index=i,
                    download_url=a.get("download_url"),
                    thumbnail_url=a.get("thumbnail_url"),
                    filename=a.get("filename"),
                    media_type=a.get("media_type"),
                )
                for i, a in enumerate(self.attachments or [])
            ],
        )


class GroupsIOResponse(BaseModel):
    """Response from groups.io getmessages API."""

    total_count: int = 0
    has_more: bool = False
    next_page_token: int | None = None
    data: list[GroupsIOMessage] = Field(default_factory=list)
