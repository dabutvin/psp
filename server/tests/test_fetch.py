"""
Tests for the fetcher logic in sync/fetch.py and sync/client.py.

Tests cover:
1. Client convenience functions (fetch_new_messages, fetch_messages_page)
2. The main fetch loop (stops on existing messages, respects max_messages, handles rate limits)
3. Message insertion helper (_insert_messages)
"""

from datetime import datetime, timezone
from unittest.mock import MagicMock, patch, call

import pytest

from core.models import GroupsIOMessage, GroupsIOResponse, Message, Hashtag, Attachment
from sync.client import RateLimitError


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_gio_message(id: int, subject: str = "Test", **kwargs) -> GroupsIOMessage:
    """Create a GroupsIOMessage for testing."""
    return GroupsIOMessage(
        id=id,
        topic_id=kwargs.get("topic_id", id),
        group_id=kwargs.get("group_id", 100),
        created=kwargs.get("created", datetime(2026, 1, 15, tzinfo=timezone.utc)),
        subject=subject,
        snippet=kwargs.get("snippet", subject[:40]),
        body=kwargs.get("body", f"Body for {subject}"),
        name=kwargs.get("name", "Test User"),
        msg_num=kwargs.get("msg_num", id),
        hashtags=kwargs.get("hashtags"),
        attachments=kwargs.get("attachments"),
    )


def _make_response(messages: list[GroupsIOMessage], has_more: bool = False, next_page_token: int | None = None) -> GroupsIOResponse:
    return GroupsIOResponse(
        total_count=len(messages),
        has_more=has_more,
        next_page_token=next_page_token,
        data=messages,
    )


# ---------------------------------------------------------------------------
# Tests for sync/client.py convenience functions
# ---------------------------------------------------------------------------

class TestClientFetchNewMessages:
    """Tests for sync.client.fetch_new_messages (convenience wrapper)."""

    @patch("sync.client.GroupsIOClient")
    def test_returns_message_objects(self, MockClient):
        """Should convert GroupsIOMessages to internal Message objects."""
        from sync.client import fetch_new_messages as client_fetch

        mock_client = MockClient.return_value
        mock_client.get_messages.return_value = _make_response([
            _make_gio_message(1, "Chair for sale $50"),
            _make_gio_message(2, "ISO: Stroller"),
        ])

        messages = client_fetch(client=mock_client, limit=10)

        assert len(messages) == 2
        assert all(isinstance(m, Message) for m in messages)
        assert messages[0].id == 1
        assert messages[1].id == 2

    @patch("sync.client.GroupsIOClient")
    def test_passes_limit_and_sort(self, MockClient):
        """Should call get_messages with correct params."""
        from sync.client import fetch_new_messages as client_fetch

        mock_client = MockClient.return_value
        mock_client.get_messages.return_value = _make_response([])

        client_fetch(client=mock_client, limit=25)

        mock_client.get_messages.assert_called_once_with(limit=25, sort_dir="desc")

    @patch("sync.client.GroupsIOClient")
    def test_empty_response(self, MockClient):
        """Should return empty list when no messages."""
        from sync.client import fetch_new_messages as client_fetch

        mock_client = MockClient.return_value
        mock_client.get_messages.return_value = _make_response([])

        messages = client_fetch(client=mock_client)
        assert messages == []


class TestClientFetchMessagesPage:
    """Tests for sync.client.fetch_messages_page."""

    @patch("sync.client.GroupsIOClient")
    def test_returns_messages_and_pagination(self, MockClient):
        """Should return (messages, next_page_token, has_more) tuple."""
        from sync.client import fetch_messages_page

        mock_client = MockClient.return_value
        mock_client.get_messages.return_value = _make_response(
            [_make_gio_message(10), _make_gio_message(11)],
            has_more=True,
            next_page_token=12,
        )

        messages, next_token, has_more = fetch_messages_page(client=mock_client, page_token=5)

        assert len(messages) == 2
        assert next_token == 12
        assert has_more is True

    @patch("sync.client.GroupsIOClient")
    def test_last_page(self, MockClient):
        """Should indicate no more pages."""
        from sync.client import fetch_messages_page

        mock_client = MockClient.return_value
        mock_client.get_messages.return_value = _make_response(
            [_make_gio_message(99)],
            has_more=False,
            next_page_token=None,
        )

        messages, next_token, has_more = fetch_messages_page(client=mock_client)

        assert len(messages) == 1
        assert next_token is None
        assert has_more is False


# ---------------------------------------------------------------------------
# Tests for sync/fetch.py main fetch loop
# ---------------------------------------------------------------------------

class TestFetchNewMessages:
    """Tests for sync.fetch.fetch_new_messages (the main DB-writing fetcher)."""

    def _mock_cursor(self, existing_ids: set[int] | None = None):
        """Create a mock psycopg2 cursor that returns existing_ids on SELECT."""
        cur = MagicMock()
        if existing_ids:
            cur.fetchall.return_value = [(id,) for id in existing_ids]
        else:
            cur.fetchall.return_value = []
        return cur

    def _mock_conn(self, cursor):
        """Create a mock psycopg2 connection wrapping a cursor."""
        conn = MagicMock()
        conn.__enter__ = MagicMock(return_value=conn)
        conn.__exit__ = MagicMock(return_value=False)
        conn.cursor.return_value.__enter__ = MagicMock(return_value=cursor)
        conn.cursor.return_value.__exit__ = MagicMock(return_value=False)
        return conn

    @patch("sync.fetch.execute_values")
    @patch("sync.fetch.psycopg2.connect")
    @patch("sync.fetch.GroupsIOClient")
    @patch("sync.fetch.get_db_url", return_value="postgresql://test")
    def test_inserts_new_messages(self, mock_db_url, MockClient, mock_connect, mock_exec):
        """Should insert messages that don't exist in the DB."""
        from sync.fetch import fetch_new_messages

        # Client returns 2 messages
        mock_client = MockClient.return_value
        mock_client.get_messages.return_value = _make_response(
            [_make_gio_message(1, "New post"), _make_gio_message(2, "Another new post")],
            has_more=False,
        )

        # DB has no existing messages
        cur = self._mock_cursor(existing_ids=set())
        mock_connect.return_value = self._mock_conn(cur)

        result = fetch_new_messages(batch_size=100, max_messages=1000)

        assert result == 2
        # execute_values should have been called for message inserts
        assert mock_exec.call_count >= 1

    @patch("sync.fetch.execute_values")
    @patch("sync.fetch.psycopg2.connect")
    @patch("sync.fetch.GroupsIOClient")
    @patch("sync.fetch.get_db_url", return_value="postgresql://test")
    def test_stops_when_existing_found(self, mock_db_url, MockClient, mock_connect, mock_exec):
        """Should stop fetching when it finds messages already in the DB."""
        from sync.fetch import fetch_new_messages

        mock_client = MockClient.return_value
        mock_client.get_messages.return_value = _make_response(
            [_make_gio_message(3, "New"), _make_gio_message(2, "Existing"), _make_gio_message(1, "Also existing")],
            has_more=True,
            next_page_token=100,
        )

        # DB already has messages 1 and 2
        cur = self._mock_cursor(existing_ids={1, 2})
        mock_connect.return_value = self._mock_conn(cur)

        result = fetch_new_messages()

        # Only message 3 is new
        assert result == 1
        # Should NOT fetch a second page because existing messages were found
        assert mock_client.get_messages.call_count == 1

    @patch("sync.fetch.psycopg2.connect")
    @patch("sync.fetch.GroupsIOClient")
    @patch("sync.fetch.get_db_url", return_value="postgresql://test")
    def test_dry_run_does_not_insert(self, mock_db_url, MockClient, mock_connect):
        """Dry run should count messages but not insert or commit."""
        from sync.fetch import fetch_new_messages

        mock_client = MockClient.return_value
        mock_client.get_messages.return_value = _make_response(
            [_make_gio_message(1, "Test")],
            has_more=False,
        )

        cur = self._mock_cursor(existing_ids=set())
        conn = self._mock_conn(cur)
        mock_connect.return_value = conn

        result = fetch_new_messages(dry_run=True)

        assert result == 1
        # commit should not have been called
        conn.commit.assert_not_called()

    @patch("sync.fetch.psycopg2.connect")
    @patch("sync.fetch.GroupsIOClient")
    @patch("sync.fetch.get_db_url", return_value="postgresql://test")
    def test_handles_rate_limit(self, mock_db_url, MockClient, mock_connect):
        """Should gracefully stop when rate limited."""
        from sync.fetch import fetch_new_messages

        mock_client = MockClient.return_value
        mock_client.get_messages.side_effect = RateLimitError(retry_after=60)

        cur = self._mock_cursor()
        mock_connect.return_value = self._mock_conn(cur)

        result = fetch_new_messages()

        assert result == 0

    @patch("sync.fetch.execute_values")
    @patch("sync.fetch.psycopg2.connect")
    @patch("sync.fetch.GroupsIOClient")
    @patch("sync.fetch.get_db_url", return_value="postgresql://test")
    def test_respects_max_messages(self, mock_db_url, MockClient, mock_connect, mock_exec):
        """Should stop after fetching max_messages."""
        from sync.fetch import fetch_new_messages

        # First call returns 5 messages, has_more=True
        # Second call would exceed max_messages=5 so loop should stop
        mock_client = MockClient.return_value
        mock_client.get_messages.return_value = _make_response(
            [_make_gio_message(i) for i in range(1, 6)],
            has_more=True,
            next_page_token=100,
        )

        cur = self._mock_cursor(existing_ids=set())
        mock_connect.return_value = self._mock_conn(cur)

        result = fetch_new_messages(batch_size=5, max_messages=5)

        assert result == 5
        # Should only call get_messages once since we hit max_messages
        assert mock_client.get_messages.call_count == 1

    @patch("sync.fetch.psycopg2.connect")
    @patch("sync.fetch.GroupsIOClient")
    @patch("sync.fetch.get_db_url", return_value="postgresql://test")
    def test_empty_response_stops(self, mock_db_url, MockClient, mock_connect):
        """Should stop when API returns no messages."""
        from sync.fetch import fetch_new_messages

        mock_client = MockClient.return_value
        mock_client.get_messages.return_value = _make_response([])

        cur = self._mock_cursor()
        mock_connect.return_value = self._mock_conn(cur)

        result = fetch_new_messages()

        assert result == 0


# ---------------------------------------------------------------------------
# Tests for GroupsIOMessage.to_message conversion
# ---------------------------------------------------------------------------

class TestGroupsIOMessageConversion:
    """Tests for GroupsIOMessage.to_message()."""

    def test_basic_conversion(self):
        """Should convert fields correctly."""
        gio = _make_gio_message(42, "For Sale: Desk $100", name="Alice <alice@example.com>")
        msg = gio.to_message()

        assert msg.id == 42
        assert msg.subject == "For Sale: Desk $100"
        assert msg.sender_email == "alice@example.com"
        assert isinstance(msg, Message)

    def test_hashtags_converted(self):
        """Should convert hashtag dicts to Hashtag models."""
        gio = _make_gio_message(
            1, "Tagged post",
            hashtags=[{"name": "ForSale", "color": "#4CAF50"}, {"name": "furniture"}],
        )
        msg = gio.to_message()

        assert len(msg.hashtags) == 2
        assert all(isinstance(h, Hashtag) for h in msg.hashtags)
        assert msg.hashtags[0].name == "ForSale"
        assert msg.hashtags[0].color_hex == "#4CAF50"
        assert msg.hashtags[1].name == "furniture"
        assert msg.hashtags[1].color_hex is None

    def test_attachments_converted(self):
        """Should convert attachment dicts to Attachment models."""
        gio = _make_gio_message(
            1, "With photo",
            attachments=[{
                "download_url": "https://example.com/photo.jpg",
                "image_thumbnail_url": "https://example.com/thumb.jpg",
                "filename": "photo.jpg",
                "media_type": "image/jpeg",
            }],
        )
        msg = gio.to_message()

        assert len(msg.attachments) == 1
        att = msg.attachments[0]
        assert isinstance(att, Attachment)
        assert att.download_url == "https://example.com/photo.jpg"
        assert att.thumbnail_url == "https://example.com/thumb.jpg"
        assert att.filename == "photo.jpg"
        assert att.attachment_index == 0

    def test_null_hashtags_and_attachments(self):
        """Should handle null hashtags/attachments from API (returns None, not [])."""
        gio = _make_gio_message(1, "Plain post", hashtags=None, attachments=None)
        msg = gio.to_message()

        assert msg.hashtags == []
        assert msg.attachments == []
