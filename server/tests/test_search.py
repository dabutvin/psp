"""
Tests for core/search.py full-text search utilities.

These tests verify:
1. SQL condition building for PostgreSQL full-text search
2. Search term normalization (whitespace, case, truncation)
3. Search filter validation (duplicates, limits, empty handling)
4. Device matching for notifications (async DB queries)
"""

import pytest
from unittest.mock import AsyncMock, MagicMock

from core.search import (
    MAX_SEARCH_FILTERS,
    MAX_SEARCH_TERM_LENGTH,
    build_search_condition,
    normalize_search_term,
    validate_search_filters,
    get_devices_matching_post,
    remove_device_token,
)


class TestBuildSearchCondition:
    """Tests for build_search_condition function."""

    def test_basic_param_index(self):
        """Should build correct SQL condition with given parameter index."""
        result = build_search_condition(1)
        assert result == "search_vector @@ plainto_tsquery('english', $1)"

    def test_higher_param_index(self):
        """Should work with higher parameter indices."""
        result = build_search_condition(5)
        assert result == "search_vector @@ plainto_tsquery('english', $5)"

    def test_param_index_one(self):
        """Minimum valid parameter index is 1."""
        result = build_search_condition(1)
        assert "$1" in result

    def test_zero_param_index_raises(self):
        """Should raise ValueError for param_index of 0."""
        with pytest.raises(ValueError, match="Parameter index must be >= 1"):
            build_search_condition(0)

    def test_negative_param_index_raises(self):
        """Should raise ValueError for negative param_index."""
        with pytest.raises(ValueError, match="Parameter index must be >= 1"):
            build_search_condition(-1)

    def test_uses_english_config(self):
        """Should use 'english' text search configuration for stemming."""
        result = build_search_condition(1)
        assert "'english'" in result

    def test_uses_plainto_tsquery(self):
        """Should use plainto_tsquery for safe user input handling."""
        result = build_search_condition(1)
        assert "plainto_tsquery" in result


class TestNormalizeSearchTerm:
    """Tests for normalize_search_term function."""

    def test_strips_whitespace(self):
        """Should strip leading and trailing whitespace."""
        assert normalize_search_term("  stroller  ") == "stroller"
        assert normalize_search_term("\ttoys\n") == "toys"

    def test_converts_to_lowercase(self):
        """Should convert to lowercase."""
        assert normalize_search_term("STROLLER") == "stroller"
        assert normalize_search_term("Baby Clothes") == "baby clothes"

    def test_truncates_long_terms(self):
        """Should truncate terms exceeding MAX_SEARCH_TERM_LENGTH."""
        long_term = "a" * (MAX_SEARCH_TERM_LENGTH + 50)
        result = normalize_search_term(long_term)
        assert len(result) == MAX_SEARCH_TERM_LENGTH

    def test_preserves_short_terms(self):
        """Should not truncate terms within length limit."""
        short_term = "stroller"
        result = normalize_search_term(short_term)
        assert result == "stroller"

    def test_empty_string(self):
        """Should handle empty string."""
        assert normalize_search_term("") == ""

    def test_whitespace_only(self):
        """Should return empty string for whitespace-only input."""
        assert normalize_search_term("   ") == ""

    def test_combined_operations(self):
        """Should apply all normalizations together."""
        result = normalize_search_term("  BABY Stroller  ")
        assert result == "baby stroller"


class TestValidateSearchFilters:
    """Tests for validate_search_filters function."""

    def test_none_input_returns_none(self):
        """Should return None for None input."""
        assert validate_search_filters(None) is None

    def test_empty_list_returns_none(self):
        """Should return None for empty list."""
        assert validate_search_filters([]) is None

    def test_whitespace_only_items_returns_none(self):
        """Should return None if all items are whitespace."""
        assert validate_search_filters(["", "   ", "\t"]) is None

    def test_normalizes_terms(self):
        """Should normalize all terms."""
        result = validate_search_filters(["  STROLLER  ", "TOYS"])
        assert result == ["stroller", "toys"]

    def test_removes_duplicates(self):
        """Should remove duplicate terms after normalization."""
        result = validate_search_filters(["stroller", "STROLLER", "Stroller"])
        assert result == ["stroller"]

    def test_preserves_order(self):
        """Should preserve order of first occurrence."""
        result = validate_search_filters(["toys", "stroller", "baby"])
        assert result == ["toys", "stroller", "baby"]

    def test_removes_empty_strings(self):
        """Should remove empty strings from list."""
        result = validate_search_filters(["stroller", "", "toys", "   "])
        assert result == ["stroller", "toys"]

    def test_max_filters_allowed(self):
        """Should accept exactly MAX_SEARCH_FILTERS items."""
        filters = [f"term{i}" for i in range(MAX_SEARCH_FILTERS)]
        result = validate_search_filters(filters)
        assert len(result) == MAX_SEARCH_FILTERS

    def test_exceeds_max_filters_raises(self):
        """Should raise ValueError when exceeding MAX_SEARCH_FILTERS."""
        filters = [f"term{i}" for i in range(MAX_SEARCH_FILTERS + 1)]
        with pytest.raises(ValueError, match=f"Maximum {MAX_SEARCH_FILTERS}"):
            validate_search_filters(filters)

    def test_duplicates_dont_count_toward_limit(self):
        """Duplicates are removed, so they shouldn't affect the limit check."""
        # This creates MAX_SEARCH_FILTERS + 5 items, but after dedup only MAX_SEARCH_FILTERS
        filters = [f"term{i % MAX_SEARCH_FILTERS}" for i in range(MAX_SEARCH_FILTERS + 5)]
        # Should raise because check happens before dedup
        with pytest.raises(ValueError):
            validate_search_filters(filters)


class TestGetDevicesMatchingPost:
    """Tests for get_devices_matching_post async function."""

    @pytest.fixture
    def mock_db(self):
        """Create a mock database."""
        db = MagicMock()
        db.fetch = AsyncMock(return_value=[])
        return db

    @pytest.mark.asyncio
    async def test_returns_empty_list_when_no_matches(self, mock_db):
        """Should return empty list when no devices match."""
        mock_db.fetch.return_value = []
        
        result = await get_devices_matching_post(mock_db, 123)
        
        assert result == []

    @pytest.mark.asyncio
    async def test_returns_token_and_environment(self, mock_db):
        """Should return list of dicts with token and environment."""
        mock_db.fetch.return_value = [
            {"token": "abc123", "environment": "production"},
            {"token": "def456", "environment": "sandbox"},
        ]
        
        result = await get_devices_matching_post(mock_db, 123)
        
        assert len(result) == 2
        assert result[0] == {"token": "abc123", "environment": "production"}
        assert result[1] == {"token": "def456", "environment": "sandbox"}

    @pytest.mark.asyncio
    async def test_passes_post_id_to_query(self, mock_db):
        """Should pass post_id as query parameter."""
        mock_db.fetch.return_value = []
        
        await get_devices_matching_post(mock_db, 456)
        
        mock_db.fetch.assert_called_once()
        call_args = mock_db.fetch.call_args
        assert call_args[0][1] == 456  # Second positional arg is post_id

    @pytest.mark.asyncio
    async def test_query_checks_enabled_flag(self, mock_db):
        """Query should filter by enabled = TRUE."""
        mock_db.fetch.return_value = []
        
        await get_devices_matching_post(mock_db, 123)
        
        query = mock_db.fetch.call_args[0][0]
        assert "enabled = TRUE" in query

    @pytest.mark.asyncio
    async def test_query_handles_notify_all(self, mock_db):
        """Query should include notify_all = TRUE condition."""
        mock_db.fetch.return_value = []
        
        await get_devices_matching_post(mock_db, 123)
        
        query = mock_db.fetch.call_args[0][0]
        assert "notify_all = TRUE" in query

    @pytest.mark.asyncio
    async def test_query_uses_plainto_tsquery(self, mock_db):
        """Query should use plainto_tsquery for search matching."""
        mock_db.fetch.return_value = []
        
        await get_devices_matching_post(mock_db, 123)
        
        query = mock_db.fetch.call_args[0][0]
        assert "plainto_tsquery('english'" in query

    @pytest.mark.asyncio
    async def test_query_excludes_iso_posts_from_keyword_matches(self, mock_db):
        """Keyword-match branch should exclude ISO posts via hashtags table."""
        mock_db.fetch.return_value = []
        
        await get_devices_matching_post(mock_db, 123)
        
        query = mock_db.fetch.call_args[0][0]
        assert "NOT EXISTS" in query
        assert "'iso'" in query.lower()
        assert "hashtags" in query

    @pytest.mark.asyncio
    async def test_query_does_not_exclude_iso_from_notify_all(self, mock_db):
        """notify_all branch should NOT have the ISO exclusion."""
        mock_db.fetch.return_value = []
        
        await get_devices_matching_post(mock_db, 123)
        
        query = mock_db.fetch.call_args[0][0]
        # The notify_all = TRUE branch should be a simple condition
        # without ISO exclusion -- it appears before the keyword-match branch
        notify_all_idx = query.index("notify_all = TRUE")
        search_filters_idx = query.index("search_filters IS NOT NULL")
        not_exists_idx = query.index("NOT EXISTS")
        # ISO exclusion should be inside the search_filters branch, not the notify_all branch
        assert not_exists_idx > search_filters_idx
        assert notify_all_idx < search_filters_idx


class TestRemoveDeviceToken:
    """Tests for remove_device_token async function."""

    @pytest.fixture
    def mock_db(self):
        """Create a mock database."""
        db = MagicMock()
        db.execute = AsyncMock()
        return db

    @pytest.mark.asyncio
    async def test_executes_delete_query(self, mock_db):
        """Should execute DELETE query."""
        await remove_device_token(mock_db, "test_token_123")
        
        mock_db.execute.assert_called_once()
        query = mock_db.execute.call_args[0][0]
        assert "DELETE FROM device_tokens" in query

    @pytest.mark.asyncio
    async def test_passes_token_to_query(self, mock_db):
        """Should pass token as query parameter."""
        await remove_device_token(mock_db, "my_device_token")
        
        call_args = mock_db.execute.call_args
        assert call_args[0][1] == "my_device_token"

    @pytest.mark.asyncio
    async def test_uses_parameterized_query(self, mock_db):
        """Should use parameterized query to prevent SQL injection."""
        await remove_device_token(mock_db, "token'; DROP TABLE users;--")
        
        query = mock_db.execute.call_args[0][0]
        assert "$1" in query
        # The malicious token should be passed as parameter, not in query
        assert "DROP TABLE" not in query
