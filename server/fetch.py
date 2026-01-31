"""
Fetch module for PSP server.
Fetches new messages from groups.io until we hit one we already have.
"""

from datetime import datetime, timezone

import psycopg2
from psycopg2.extras import execute_values

from api_client import GroupsIOClient, RateLimitError
from config import get_db_url
from logging_config import get_logger
from models import Message

logger = get_logger(__name__)


def fetch_new_messages(
    batch_size: int = 100,
    max_messages: int = 1000,
    dry_run: bool = False,
) -> int:
    """
    Fetch new messages from groups.io until we hit one we already have.

    Args:
        batch_size: Number of messages to fetch per API call (max 100)
        max_messages: Maximum total messages to fetch (safety limit)
        dry_run: If True, don't insert into database

    Returns:
        Number of new messages fetched and stored
    """
    client = GroupsIOClient()
    db_url = get_db_url()

    total_fetched = 0
    total_new = 0
    page_token = None

    with psycopg2.connect(db_url) as conn:
        with conn.cursor() as cur:
            while total_fetched < max_messages:
                # Calculate how many to fetch this batch
                remaining = max_messages - total_fetched
                fetch_limit = min(batch_size, remaining)

                # Fetch a batch of messages (newest first)
                logger.info(
                    f"Fetching batch of {fetch_limit}",
                    extra={"batch_size": fetch_limit, "page_token": page_token},
                )
                try:
                    response = client.get_messages(
                        limit=fetch_limit,
                        page_token=page_token,
                        sort_dir="desc",
                    )
                except RateLimitError as e:
                    logger.warning(f"Rate limited, stopping. Retry after {e.retry_after}s")
                    break

                if not response.data:
                    logger.info("No more messages to fetch")
                    break

                messages = [msg.to_message() for msg in response.data]
                total_fetched += len(messages)

                # Check which messages we already have
                message_ids = [m.id for m in messages]
                cur.execute(
                    "SELECT id FROM messages WHERE id = ANY(%s)",
                    (message_ids,),
                )
                existing_ids = {row[0] for row in cur.fetchall()}

                # Filter to only new messages
                new_messages = [m for m in messages if m.id not in existing_ids]

                if new_messages:
                    if not dry_run:
                        _insert_messages(cur, new_messages)
                    total_new += len(new_messages)
                    logger.info(
                        f"Inserted {len(new_messages)} new messages",
                        extra={"inserted": len(new_messages), "total_new": total_new},
                    )

                # If we found any existing messages, we've caught up
                if existing_ids:
                    logger.info(
                        f"Found {len(existing_ids)} existing messages, caught up!"
                    )
                    break

                # Check if there are more pages
                if not response.has_more:
                    logger.info("No more pages available")
                    break

                page_token = response.next_page_token

            # Update sync state
            if total_new > 0 and not dry_run:
                cur.execute(
                    """
                    UPDATE sync_state 
                    SET last_fetch_at = %s,
                        newest_message_id = GREATEST(newest_message_id, %s)
                    WHERE id = 1
                    """,
                    (datetime.now(timezone.utc), message_ids[0] if message_ids else None),
                )

        if not dry_run:
            conn.commit()

    logger.info(
        f"Fetch complete: {total_new} new messages from {total_fetched} checked",
        extra={"total_new": total_new, "total_checked": total_fetched},
    )
    return total_new


def _insert_messages(cur, messages: list[Message]) -> None:
    """Insert messages and their related data into the database."""
    # Insert messages
    message_values = [
        (
            m.id,
            m.topic_id,
            m.group_id,
            m.created,
            m.updated,
            m.subject,
            m.body,
            m.snippet,
            m.name,
            m.sender_email,
            m.msg_num,
            m.is_reply,
            m.is_plain_text,
            m.reply_to,
        )
        for m in messages
    ]

    execute_values(
        cur,
        """
        INSERT INTO messages (
            id, topic_id, group_id, created, updated, subject, body, snippet,
            name, sender_email, msg_num, is_reply, is_plain_text, reply_to
        ) VALUES %s
        ON CONFLICT (id) DO NOTHING
        """,
        message_values,
    )

    # Insert hashtags
    hashtag_values = [
        (m.id, h.name, h.color_hex)
        for m in messages
        for h in m.hashtags
    ]
    if hashtag_values:
        execute_values(
            cur,
            """
            INSERT INTO hashtags (message_id, name, color_hex)
            VALUES %s
            """,
            hashtag_values,
        )

    # Insert attachments
    attachment_values = [
        (m.id, a.attachment_index, a.download_url, a.thumbnail_url, a.filename, a.media_type)
        for m in messages
        for a in m.attachments
    ]
    if attachment_values:
        execute_values(
            cur,
            """
            INSERT INTO attachments (
                message_id, attachment_index, download_url, thumbnail_url, filename, media_type
            ) VALUES %s
            """,
            attachment_values,
        )


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    fetch_new_messages()
