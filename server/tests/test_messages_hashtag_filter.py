"""
Tests for hashtag filtering in the messages endpoint.

These tests verify:
1. Single hashtag filtering returns only matching posts
2. Multiple hashtag filtering uses OR logic (posts matching ANY hashtag)
3. Hashtag filtering is case-insensitive
4. Empty/missing hashtag parameter returns all posts
5. Hashtag filtering works with pagination
"""

import pytest


class TestHashtagFiltering:
    """Tests for /api/v1/messages hashtag filtering."""
    
    def test_no_filter_returns_all_messages(self, client):
        """Without hashtag filter, all messages should be returned."""
        response = client.get("/api/v1/messages")
        
        assert response.status_code == 200
        data = response.json()
        assert "messages" in data
        assert len(data["messages"]) == 3  # All sample messages
    
    def test_single_hashtag_filter(self, client):
        """Single hashtag should filter to posts with that hashtag."""
        response = client.get("/api/v1/messages?hashtags=furniture")
        
        assert response.status_code == 200
        data = response.json()
        messages = data["messages"]
        
        # Should only return the furniture post (id=1001)
        assert len(messages) == 1
        assert messages[0]["id"] == 1001
        assert any(h["name"] == "furniture" for h in messages[0]["hashtags"])
    
    def test_single_hashtag_filter_case_insensitive(self, client):
        """Hashtag filtering should be case-insensitive."""
        # Test uppercase
        response_upper = client.get("/api/v1/messages?hashtags=FURNITURE")
        # Test mixed case
        response_mixed = client.get("/api/v1/messages?hashtags=Furniture")
        # Test lowercase
        response_lower = client.get("/api/v1/messages?hashtags=furniture")
        
        assert response_upper.status_code == 200
        assert response_mixed.status_code == 200
        assert response_lower.status_code == 200
        
        # All should return the same result
        assert len(response_upper.json()["messages"]) == 1
        assert len(response_mixed.json()["messages"]) == 1
        assert len(response_lower.json()["messages"]) == 1
        
        # All should be the furniture post
        assert response_upper.json()["messages"][0]["id"] == 1001
        assert response_mixed.json()["messages"][0]["id"] == 1001
        assert response_lower.json()["messages"][0]["id"] == 1001
    
    def test_multiple_hashtags_or_logic(self, client):
        """Multiple hashtags should use OR logic - return posts matching ANY."""
        response = client.get("/api/v1/messages?hashtags=furniture,toys")
        
        assert response.status_code == 200
        data = response.json()
        messages = data["messages"]
        
        # Should return both furniture (1001) and toys (1002) posts
        assert len(messages) == 2
        message_ids = {m["id"] for m in messages}
        assert message_ids == {1001, 1002}
    
    def test_multiple_hashtags_with_spaces(self, client):
        """Hashtags with spaces around commas should be handled correctly."""
        response = client.get("/api/v1/messages?hashtags=furniture, toys")
        
        assert response.status_code == 200
        data = response.json()
        messages = data["messages"]
        
        # Should still match both posts
        assert len(messages) == 2
    
    def test_hashtag_filter_no_matches(self, client):
        """Filtering by non-existent hashtag should return empty list."""
        response = client.get("/api/v1/messages?hashtags=nonexistent")
        
        assert response.status_code == 200
        data = response.json()
        
        assert data["messages"] == []
        assert data["has_more"] is False
    
    def test_shared_hashtag_returns_multiple_posts(self, client):
        """Filtering by a hashtag shared by multiple posts should return all."""
        # Both messages 1001 and 1003 have "parkslope" hashtag
        response = client.get("/api/v1/messages?hashtags=parkslope")
        
        assert response.status_code == 200
        data = response.json()
        messages = data["messages"]
        
        assert len(messages) == 2
        message_ids = {m["id"] for m in messages}
        assert message_ids == {1001, 1003}
    
    def test_category_hashtags(self, client):
        """Category hashtags (ForSale, ForFree, iso) should filter correctly."""
        # Test ForSale
        response_sale = client.get("/api/v1/messages?hashtags=ForSale")
        assert response_sale.status_code == 200
        assert len(response_sale.json()["messages"]) == 1
        assert response_sale.json()["messages"][0]["id"] == 1001
        
        # Test ForFree
        response_free = client.get("/api/v1/messages?hashtags=ForFree")
        assert response_free.status_code == 200
        assert len(response_free.json()["messages"]) == 1
        assert response_free.json()["messages"][0]["id"] == 1003
        
        # Test iso
        response_iso = client.get("/api/v1/messages?hashtags=iso")
        assert response_iso.status_code == 200
        assert len(response_iso.json()["messages"]) == 1
        assert response_iso.json()["messages"][0]["id"] == 1002
    
    def test_empty_hashtags_parameter(self, client):
        """Empty hashtags parameter should return all messages."""
        response = client.get("/api/v1/messages?hashtags=")
        
        assert response.status_code == 200
        data = response.json()
        
        # Empty string should be treated as no filter
        assert len(data["messages"]) == 3
    
    def test_response_includes_hashtags(self, client):
        """Response messages should include their hashtags."""
        response = client.get("/api/v1/messages?hashtags=furniture")
        
        assert response.status_code == 200
        message = response.json()["messages"][0]
        
        assert "hashtags" in message
        assert len(message["hashtags"]) > 0
        
        hashtag_names = [h["name"] for h in message["hashtags"]]
        assert "furniture" in hashtag_names
        assert "ForSale" in hashtag_names
    
    def test_response_structure(self, client):
        """Verify response structure matches expected format."""
        response = client.get("/api/v1/messages?hashtags=furniture")
        
        assert response.status_code == 200
        data = response.json()
        
        # Check top-level structure
        assert "messages" in data
        assert "has_more" in data
        assert "next_cursor" in data
        
        # Check message structure
        if data["messages"]:
            message = data["messages"][0]
            assert "id" in message
            assert "subject" in message
            assert "snippet" in message
            assert "created" in message
            assert "name" in message
            assert "hashtags" in message
            assert "attachments" in message
            assert "category" in message
            assert "is_reply" in message


class TestHashtagFilteringWithOtherFilters:
    """Tests for hashtag filtering combined with other filters."""
    
    def test_hashtags_with_limit(self, client):
        """Hashtag filtering should respect limit parameter."""
        response = client.get("/api/v1/messages?hashtags=parkslope&limit=1")
        
        assert response.status_code == 200
        data = response.json()
        
        # Should only return 1 message even though 2 match
        assert len(data["messages"]) == 1
        # has_more should indicate more results available
        assert data["has_more"] is True


class TestHashtagsEndpoint:
    """Tests for /api/v1/hashtags endpoint."""
    
    def test_list_hashtags(self, client):
        """Should return all unique hashtags with counts."""
        response = client.get("/api/v1/hashtags")
        
        assert response.status_code == 200
        data = response.json()
        
        assert "hashtags" in data
        assert "total_unique" in data
        assert data["total_unique"] > 0
        
        # Check hashtag structure
        if data["hashtags"]:
            hashtag = data["hashtags"][0]
            assert "name" in hashtag
            assert "count" in hashtag
    
    def test_hashtags_sorted_by_count(self, client):
        """Hashtags should be sorted by count descending."""
        response = client.get("/api/v1/hashtags")
        
        assert response.status_code == 200
        hashtags = response.json()["hashtags"]
        
        if len(hashtags) > 1:
            counts = [h["count"] for h in hashtags]
            assert counts == sorted(counts, reverse=True)
    
    def test_hashtag_counts_are_accurate(self, client):
        """Hashtag counts should reflect actual message counts."""
        response = client.get("/api/v1/hashtags")
        
        assert response.status_code == 200
        hashtags = {h["name"]: h["count"] for h in response.json()["hashtags"]}
        
        # parkslope appears in 2 messages (1001, 1003)
        assert hashtags.get("parkslope") == 2
        
        # furniture appears in 1 message (1001)
        assert hashtags.get("furniture") == 1
