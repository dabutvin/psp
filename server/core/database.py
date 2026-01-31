"""
Database module for PSP server.
Handles PostgreSQL connection and schema initialization.
"""

import asyncio
from contextlib import asynccontextmanager
from typing import AsyncGenerator

import asyncpg
import psycopg2
from psycopg2.extras import RealDictCursor

from core.config import get_db_url

# Schema definition
SCHEMA_SQL = """
-- Messages table (main data)
CREATE TABLE IF NOT EXISTS messages (
    id BIGINT PRIMARY KEY,               -- groups.io message id
    topic_id BIGINT,
    group_id INTEGER,
    created TIMESTAMPTZ,
    updated TIMESTAMPTZ,
    subject TEXT,
    body TEXT,
    snippet TEXT,
    name TEXT,                           -- sender display name
    sender_email TEXT,                   -- extracted email for reply-to
    msg_num INTEGER,
    is_reply BOOLEAN,
    is_plain_text BOOLEAN,
    reply_to TEXT,
    fetched_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for messages
CREATE INDEX IF NOT EXISTS idx_messages_created ON messages(created DESC);
CREATE INDEX IF NOT EXISTS idx_messages_topic_id ON messages(topic_id);
CREATE INDEX IF NOT EXISTS idx_messages_msg_num ON messages(msg_num);
CREATE INDEX IF NOT EXISTS idx_messages_id_created ON messages(id DESC, created DESC);

-- Hashtags table
CREATE TABLE IF NOT EXISTS hashtags (
    id SERIAL PRIMARY KEY,
    message_id BIGINT REFERENCES messages(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color_hex TEXT
);

CREATE INDEX IF NOT EXISTS idx_hashtags_name ON hashtags(name);
CREATE INDEX IF NOT EXISTS idx_hashtags_message_id ON hashtags(message_id);

-- Attachments table
CREATE TABLE IF NOT EXISTS attachments (
    id SERIAL PRIMARY KEY,
    message_id BIGINT REFERENCES messages(id) ON DELETE CASCADE,
    attachment_index INTEGER,            -- 0, 1, 2... within message
    download_url TEXT,
    thumbnail_url TEXT,
    filename TEXT,
    media_type TEXT                      -- e.g. "image/jpeg"
);

CREATE INDEX IF NOT EXISTS idx_attachments_message_id ON attachments(message_id);

-- Sync state table (singleton row)
CREATE TABLE IF NOT EXISTS sync_state (
    id INTEGER PRIMARY KEY DEFAULT 1,
    last_fetch_at TIMESTAMPTZ,
    newest_message_id BIGINT,
    oldest_message_id BIGINT,
    backfill_page_token BIGINT           -- for resumable backfill
);

-- Initialize sync_state if empty
INSERT INTO sync_state (id) VALUES (1) ON CONFLICT (id) DO NOTHING;
"""

# Full-text search setup (run after initial schema)
SEARCH_SCHEMA_SQL = """
-- Add tsvector column for full-text search
ALTER TABLE messages ADD COLUMN IF NOT EXISTS search_vector tsvector;

-- Create GIN index for fast search
CREATE INDEX IF NOT EXISTS idx_messages_search ON messages USING GIN(search_vector);

-- Trigger function to keep search_vector updated
CREATE OR REPLACE FUNCTION messages_search_trigger() RETURNS trigger AS $$
BEGIN
    NEW.search_vector := to_tsvector('english', coalesce(NEW.subject, '') || ' ' || coalesce(NEW.body, ''));
    RETURN NEW;
END
$$ LANGUAGE plpgsql;

-- Create trigger (drop first to avoid duplicates)
DROP TRIGGER IF EXISTS messages_search_update ON messages;
CREATE TRIGGER messages_search_update
    BEFORE INSERT OR UPDATE ON messages
    FOR EACH ROW EXECUTE FUNCTION messages_search_trigger();
"""


class Database:
    """Async database connection manager using asyncpg."""

    def __init__(self, database_url: str | None = None):
        self.database_url = database_url or get_db_url()
        self._pool: asyncpg.Pool | None = None

    async def connect(self) -> None:
        """Create connection pool."""
        if self._pool is None:
            self._pool = await asyncpg.create_pool(
                self.database_url,
                min_size=2,
                max_size=10,
            )

    async def disconnect(self) -> None:
        """Close connection pool."""
        if self._pool:
            await self._pool.close()
            self._pool = None

    @asynccontextmanager
    async def acquire(self) -> AsyncGenerator[asyncpg.Connection, None]:
        """Acquire a connection from the pool."""
        if self._pool is None:
            await self.connect()
        async with self._pool.acquire() as conn:
            yield conn

    async def execute(self, query: str, *args) -> str:
        """Execute a query."""
        async with self.acquire() as conn:
            return await conn.execute(query, *args)

    async def fetch(self, query: str, *args) -> list[asyncpg.Record]:
        """Fetch multiple rows."""
        async with self.acquire() as conn:
            return await conn.fetch(query, *args)

    async def fetchrow(self, query: str, *args) -> asyncpg.Record | None:
        """Fetch a single row."""
        async with self.acquire() as conn:
            return await conn.fetchrow(query, *args)

    async def fetchval(self, query: str, *args):
        """Fetch a single value."""
        async with self.acquire() as conn:
            return await conn.fetchval(query, *args)


# Singleton database instance
_db: Database | None = None


def get_database() -> Database:
    """Get the singleton database instance."""
    global _db
    if _db is None:
        _db = Database()
    return _db


# Synchronous functions for scripts/CLI

def init_schema_sync() -> None:
    """
    Initialize database schema using synchronous psycopg2.
    Useful for setup scripts and CLI.
    """
    db_url = get_db_url()
    print(f"Connecting to database...")

    with psycopg2.connect(db_url) as conn:
        with conn.cursor() as cur:
            print("Creating base schema...")
            cur.execute(SCHEMA_SQL)

            print("Setting up full-text search...")
            cur.execute(SEARCH_SCHEMA_SQL)

        conn.commit()

    print("Schema initialized successfully!")


def get_sync_connection():
    """Get a synchronous psycopg2 connection."""
    return psycopg2.connect(get_db_url(), cursor_factory=RealDictCursor)


async def init_schema_async() -> None:
    """Initialize database schema using async connection."""
    db = get_database()
    await db.connect()

    print("Creating base schema...")
    await db.execute(SCHEMA_SQL)

    print("Setting up full-text search...")
    await db.execute(SEARCH_SCHEMA_SQL)

    print("Schema initialized successfully!")


if __name__ == "__main__":
    # Run schema initialization when executed directly
    init_schema_sync()
