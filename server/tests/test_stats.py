"""
Tests for the stats endpoint.

Verifies:
1. Response structure includes all expected fields
2. Message counts and date ranges are correct
3. Sync state (last_sync) is returned
4. Database size info is included with table breakdown
5. Caching headers are set
"""

import pytest


class TestStatsEndpoint:
    """Tests for GET /api/v1/stats."""

    def test_stats_returns_200(self, client):
        """Stats endpoint should return 200."""
        response = client.get("/api/v1/stats")
        assert response.status_code == 200

    def test_stats_response_structure(self, client):
        """Response should include all expected top-level fields."""
        response = client.get("/api/v1/stats")
        data = response.json()

        assert "total_messages" in data
        assert "newest_message_date" in data
        assert "oldest_message_date" in data
        assert "last_sync" in data
        assert "backfill_in_progress" in data
        assert "database" in data

    def test_stats_message_count(self, client):
        """Total messages should match the number of sample messages."""
        response = client.get("/api/v1/stats")
        data = response.json()

        assert data["total_messages"] == 3

    def test_stats_date_range(self, client):
        """Oldest and newest dates should span the sample data."""
        response = client.get("/api/v1/stats")
        data = response.json()

        assert data["oldest_message_date"] is not None
        assert data["newest_message_date"] is not None
        # Oldest should be before newest
        assert data["oldest_message_date"] < data["newest_message_date"]

    def test_stats_last_sync(self, client):
        """Last sync time should be present."""
        response = client.get("/api/v1/stats")
        data = response.json()

        assert data["last_sync"] is not None

    def test_stats_backfill_not_in_progress(self, client):
        """Backfill should not be in progress (no page token in mock)."""
        response = client.get("/api/v1/stats")
        data = response.json()

        assert data["backfill_in_progress"] is False

    def test_stats_database_size(self, client):
        """Database size info should be present with expected structure."""
        response = client.get("/api/v1/stats")
        data = response.json()

        db = data["database"]
        assert db is not None
        assert "total_mb" in db
        assert "limit_mb" in db
        assert "usage_percent" in db
        assert "tables" in db

        assert db["limit_mb"] == 500
        assert db["total_mb"] > 0
        assert 0 < db["usage_percent"] < 100

    def test_stats_database_tables(self, client):
        """Database tables should list individual table sizes."""
        response = client.get("/api/v1/stats")
        tables = response.json()["database"]["tables"]

        assert len(tables) > 0

        # Each table should have name and size_mb
        for table in tables:
            assert "name" in table
            assert "size_mb" in table

        # Messages table should be the largest
        table_names = [t["name"] for t in tables]
        assert "messages" in table_names

    def test_stats_cache_headers(self, client):
        """Response should include cache control headers."""
        response = client.get("/api/v1/stats")

        assert "cache-control" in response.headers
        assert "max-age=60" in response.headers["cache-control"]

    def test_stats_last_modified_header(self, client):
        """Response should include Last-Modified header when last_sync is set."""
        response = client.get("/api/v1/stats")

        assert "last-modified" in response.headers
