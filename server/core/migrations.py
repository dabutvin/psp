"""
Database migrations for PSP server.

Contains one-time migrations for schema changes and data backfills.
"""

import time

import psycopg2

from core.config import get_db_url
from core.logging import get_logger

logger = get_logger(__name__)


def migrate_search_vectors(batch_size: int = 1000, delay: float = 0.1) -> int:
    """
    Populate search_vector column for existing messages.
    
    The search_vector column is populated automatically by a trigger on INSERT/UPDATE,
    but messages inserted before the trigger was created need to be backfilled.
    
    Args:
        batch_size: Number of messages to update per batch
        delay: Seconds to wait between batches (be gentle on DB)
    
    Returns:
        Number of messages updated
    """
    db_url = get_db_url()
    total_updated = 0

    with psycopg2.connect(db_url) as conn:
        with conn.cursor() as cur:
            # Count messages needing update
            cur.execute("""
                SELECT COUNT(*) FROM messages 
                WHERE search_vector IS NULL
            """)
            need_update = cur.fetchone()[0]

            if need_update == 0:
                logger.info("All messages already have search vectors")
                return 0

            logger.info(
                f"Migrating search vectors for {need_update:,} messages",
                extra={"total": need_update, "batch_size": batch_size},
            )

            # Process in batches
            while True:
                # Update a batch of messages
                cur.execute("""
                    WITH batch AS (
                        SELECT id FROM messages
                        WHERE search_vector IS NULL
                        LIMIT %s
                    )
                    UPDATE messages m
                    SET subject = m.subject
                    FROM batch
                    WHERE m.id = batch.id
                    RETURNING m.id
                """, (batch_size,))

                updated = cur.rowcount
                conn.commit()

                if updated == 0:
                    break

                total_updated += updated
                progress = (total_updated / need_update) * 100

                logger.info(
                    f"Updated {total_updated:,}/{need_update:,} ({progress:.1f}%)",
                    extra={"updated": total_updated, "total": need_update, "progress": progress},
                )

                if delay > 0:
                    time.sleep(delay)

    logger.info(
        f"Search vector migration complete: {total_updated:,} messages updated",
        extra={"total_updated": total_updated},
    )
    return total_updated


def rebuild_search_vectors(batch_size: int = 1000, delay: float = 0.1) -> int:
    """
    Rebuild ALL search vectors (not just missing ones).
    
    Use this after changing the search normalization logic to ensure
    all existing messages get the updated tokenization.
    
    Args:
        batch_size: Number of messages to update per batch
        delay: Seconds to wait between batches
    
    Returns:
        Number of messages updated
    """
    db_url = get_db_url()
    total_updated = 0

    with psycopg2.connect(db_url) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM messages")
            total = cur.fetchone()[0]

            if total == 0:
                logger.info("No messages to rebuild")
                return 0

            logger.info(
                f"Rebuilding search vectors for {total:,} messages",
                extra={"total": total, "batch_size": batch_size},
            )

            last_id = 0
            while True:
                cur.execute("""
                    WITH batch AS (
                        SELECT id FROM messages
                        WHERE id > %s
                        ORDER BY id
                        LIMIT %s
                    )
                    UPDATE messages m
                    SET subject = m.subject
                    FROM batch
                    WHERE m.id = batch.id
                    RETURNING m.id
                """, (last_id, batch_size))

                rows = cur.fetchall()
                updated = len(rows)
                conn.commit()

                if updated == 0:
                    break

                last_id = max(row[0] for row in rows)
                total_updated += updated
                progress = (total_updated / total) * 100

                logger.info(
                    f"Rebuilt {total_updated:,}/{total:,} ({progress:.1f}%)",
                    extra={"updated": total_updated, "total": total, "progress": progress},
                )

                if delay > 0:
                    time.sleep(delay)

    logger.info(
        f"Search vector rebuild complete: {total_updated:,} messages updated",
        extra={"total_updated": total_updated},
    )
    return total_updated


def migrate_device_tokens_schema() -> bool:
    """
    Migrate device_tokens table from hashtag_filters to search_filters + notify_all.
    
    This migration:
    - Adds search_filters column (if not exists)
    - Adds notify_all column (if not exists)
    - Drops hashtag_filters column (if exists)
    
    Returns:
        True if any changes were made, False if already migrated
    """
    db_url = get_db_url()
    changes_made = False

    with psycopg2.connect(db_url) as conn:
        with conn.cursor() as cur:
            # Check current columns
            cur.execute("""
                SELECT column_name FROM information_schema.columns
                WHERE table_name = 'device_tokens'
            """)
            existing_columns = {row[0] for row in cur.fetchall()}

            # Add search_filters if missing
            if 'search_filters' not in existing_columns:
                logger.info("Adding search_filters column to device_tokens")
                cur.execute("""
                    ALTER TABLE device_tokens 
                    ADD COLUMN search_filters TEXT[]
                """)
                changes_made = True

            # Add notify_all if missing
            if 'notify_all' not in existing_columns:
                logger.info("Adding notify_all column to device_tokens")
                cur.execute("""
                    ALTER TABLE device_tokens 
                    ADD COLUMN notify_all BOOLEAN DEFAULT FALSE
                """)
                changes_made = True

            # Drop hashtag_filters if it exists
            if 'hashtag_filters' in existing_columns:
                logger.info("Dropping hashtag_filters column from device_tokens")
                cur.execute("""
                    ALTER TABLE device_tokens 
                    DROP COLUMN hashtag_filters
                """)
                changes_made = True

            # Add composite index for notification queries
            cur.execute("""
                SELECT EXISTS (
                    SELECT 1 FROM pg_indexes
                    WHERE tablename = 'device_tokens' 
                    AND indexname = 'idx_device_tokens_notification'
                )
            """)
            has_notification_index = cur.fetchone()[0]
            
            if not has_notification_index:
                logger.info("Creating composite index for notification queries")
                cur.execute("""
                    CREATE INDEX idx_device_tokens_notification 
                    ON device_tokens (enabled, notify_all)
                    WHERE enabled = TRUE
                """)
                changes_made = True

            conn.commit()

    if changes_made:
        logger.info("device_tokens schema migration complete")
    else:
        logger.info("device_tokens schema already up to date")

    return changes_made


def check_schema_version(cur) -> dict:
    """
    Check current schema state and what migrations are needed.
    
    Returns dict with:
        - has_search_vector: bool
        - has_search_index: bool
        - has_search_trigger: bool
        - messages_without_sv: int
    """
    # Check if search_vector column exists
    cur.execute("""
        SELECT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_name = 'messages' AND column_name = 'search_vector'
        )
    """)
    has_search_vector = cur.fetchone()[0]

    # Check if GIN index exists
    cur.execute("""
        SELECT EXISTS (
            SELECT 1 FROM pg_indexes
            WHERE tablename = 'messages' AND indexname = 'idx_messages_search'
        )
    """)
    has_search_index = cur.fetchone()[0]

    # Check if trigger exists
    cur.execute("""
        SELECT EXISTS (
            SELECT 1 FROM pg_trigger
            WHERE tgname = 'messages_search_update'
        )
    """)
    has_search_trigger = cur.fetchone()[0]

    # Count messages without search vector
    messages_without_sv = 0
    if has_search_vector:
        cur.execute("SELECT COUNT(*) FROM messages WHERE search_vector IS NULL")
        messages_without_sv = cur.fetchone()[0]

    return {
        "has_search_vector": has_search_vector,
        "has_search_index": has_search_index,
        "has_search_trigger": has_search_trigger,
        "messages_without_sv": messages_without_sv,
    }


def run_pending_migrations() -> list[str]:
    """
    Check and run any pending migrations.
    
    Returns list of migrations that were run.
    """
    db_url = get_db_url()
    migrations_run = []

    with psycopg2.connect(db_url) as conn:
        with conn.cursor() as cur:
            status = check_schema_version(cur)

            # If search_vector column is missing, need to run init-db first
            if not status["has_search_vector"]:
                logger.warning(
                    "search_vector column missing - run 'python cli.py init-db' first"
                )
                return migrations_run

            # Check if we need to migrate search vectors
            if status["messages_without_sv"] > 0:
                logger.info(
                    f"Found {status['messages_without_sv']:,} messages without search vectors"
                )
                migrate_search_vectors()
                migrations_run.append("search_vectors")

    # Run device_tokens schema migration
    if migrate_device_tokens_schema():
        migrations_run.append("device_tokens_schema")

    return migrations_run


def print_migration_status() -> None:
    """Print current migration status."""
    db_url = get_db_url()

    with psycopg2.connect(db_url) as conn:
        with conn.cursor() as cur:
            status = check_schema_version(cur)

    print("\nMigration Status:")
    print(f"  search_vector column: {'✓' if status['has_search_vector'] else '✗'}")
    print(f"  GIN search index: {'✓' if status['has_search_index'] else '✗'}")
    print(f"  Search trigger: {'✓' if status['has_search_trigger'] else '✗'}")
    
    if status["messages_without_sv"] > 0:
        print(f"  ⚠️  Messages without search vector: {status['messages_without_sv']:,}")
        print("     Run 'python cli.py migrate-search' to fix")
    else:
        print("  All messages have search vectors: ✓")


if __name__ == "__main__":
    import logging
    from dotenv import load_dotenv
    load_dotenv()
    
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    
    print_migration_status()
