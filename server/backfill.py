"""
Backfill module for PSP server.
Fetches historical messages from groups.io (newest to oldest).

Start with most recent messages so the app is useful right away,
then work backwards through history.

IMPORTANT: Be gentle with the API!
- ~704,790 messages total
- At 100 messages per request = ~7,048 API calls needed
- Default: 1 request per 5 seconds = ~10 hours total
- Resumable via backfill_page_token in sync_state
"""

import logging
import signal
import time
from datetime import datetime, timezone

import psycopg2
from psycopg2.extras import execute_values

from api_client import GroupsIOClient, RateLimitError
from config import get_db_url
from models import Message

logger = logging.getLogger(__name__)

# Global flag for graceful shutdown
_shutdown_requested = False


def _signal_handler(signum, frame):
    """Handle shutdown signals gracefully."""
    global _shutdown_requested
    logger.info("Shutdown requested, will stop after current batch...")
    _shutdown_requested = True


def backfill_messages(
    batch_size: int = 100,
    max_messages: int | None = None,
    delay: float = 5.0,
    dry_run: bool = False,
) -> tuple[int, bool]:
    """
    Backfill historical messages from groups.io (newest to oldest).

    Starts with most recent messages and works backwards through history.
    This function is resumable - it saves progress to the database and can be
    stopped/started at any time. Progress is tracked via backfill_page_token.

    Args:
        batch_size: Number of messages to fetch per API call (max 100)
        max_messages: Maximum messages to fetch this run (None = no limit)
        delay: Seconds to wait between API requests (be gentle!)
        dry_run: If True, don't modify database

    Returns:
        Tuple of (messages_fetched, is_complete)
        - messages_fetched: Number of messages inserted this run
        - is_complete: True if backfill reached the end (no more messages)
    """
    global _shutdown_requested
    _shutdown_requested = False

    # Set up signal handlers for graceful shutdown
    original_sigint = signal.signal(signal.SIGINT, _signal_handler)
    original_sigterm = signal.signal(signal.SIGTERM, _signal_handler)

    try:
        return _do_backfill(batch_size, max_messages, delay, dry_run)
    finally:
        # Restore original signal handlers
        signal.signal(signal.SIGINT, original_sigint)
        signal.signal(signal.SIGTERM, original_sigterm)


def _do_backfill(
    batch_size: int,
    max_messages: int | None,
    delay: float,
    dry_run: bool,
) -> tuple[int, bool]:
    """Internal backfill implementation."""
    client = GroupsIOClient()
    db_url = get_db_url()

    total_fetched = 0
    total_new = 0
    is_complete = False

    with psycopg2.connect(db_url) as conn:
        with conn.cursor() as cur:
            # Get current backfill state
            cur.execute("SELECT backfill_page_token FROM sync_state WHERE id = 1")
            row = cur.fetchone()
            page_token = row[0] if row else None

            if page_token:
                logger.info(f"Resuming backfill from page_token={page_token}")
            else:
                logger.info("Starting backfill from the beginning")

            # Get total message count for progress reporting
            try:
                response = client.get_messages(limit=1, sort_dir="desc")
                total_count = response.total_count
                logger.info(f"Total messages in group: {total_count:,}")
            except Exception as e:
                logger.warning(f"Could not get total count: {e}")
                total_count = None

            while True:
                # Check shutdown flag
                if _shutdown_requested:
                    logger.info("Shutdown requested, stopping backfill")
                    break

                # Check max messages limit
                if max_messages is not None and total_fetched >= max_messages:
                    logger.info(f"Reached max_messages limit ({max_messages})")
                    break

                # Calculate batch size
                remaining = (max_messages - total_fetched) if max_messages else batch_size
                fetch_limit = min(batch_size, remaining)

                # Fetch a batch of messages (oldest first for backfill)
                logger.info(f"Fetching batch of {fetch_limit} (page_token={page_token})...")

                try:
                    response = client.get_messages(
                        limit=fetch_limit,
                        page_token=page_token,
                        sort_dir="desc",  # Newest first, work backwards
                    )
                except RateLimitError as e:
                    logger.warning(f"Rate limited! Waiting {e.retry_after}s before retry...")
                    time.sleep(e.retry_after)
                    continue

                if not response.data:
                    logger.info("No more messages - backfill complete!")
                    is_complete = True
                    break

                messages = [msg.to_message() for msg in response.data]
                total_fetched += len(messages)

                # Check which messages we already have (for idempotency)
                message_ids = [m.id for m in messages]
                cur.execute(
                    "SELECT id FROM messages WHERE id = ANY(%s)",
                    (message_ids,),
                )
                existing_ids = {row[0] for row in cur.fetchall()}

                # Filter to only new messages
                new_messages = [m for m in messages if m.id not in existing_ids]
                skipped = len(messages) - len(new_messages)

                if new_messages:
                    if not dry_run:
                        _insert_messages(cur, new_messages)
                    total_new += len(new_messages)

                # Progress logging
                if skipped > 0:
                    logger.info(
                        f"Inserted {len(new_messages)} messages, skipped {skipped} existing"
                    )
                else:
                    logger.info(f"Inserted {len(new_messages)} messages")

                if total_count:
                    # Estimate progress based on page_token (message ID)
                    oldest_in_batch = min(m.id for m in messages)
                    newest_in_batch = max(m.id for m in messages)
                    logger.info(
                        f"Progress: {total_new:,} new messages, "
                        f"ID range: {oldest_in_batch:,} - {newest_in_batch:,}"
                    )

                # Update backfill state (track how far back we've gone)
                if not dry_run and response.next_page_token:
                    cur.execute(
                        """
                        UPDATE sync_state
                        SET backfill_page_token = %s,
                            oldest_message_id = LEAST(oldest_message_id, %s),
                            newest_message_id = GREATEST(newest_message_id, %s)
                        WHERE id = 1
                        """,
                        (response.next_page_token, min(message_ids), max(message_ids)),
                    )
                    conn.commit()

                # Check if we've reached the end
                if not response.has_more:
                    logger.info("No more pages - backfill complete!")
                    is_complete = True
                    # Clear the backfill token since we're done
                    if not dry_run:
                        cur.execute(
                            "UPDATE sync_state SET backfill_page_token = NULL WHERE id = 1"
                        )
                        conn.commit()
                    break

                # Update page token for next iteration
                page_token = response.next_page_token

                # Be gentle with the API
                if delay > 0:
                    logger.debug(f"Waiting {delay}s before next request...")
                    time.sleep(delay)

        # Final commit
        if not dry_run:
            conn.commit()

    logger.info(
        f"Backfill session complete: {total_new} new messages from {total_fetched} checked"
    )
    return total_new, is_complete


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


def get_backfill_status() -> dict:
    """
    Get current backfill status from database.

    Returns dict with:
        - messages_count: Total messages in database
        - oldest_message_id: Oldest message ID we have
        - newest_message_id: Newest message ID we have
        - backfill_page_token: Current backfill position (None if complete)
        - is_complete: True if backfill_page_token is None
    """
    db_url = get_db_url()

    with psycopg2.connect(db_url) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM messages")
            messages_count = cur.fetchone()[0]

            cur.execute(
                """
                SELECT oldest_message_id, newest_message_id, backfill_page_token
                FROM sync_state WHERE id = 1
                """
            )
            row = cur.fetchone()

            if row:
                oldest_id, newest_id, page_token = row
            else:
                oldest_id, newest_id, page_token = None, None, None

            # Also get actual min/max from messages table
            cur.execute("SELECT MIN(id), MAX(id) FROM messages")
            actual_min, actual_max = cur.fetchone()

    return {
        "messages_count": messages_count,
        "oldest_message_id": actual_min or oldest_id,
        "newest_message_id": actual_max or newest_id,
        "backfill_page_token": page_token,
        "is_complete": page_token is None and messages_count > 0,
    }


def reset_backfill() -> None:
    """
    Reset backfill state to start from the beginning.
    WARNING: This does NOT delete existing messages.
    """
    db_url = get_db_url()

    with psycopg2.connect(db_url) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE sync_state
                SET backfill_page_token = NULL,
                    oldest_message_id = NULL
                WHERE id = 1
                """
            )
        conn.commit()

    logger.info("Backfill state reset")


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    # Quick status check when run directly
    status = get_backfill_status()
    print(f"Backfill Status:")
    print(f"  Messages in DB: {status['messages_count']:,}")
    print(f"  Message ID range: {status['oldest_message_id']} - {status['newest_message_id']}")
    print(f"  Backfill complete: {status['is_complete']}")
    if status['backfill_page_token']:
        print(f"  Resume token: {status['backfill_page_token']}")
