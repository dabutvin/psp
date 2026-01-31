"""
Stats module for PSP server.

Provides observability into the system state:
- Message counts and date ranges
- Sync status (last fetch, backfill progress)
- Hashtag distributions
- Database health metrics
"""

from datetime import datetime
from typing import Any

import psycopg2

from config import get_db_url


def get_system_stats() -> dict[str, Any]:
    """
    Get comprehensive system statistics.
    
    Returns dict with:
        - messages: total count, date range, recent activity
        - sync: last fetch time, backfill status
        - hashtags: top hashtags by count
        - database: table sizes, index usage
    """
    db_url = get_db_url()
    stats: dict[str, Any] = {}

    with psycopg2.connect(db_url) as conn:
        with conn.cursor() as cur:
            # Message statistics
            stats["messages"] = _get_message_stats(cur)

            # Sync state
            stats["sync"] = _get_sync_stats(cur)

            # Hashtag distribution
            stats["hashtags"] = _get_hashtag_stats(cur)

            # Database metrics
            stats["database"] = _get_database_stats(cur)

    return stats


def _get_message_stats(cur) -> dict[str, Any]:
    """Get message-related statistics."""
    # Total count
    cur.execute("SELECT COUNT(*) FROM messages")
    total_count = cur.fetchone()[0]

    # Date range
    cur.execute("""
        SELECT 
            MIN(created) as oldest,
            MAX(created) as newest,
            MIN(id) as min_id,
            MAX(id) as max_id
        FROM messages
    """)
    row = cur.fetchone()
    oldest_date, newest_date, min_id, max_id = row

    # Messages in last 24 hours
    cur.execute("""
        SELECT COUNT(*) FROM messages 
        WHERE created > NOW() - INTERVAL '24 hours'
    """)
    last_24h = cur.fetchone()[0]

    # Messages in last 7 days
    cur.execute("""
        SELECT COUNT(*) FROM messages 
        WHERE created > NOW() - INTERVAL '7 days'
    """)
    last_7d = cur.fetchone()[0]

    # Reply vs original posts
    cur.execute("""
        SELECT 
            COUNT(*) FILTER (WHERE is_reply = false) as originals,
            COUNT(*) FILTER (WHERE is_reply = true) as replies
        FROM messages
    """)
    originals, replies = cur.fetchone()

    # Messages with attachments
    cur.execute("""
        SELECT COUNT(DISTINCT message_id) FROM attachments
    """)
    with_attachments = cur.fetchone()[0]

    return {
        "total_count": total_count,
        "oldest_date": oldest_date.isoformat() if oldest_date else None,
        "newest_date": newest_date.isoformat() if newest_date else None,
        "id_range": {"min": min_id, "max": max_id},
        "last_24_hours": last_24h,
        "last_7_days": last_7d,
        "originals": originals,
        "replies": replies,
        "with_attachments": with_attachments,
    }


def _get_sync_stats(cur) -> dict[str, Any]:
    """Get sync state statistics."""
    cur.execute("""
        SELECT 
            last_fetch_at,
            newest_message_id,
            oldest_message_id,
            backfill_page_token
        FROM sync_state 
        WHERE id = 1
    """)
    row = cur.fetchone()

    if not row:
        return {
            "last_fetch_at": None,
            "newest_message_id": None,
            "oldest_message_id": None,
            "backfill_in_progress": False,
            "backfill_page_token": None,
        }

    last_fetch, newest_id, oldest_id, backfill_token = row

    return {
        "last_fetch_at": last_fetch.isoformat() if last_fetch else None,
        "newest_message_id": newest_id,
        "oldest_message_id": oldest_id,
        "backfill_in_progress": backfill_token is not None,
        "backfill_page_token": backfill_token,
    }


def _get_hashtag_stats(cur, limit: int = 10) -> dict[str, Any]:
    """Get hashtag distribution statistics."""
    # Total unique hashtags
    cur.execute("SELECT COUNT(DISTINCT name) FROM hashtags")
    unique_count = cur.fetchone()[0]

    # Top hashtags by count
    cur.execute("""
        SELECT name, color_hex, COUNT(*) as count
        FROM hashtags
        GROUP BY name, color_hex
        ORDER BY count DESC
        LIMIT %s
    """, (limit,))
    
    top_hashtags = [
        {"name": row[0], "color_hex": row[1], "count": row[2]}
        for row in cur.fetchall()
    ]

    # Category breakdown (ForSale, ForFree, ISO)
    cur.execute("""
        SELECT 
            LOWER(name) as category,
            COUNT(*) as count
        FROM hashtags
        WHERE LOWER(name) IN ('forsale', 'forfree', 'iso')
        GROUP BY LOWER(name)
    """)
    categories = {row[0]: row[1] for row in cur.fetchall()}

    return {
        "unique_count": unique_count,
        "top_hashtags": top_hashtags,
        "categories": {
            "forsale": categories.get("forsale", 0),
            "forfree": categories.get("forfree", 0),
            "iso": categories.get("iso", 0),
        },
    }


def _get_database_stats(cur) -> dict[str, Any]:
    """Get database health and size statistics."""
    # Table sizes
    cur.execute("""
        SELECT 
            relname as table_name,
            pg_size_pretty(pg_total_relation_size(relid)) as total_size,
            pg_total_relation_size(relid) as size_bytes
        FROM pg_catalog.pg_statio_user_tables
        WHERE schemaname = 'public'
        ORDER BY pg_total_relation_size(relid) DESC
    """)
    
    tables = [
        {"name": row[0], "size": row[1], "size_bytes": row[2]}
        for row in cur.fetchall()
    ]

    # Total database size
    cur.execute("SELECT pg_size_pretty(pg_database_size(current_database()))")
    total_size = cur.fetchone()[0]

    # Index usage stats
    cur.execute("""
        SELECT 
            indexrelname as index_name,
            idx_scan as scans,
            pg_size_pretty(pg_relation_size(indexrelid)) as size
        FROM pg_stat_user_indexes
        WHERE schemaname = 'public'
        ORDER BY idx_scan DESC
        LIMIT 10
    """)
    
    indexes = [
        {"name": row[0], "scans": row[1], "size": row[2]}
        for row in cur.fetchall()
    ]

    # Check if search_vector is populated
    cur.execute("""
        SELECT 
            COUNT(*) as total,
            COUNT(search_vector) as with_search_vector
        FROM messages
    """)
    total, with_sv = cur.fetchone()
    search_coverage = (with_sv / total * 100) if total > 0 else 0

    return {
        "total_size": total_size,
        "tables": tables,
        "indexes": indexes,
        "search_vector_coverage": f"{search_coverage:.1f}%",
        "messages_without_search_vector": total - with_sv,
    }


def print_stats(stats: dict[str, Any]) -> None:
    """Print stats in a human-readable format."""
    print("\n" + "=" * 60)
    print("PSP SERVER STATISTICS")
    print("=" * 60)

    # Messages
    msg = stats["messages"]
    print("\n📬 MESSAGES")
    print(f"  Total: {msg['total_count']:,}")
    if msg['oldest_date'] and msg['newest_date']:
        print(f"  Date range: {msg['oldest_date'][:10]} → {msg['newest_date'][:10]}")
    if msg['id_range']['min'] and msg['id_range']['max']:
        print(f"  ID range: {msg['id_range']['min']:,} → {msg['id_range']['max']:,}")
    print(f"  Last 24 hours: {msg['last_24_hours']:,}")
    print(f"  Last 7 days: {msg['last_7_days']:,}")
    print(f"  Original posts: {msg['originals']:,}")
    print(f"  Replies: {msg['replies']:,}")
    print(f"  With attachments: {msg['with_attachments']:,}")

    # Sync
    sync = stats["sync"]
    print("\n🔄 SYNC STATUS")
    if sync['last_fetch_at']:
        print(f"  Last fetch: {sync['last_fetch_at']}")
    else:
        print("  Last fetch: Never")
    if sync['backfill_in_progress']:
        print(f"  Backfill: In progress (token: {sync['backfill_page_token']:,})")
    else:
        print("  Backfill: Complete")

    # Hashtags
    ht = stats["hashtags"]
    print("\n🏷️  HASHTAGS")
    print(f"  Unique hashtags: {ht['unique_count']:,}")
    print("  Categories:")
    print(f"    ForSale: {ht['categories']['forsale']:,}")
    print(f"    ForFree: {ht['categories']['forfree']:,}")
    print(f"    ISO: {ht['categories']['iso']:,}")
    if ht['top_hashtags']:
        print("  Top hashtags:")
        for h in ht['top_hashtags'][:5]:
            print(f"    {h['name']}: {h['count']:,}")

    # Database
    db = stats["database"]
    print("\n💾 DATABASE")
    print(f"  Total size: {db['total_size']}")
    print(f"  Search vector coverage: {db['search_vector_coverage']}")
    if db['messages_without_search_vector'] > 0:
        print(f"  ⚠️  Messages without search vector: {db['messages_without_search_vector']:,}")
        print("     Run 'python cli.py migrate-search' to fix")
    if db['tables']:
        print("  Table sizes:")
        for t in db['tables']:
            print(f"    {t['name']}: {t['size']}")

    print("\n" + "=" * 60)


if __name__ == "__main__":
    # Quick test when run directly
    from dotenv import load_dotenv
    load_dotenv()
    
    stats = get_system_stats()
    print_stats(stats)
