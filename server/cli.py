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


def cmd_poll(args):
    """Run the polling loop for new messages."""
    print("Polling not yet implemented (Phase 2)")
    # TODO: Implement in Phase 2


def cmd_backfill(args):
    """Run historical backfill."""
    print(f"Backfill not yet implemented (Phase 3)")
    print(f"  Delay between requests: {args.delay}s")
    # TODO: Implement in Phase 3


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

    # poll command
    poll_parser = subparsers.add_parser("poll", help="Poll for new messages")
    poll_parser.set_defaults(func=cmd_poll)

    # backfill command
    backfill_parser = subparsers.add_parser("backfill", help="Backfill historical data")
    backfill_parser.add_argument(
        "--delay",
        type=int,
        default=5,
        help="Seconds between API requests (default: 5)",
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
