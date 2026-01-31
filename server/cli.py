#!/usr/bin/env python3
"""
CLI entry point for PSP server operations.
"""

import argparse
import sys


def cmd_init_db(args):
    """Initialize the database schema."""
    from db import init_schema_sync

    print("Initializing database schema...")
    init_schema_sync()


def cmd_test_api(args):
    """Test API connectivity."""
    from api_client import test_connection

    print("Testing groups.io API connection...")
    success = test_connection()
    sys.exit(0 if success else 1)


def cmd_fetch(args):
    """Fetch new messages until we hit one we already have."""
    import logging

    from fetch import fetch_new_messages

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    print(f"Fetching new messages (max: {args.max})...")
    count = fetch_new_messages(
        batch_size=args.batch,
        max_messages=args.max,
        dry_run=args.dry_run,
    )
    print(f"Done! Fetched {count} new messages.")


def cmd_backfill(args):
    """Run historical backfill."""
    import logging

    from backfill import backfill_messages, get_backfill_status, reset_backfill

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    # Handle --status flag
    if args.status:
        status = get_backfill_status()
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
        print("Resetting backfill state...")
        reset_backfill()
        print("Done! Run 'backfill' again to start from the beginning.")
        return

    # Run backfill
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

    print(f"\nDone! Fetched {count:,} new messages.")
    if is_complete:
        print("Backfill is complete - all historical messages fetched!")
    else:
        print("Backfill paused - run again to continue.")


def cmd_serve(args):
    """Start the API server."""
    print(f"API server not yet implemented (Phase 5)")
    print(f"  Host: {args.host}")
    print(f"  Port: {args.port}")
    # TODO: Implement in Phase 5


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
        "-v", "--verbose",
        action="store_true",
        help="Verbose output",
    )
    backfill_parser.set_defaults(func=cmd_backfill)

    # serve command
    serve_parser = subparsers.add_parser("serve", help="Start API server")
    serve_parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
    serve_parser.add_argument("--port", type=int, default=8000, help="Port to bind to")
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
