"""
Pytest configuration and fixtures for PSP server tests.
"""

from datetime import datetime, timezone
from typing import Any
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient


# Mock database records (simulating asyncpg.Record behavior)
class MockRecord(dict):
    """Mock asyncpg.Record that supports both dict and attribute access."""
    
    def __getattr__(self, key: str) -> Any:
        try:
            return self[key]
        except KeyError:
            raise AttributeError(key)


def make_record(**kwargs) -> MockRecord:
    """Create a mock database record."""
    return MockRecord(**kwargs)


# Sample test data
SAMPLE_MESSAGES = [
    make_record(
        id=1001,
        subject="For Sale: Vintage Chair $50",
        snippet="Beautiful vintage chair in great condition...",
        body="Beautiful vintage chair in great condition. Pick up in Park Slope.",
        created=datetime(2026, 1, 30, 12, 0, 0, tzinfo=timezone.utc),
        name="Alice Smith",
        sender_email="alice@example.com",
        is_reply=False,
        topic_id=1001,
        msg_num=1,
        reply_to=None,
    ),
    make_record(
        id=1002,
        subject="ISO: Kids Toys",
        snippet="Looking for gently used toys for my toddler...",
        body="Looking for gently used toys for my toddler. Thanks!",
        created=datetime(2026, 1, 29, 10, 0, 0, tzinfo=timezone.utc),
        name="Bob Johnson",
        sender_email="bob@example.com",
        is_reply=False,
        topic_id=1002,
        msg_num=1,
        reply_to=None,
    ),
    make_record(
        id=1003,
        subject="Free: Baby Clothes",
        snippet="Giving away baby clothes 0-6 months...",
        body="Giving away baby clothes 0-6 months. Must pick up today.",
        created=datetime(2026, 1, 28, 8, 0, 0, tzinfo=timezone.utc),
        name="Carol Davis",
        sender_email="carol@example.com",
        is_reply=False,
        topic_id=1003,
        msg_num=1,
        reply_to=None,
    ),
]

SAMPLE_HASHTAGS = {
    1001: [
        make_record(message_id=1001, name="ForSale", color_hex="#4CAF50"),
        make_record(message_id=1001, name="furniture", color_hex=None),
        make_record(message_id=1001, name="parkslope", color_hex=None),
    ],
    1002: [
        make_record(message_id=1002, name="iso", color_hex="#2196F3"),
        make_record(message_id=1002, name="toys", color_hex=None),
        make_record(message_id=1002, name="KidStuff", color_hex=None),
    ],
    1003: [
        make_record(message_id=1003, name="ForFree", color_hex="#9C27B0"),
        make_record(message_id=1003, name="babyclothes", color_hex=None),
        make_record(message_id=1003, name="parkslope", color_hex=None),
    ],
}

SAMPLE_ATTACHMENTS: dict[int, list] = {
    1001: [],
    1002: [],
    1003: [],
}


class MockDatabase:
    """Mock database for testing."""
    
    def __init__(self):
        self.messages = list(SAMPLE_MESSAGES)
        self.hashtags = dict(SAMPLE_HASHTAGS)
        self.attachments = dict(SAMPLE_ATTACHMENTS)
    
    async def connect(self):
        pass
    
    async def disconnect(self):
        pass
    
    async def fetch(self, query: str, *args) -> list[MockRecord]:
        """Mock fetch that handles common query patterns."""
        query_lower = query.lower()
        
        # Hashtags query for related data
        if "from hashtags" in query_lower and "message_id = any" in query_lower:
            message_ids = args[0] if args else []
            results = []
            for msg_id in message_ids:
                results.extend(self.hashtags.get(msg_id, []))
            return results
        
        # Attachments query for related data
        if "from attachments" in query_lower and "message_id = any" in query_lower:
            message_ids = args[0] if args else []
            results = []
            for msg_id in message_ids:
                results.extend(self.attachments.get(msg_id, []))
            return results
        
        # Messages query - need to parse and filter
        if "from messages" in query_lower:
            return self._filter_messages(query, args)
        
        # Hashtags aggregation query
        if "from hashtags" in query_lower and "group by" in query_lower:
            return self._aggregate_hashtags()
        
        return []
    
    async def fetchrow(self, query: str, *args) -> MockRecord | None:
        results = await self.fetch(query, *args)
        return results[0] if results else None
    
    async def fetchval(self, query: str, *args) -> Any:
        if "select 1" in query.lower():
            return 1
        return None
    
    def _filter_messages(self, query: str, args: tuple) -> list[MockRecord]:
        """Filter messages based on query parameters."""
        results = list(self.messages)
        query_lower = query.lower()
        
        # Check for hashtag join - means we need to filter by hashtag
        if "join hashtags" in query_lower:
            # Find the hashtag filter parameter
            # Look for LOWER(h.name) = ANY($N) pattern
            if "lower(h.name) = any" in query_lower:
                # Find which parameter index has the hashtag list
                param_idx = self._find_param_index(query, "any")
                if param_idx is not None and param_idx < len(args):
                    hashtag_list = args[param_idx]
                    hashtag_set = set(h.lower() for h in hashtag_list)
                    
                    # Filter messages that have any of the hashtags
                    filtered_ids = set()
                    for msg_id, tags in self.hashtags.items():
                        tag_names = set(t["name"].lower() for t in tags)
                        if tag_names & hashtag_set:
                            filtered_ids.add(msg_id)
                    
                    results = [m for m in results if m["id"] in filtered_ids]
        
        # Apply limit (always last parameter)
        if "limit" in query_lower:
            limit = args[-1] if args else 20
            results = results[:limit]
        
        return results
    
    def _find_param_index(self, query: str, keyword: str) -> int | None:
        """Find the parameter index for a given keyword in query."""
        import re
        # Look for $N pattern near the keyword
        pattern = rf'{keyword}\s*\(\s*\$(\d+)\s*\)'
        match = re.search(pattern, query.lower())
        if match:
            return int(match.group(1)) - 1  # Convert to 0-indexed
        return None
    
    def _aggregate_hashtags(self) -> list[MockRecord]:
        """Aggregate hashtags with counts."""
        counts: dict[str, dict] = {}
        for tags in self.hashtags.values():
            for tag in tags:
                name = tag["name"]
                if name not in counts:
                    counts[name] = {"name": name, "color_hex": tag["color_hex"], "count": 0}
                counts[name]["count"] += 1
        
        # Sort by count descending
        sorted_tags = sorted(counts.values(), key=lambda x: x["count"], reverse=True)
        return [make_record(**t) for t in sorted_tags]


@pytest.fixture
def mock_db():
    """Provide a mock database instance."""
    return MockDatabase()


@pytest.fixture
def client(mock_db):
    """
    Create a test client with mocked database.
    
    This patches the database singleton before importing the app,
    ensuring all routes use the mock database.
    """
    with patch("core.database._db", mock_db):
        with patch("core.database.get_database", return_value=mock_db):
            # Import app after patching to ensure routes use mock
            from server import app
            
            # Disable rate limiting for tests
            app.state.limiter.enabled = False
            
            with TestClient(app) as test_client:
                yield test_client


@pytest.fixture
def sample_messages():
    """Provide sample message data for tests."""
    return SAMPLE_MESSAGES


@pytest.fixture
def sample_hashtags():
    """Provide sample hashtag data for tests."""
    return SAMPLE_HASHTAGS
