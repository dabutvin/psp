#!/usr/bin/env python3
"""
CLI entry point for PSP server operations.
"""

import argparse
import sys


def cmd_init_db(args):
    """Initialize the database schema."""
    from core.database import init_schema_sync

    print("Initializing database schema...")
    init_schema_sync()


def cmd_stats(args):
    """Show system statistics."""
    from core.stats import get_system_stats, print_stats

    if args.json:
        import json
        stats = get_system_stats()
        print(json.dumps(stats, indent=2, default=str))
    else:
        stats = get_system_stats()
        print_stats(stats)


def cmd_migrate(args):
    """Run all pending database migrations."""
    import logging
    from core.logging import setup_logging
    from core.migrations import run_pending_migrations, print_migration_status

    if args.status:
        print_migration_status()
        return

    setup_logging(
        level=logging.DEBUG if args.verbose else logging.INFO,
        json_format=args.json,
    )

    print("Running pending migrations...")
    migrations_run = run_pending_migrations()
    
    if migrations_run:
        print(f"Done! Ran {len(migrations_run)} migration(s): {', '.join(migrations_run)}")
    else:
        print("No pending migrations.")


def cmd_migrate_search(args):
    """Migrate search vectors for existing messages."""
    import logging
    from core.logging import setup_logging
    from core.migrations import migrate_search_vectors, print_migration_status

    if args.status:
        print_migration_status()
        return

    setup_logging(
        level=logging.DEBUG if args.verbose else logging.INFO,
        json_format=args.json,
    )

    print(f"Migrating search vectors (batch_size={args.batch}, delay={args.delay}s)...")
    count = migrate_search_vectors(
        batch_size=args.batch,
        delay=args.delay,
    )
    print(f"Done! Updated {count:,} messages.")


def cmd_test_api(args):
    """Test API connectivity."""
    from sync.client import test_connection

    print("Testing groups.io API connection...")
    success = test_connection()
    sys.exit(0 if success else 1)


def cmd_fetch(args):
    """Fetch new messages until we hit one we already have."""
    import logging
    import time
    from core.logging import setup_logging

    from sync.fetch import fetch_new_messages

    setup_logging(
        level=logging.DEBUG if args.verbose else logging.INFO,
        json_format=args.json,
    )

    if not args.json:
        print(f"Fetching new messages (max: {args.max})...")
    
    count = fetch_new_messages(
        batch_size=args.batch,
        max_messages=args.max,
        dry_run=args.dry_run,
    )
    
    if not args.json:
        print(f"Done! Fetched {count} new messages.")
    
    # Optional sleep to keep machine alive (for setting up schedules)
    if args.sleep:
        logger = logging.getLogger("fetch")
        logger.info(f"Sleeping for {args.sleep} seconds (set schedule now!)...")
        remaining = args.sleep
        while remaining > 0:
            logger.info(f"  {remaining} seconds remaining...")
            time.sleep(min(30, remaining))
            remaining -= 30
        logger.info("Sleep complete, exiting.")


def cmd_backfill(args):
    """Run historical backfill."""
    import json
    import logging
    from core.logging import setup_logging

    from sync.backfill import backfill_messages, get_backfill_status, reset_backfill

    setup_logging(
        level=logging.DEBUG if args.verbose else logging.INFO,
        json_format=args.json,
    )

    # Handle --status flag
    if args.status:
        status = get_backfill_status()
        if args.json:
            print(json.dumps(status, default=str))
        else:
            print("Backfill Status:")
            print(f"  Messages in DB: {status['messages_count']:,}")
            if status['oldest_message_id']:
                print(f"  Message ID range: {status['oldest_message_id']:,} - {status['newest_message_id']:,}")
            print(f"  Backfill complete: {status['is_complete']}")
            if status['backfill_page_token']:
                print(f"  Resume token: {status['backfill_page_token']:,}")
        return

    # Handle --reset flag
    if args.reset:
        if not args.json:
            print("Resetting backfill state...")
        reset_backfill()
        if not args.json:
            print("Done! Run 'backfill' again to start from the beginning.")
        return

    # Run backfill
    if not args.json:
        print(f"Starting backfill (delay: {args.delay}s between requests)...")
        if args.max:
            print(f"  Max messages this run: {args.max:,}")
        print("  Press Ctrl+C to stop gracefully\n")

    count, is_complete = backfill_messages(
        batch_size=args.batch,
        max_messages=args.max,
        delay=args.delay,
        dry_run=args.dry_run,
    )

    if not args.json:
        print(f"\nDone! Fetched {count:,} new messages.")
        if is_complete:
            print("Backfill is complete - all historical messages fetched!")
        else:
            print("Backfill paused - run again to continue.")


def cmd_test_notify(args):
    """Send a test push notification to a registered device."""
    import asyncio
    from sync.notify import APNsConfig, APNsClient, send_new_post_notifications, send_summary_notifications
    from core.database import get_database

    async def _send_summary():
        """Test the full summary notification code path."""
        db = get_database()
        await db.connect()

        count = args.count
        rows = await db.fetch(
            "SELECT id, subject FROM messages ORDER BY id DESC LIMIT $1", count
        )
        if not rows:
            print("Error: No messages in database.")
            sys.exit(1)

        messages = [
            {"id": row["id"], "subject": row["subject"], "hashtags": []}
            for row in rows
        ]

        print(f"Sending summary notification for {len(messages)} posts:")
        for msg in messages:
            print(f"  - [{msg['id']}] {msg['subject'][:60]}")

        sent = await send_summary_notifications(messages)
        print(f"\nSent {sent} summary notification(s).")

        if sent == 0:
            print("Hint: Make sure your device has notify_summary = TRUE in the database.")

        await db.disconnect()

    async def _send_individual():
        """Test a single individual notification."""
        config = APNsConfig.from_settings()
        if not config:
            print("Error: APNs not configured. Set APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, and APNS_KEY_PATH or APNS_KEY_CONTENT.")
            sys.exit(1)

        db = get_database()
        await db.connect()

        if args.token:
            token = args.token
            environment = args.environment
        else:
            row = await db.fetchrow(
                "SELECT token, environment FROM device_tokens WHERE enabled = TRUE ORDER BY updated_at DESC LIMIT 1"
            )
            if not row:
                print("Error: No registered devices found. Pass --token explicitly.")
                sys.exit(1)
            token = row["token"]
            environment = row["environment"]
            print(f"Using most recently updated device: {token[:8]}... ({environment})")

        post_id = args.post_id
        if not post_id:
            row = await db.fetchrow("SELECT id FROM messages ORDER BY id DESC LIMIT 1")
            if row:
                post_id = row["id"]
                print(f"Using latest post ID: {post_id}")
            else:
                post_id = 1
                print(f"No posts in DB, using post_id={post_id}")

        title = "Test Notification"
        body = f"Tap to open post {post_id}"
        data = {"post_id": post_id}

        print(f"Sending to {token[:8]}... ({environment})")
        print(f"  Payload: post_id={post_id}")

        import httpx
        base_url = "https://api.push.apple.com" if environment == "production" else "https://api.sandbox.push.apple.com"
        url = f"{base_url}/3/device/{token}"

        payload = {
            "aps": {
                "alert": {"title": title, "body": body},
                "sound": "default",
                "badge": 1,
            },
            **data,
        }

        async with APNsClient(config) as client:
            jwt_token = client._get_token()

        headers = {
            "authorization": f"bearer {jwt_token}",
            "apns-topic": config.bundle_id,
            "apns-push-type": "alert",
            "apns-priority": "10",
        }

        print(f"  URL: {url}")
        async with httpx.AsyncClient(http2=True, timeout=30.0) as http:
            response = await http.post(url, json=payload, headers=headers)

        print(f"  Status: {response.status_code}")
        if response.content:
            print(f"  Response: {response.text}")

        if response.status_code == 200:
            print("Sent successfully!")
        else:
            print("Failed.")

        await db.disconnect()

    if args.summary:
        asyncio.run(_send_summary())
    else:
        asyncio.run(_send_individual())


def cmd_serve(args):
    """Start the API server."""
    from server import run_server

    print(f"Starting PSP API server...")
    print(f"  Host: {args.host}")
    print(f"  Port: {args.port}")
    print(f"  Docs: http://{args.host}:{args.port}/docs")
    print()
    
    run_server(
        host=args.host,
        port=args.port,
        reload=args.reload,
    )


def main():
    parser = argparse.ArgumentParser(
        description="Park Slope Parents Message Ingestion System",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # init-db command
    init_parser = subparsers.add_parser("init-db", help="Initialize database schema")
    init_parser.set_defaults(func=cmd_init_db)

    # test-api command
    test_parser = subparsers.add_parser("test-api", help="Test API connectivity")
    test_parser.set_defaults(func=cmd_test_api)

    # stats command
    stats_parser = subparsers.add_parser(
        "stats", help="Show system statistics"
    )
    stats_parser.add_argument(
        "--json", action="store_true", help="Output as JSON"
    )
    stats_parser.set_defaults(func=cmd_stats)

    # migrate command (runs all pending migrations)
    migrate_all_parser = subparsers.add_parser(
        "migrate",
        help="Run all pending database migrations",
        description="Run all pending migrations including schema changes and data backfills.",
    )
    migrate_all_parser.add_argument(
        "--status", action="store_true", help="Show migration status and exit"
    )
    migrate_all_parser.add_argument(
        "--json", action="store_true", help="Output logs as JSON"
    )
    migrate_all_parser.add_argument(
        "-v", "--verbose", action="store_true", help="Verbose output"
    )
    migrate_all_parser.set_defaults(func=cmd_migrate)

    # migrate-search command
    migrate_parser = subparsers.add_parser(
        "migrate-search",
        help="Populate search vectors for existing messages",
        description="Backfill the search_vector column for messages that don't have one.",
    )
    migrate_parser.add_argument(
        "--batch", type=int, default=1000, help="Messages per batch (default: 1000)"
    )
    migrate_parser.add_argument(
        "--delay", type=float, default=0.1, help="Seconds between batches (default: 0.1)"
    )
    migrate_parser.add_argument(
        "--status", action="store_true", help="Show migration status and exit"
    )
    migrate_parser.add_argument(
        "--json", action="store_true", help="Output logs as JSON"
    )
    migrate_parser.add_argument(
        "-v", "--verbose", action="store_true", help="Verbose output"
    )
    migrate_parser.set_defaults(func=cmd_migrate_search)

    # fetch command
    fetch_parser = subparsers.add_parser(
        "fetch", help="Fetch new messages until caught up"
    )
    fetch_parser.add_argument(
        "--batch", type=int, default=100, help="Messages per API call (default: 100)"
    )
    fetch_parser.add_argument(
        "--max", type=int, default=1000, help="Max messages to fetch (default: 1000)"
    )
    fetch_parser.add_argument(
        "--dry-run", action="store_true", help="Don't insert into database"
    )
    fetch_parser.add_argument(
        "--json", action="store_true", help="Output logs as JSON"
    )
    fetch_parser.add_argument(
        "-v", "--verbose", action="store_true", help="Verbose output"
    )
    fetch_parser.add_argument(
        "--sleep", type=int, default=0, help="Seconds to sleep after fetch (for setting up schedules)"
    )
    fetch_parser.set_defaults(func=cmd_fetch)

    # backfill command
    backfill_parser = subparsers.add_parser(
        "backfill",
        help="Backfill historical data (newest to oldest)",
        description="Fetch historical messages from groups.io, starting with most recent. Resumable - can stop/start anytime.",
    )
    backfill_parser.add_argument(
        "--delay",
        type=float,
        default=5.0,
        help="Seconds between API requests (default: 5.0, be gentle!)",
    )
    backfill_parser.add_argument(
        "--batch",
        type=int,
        default=100,
        help="Messages per API call (default: 100, max: 100)",
    )
    backfill_parser.add_argument(
        "--max",
        type=int,
        default=None,
        help="Max messages to fetch this run (default: no limit)",
    )
    backfill_parser.add_argument(
        "--status",
        action="store_true",
        help="Show backfill status and exit",
    )
    backfill_parser.add_argument(
        "--reset",
        action="store_true",
        help="Reset backfill state to start from beginning",
    )
    backfill_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Don't insert into database",
    )
    backfill_parser.add_argument(
        "--json",
        action="store_true",
        help="Output logs as JSON",
    )
    backfill_parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Verbose output",
    )
    backfill_parser.set_defaults(func=cmd_backfill)

    # test-notify command
    test_notify_parser = subparsers.add_parser(
        "test-notify",
        help="Send a test push notification to a device",
        description="Send a test notification with a post_id payload. "
                    "Defaults to the most recently updated device and the latest post.",
    )
    test_notify_parser.add_argument(
        "--token", type=str, default=None, help="Device token (default: most recently updated device)"
    )
    test_notify_parser.add_argument(
        "--post-id", type=int, default=None, help="Post ID to include in payload (default: latest post)"
    )
    test_notify_parser.add_argument(
        "--environment", type=str, default="production",
        choices=["production", "sandbox"],
        help="APNs environment (default: production)"
    )
    test_notify_parser.add_argument(
        "--summary", action="store_true",
        help="Send a summary notification instead of an individual one"
    )
    test_notify_parser.add_argument(
        "--count", type=int, default=3,
        help="Number of recent posts to include in summary (default: 3)"
    )
    test_notify_parser.set_defaults(func=cmd_test_notify)

    # serve command
    serve_parser = subparsers.add_parser("serve", help="Start API server")
    serve_parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
    serve_parser.add_argument("--port", type=int, default=8000, help="Port to bind to")
    serve_parser.add_argument("--reload", action="store_true", help="Enable auto-reload for development")
    serve_parser.set_defaults(func=cmd_serve)

    args = parser.parse_args()

    if args.command is None:
        parser.print_help()
        sys.exit(1)

    # Load environment variables
    from dotenv import load_dotenv

    load_dotenv()

    # Run the command
    args.func(args)


if __name__ == "__main__":
    main()
