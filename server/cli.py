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
