"""
Groups.io API client for PSP server.
Handles communication with the groups.io API.
"""

import logging
import time
from typing import Literal

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from config import get_settings
from models import GroupsIOResponse, Message

logger = logging.getLogger(__name__)


class RateLimitError(Exception):
    """Raised when rate limited by the API."""

    def __init__(self, retry_after: int = 60):
        self.retry_after = retry_after
        super().__init__(f"Rate limited. Retry after {retry_after} seconds.")


class APIError(Exception):
    """Generic API error."""

    def __init__(self, status_code: int, message: str):
        self.status_code = status_code
        super().__init__(f"API error {status_code}: {message}")


class GroupsIOClient:
    """
    Client for the groups.io API.

    Usage:
        client = GroupsIOClient()
        messages = client.get_messages(limit=20)
    """

    def __init__(
        self,
        api_token: str | None = None,
        group_id: int | None = None,
        base_url: str | None = None,
    ):
        settings = get_settings()
        self.api_token = api_token or settings.groups_io_api_token
        self.group_id = group_id or settings.groups_io_group_id
        self.base_url = base_url or settings.groups_io_base_url

        # Set up session with retries
        self.session = requests.Session()
        retries = Retry(
            total=3,
            backoff_factor=1,
            status_forcelist=[500, 502, 503, 504],
            allowed_methods=["GET"],
        )
        adapter = HTTPAdapter(max_retries=retries)
        self.session.mount("https://", adapter)
        self.session.mount("http://", adapter)

        # Set default headers
        self.session.headers.update(
            {
                "Authorization": f"Bearer {self.api_token}",
                "Accept": "application/json",
            }
        )

    def get_messages(
        self,
        limit: int = 100,
        page_token: int | None = None,
        sort_dir: Literal["asc", "desc"] = "desc",
        sort_field: str = "id",
    ) -> GroupsIOResponse:
        """
        Fetch messages from the groups.io API.

        Args:
            limit: Number of messages to fetch (max 100)
            page_token: Pagination token from previous response
            sort_dir: Sort direction - "desc" for newest first, "asc" for oldest first
            sort_field: Field to sort by (default: "id")

        Returns:
            GroupsIOResponse with messages and pagination info
        """
        params = {
            "group_id": self.group_id,
            "limit": min(limit, 100),  # API max is 100
            "sort_dir": sort_dir,
            "sort_field": sort_field,
        }

        if page_token is not None:
            params["page_token"] = page_token

        url = f"{self.base_url}/getmessages"
        logger.debug(f"Fetching messages: {url} params={params}")

        response = self._make_request(url, params)
        return GroupsIOResponse.model_validate(response)

    def get_message(self, message_id: int) -> Message | None:
        """
        Fetch a single message by ID.

        Args:
            message_id: The message ID to fetch

        Returns:
            Message object or None if not found
        """
        # Note: groups.io may not have a single-message endpoint
        # This might need to be implemented differently
        url = f"{self.base_url}/getmessage"
        params = {"message_id": message_id}

        try:
            response = self._make_request(url, params)
            if response:
                from models import GroupsIOMessage

                msg = GroupsIOMessage.model_validate(response)
                return msg.to_message()
        except APIError as e:
            if e.status_code == 404:
                return None
            raise

        return None

    def _make_request(self, url: str, params: dict) -> dict:
        """
        Make an authenticated request to the API.

        Handles rate limiting and errors.
        """
        try:
            response = self.session.get(url, params=params, timeout=30)

            # Handle rate limiting
            if response.status_code == 429:
                retry_after = int(response.headers.get("Retry-After", 60))
                raise RateLimitError(retry_after)

            # Handle other errors
            if response.status_code >= 400:
                raise APIError(response.status_code, response.text)

            return response.json()

        except requests.RequestException as e:
            logger.error(f"Request failed: {e}")
            raise


# Convenience functions


def fetch_new_messages(
    client: GroupsIOClient | None = None,
    limit: int = 100,
) -> list[Message]:
    """
    Fetch newest messages (for polling).

    Args:
        client: Optional client instance (creates new if not provided)
        limit: Number of messages to fetch

    Returns:
        List of Message objects, newest first
    """
    if client is None:
        client = GroupsIOClient()

    response = client.get_messages(limit=limit, sort_dir="desc")
    return [msg.to_message() for msg in response.data]


def fetch_messages_page(
    client: GroupsIOClient | None = None,
    page_token: int | None = None,
    limit: int = 100,
    sort_dir: Literal["asc", "desc"] = "asc",
) -> tuple[list[Message], int | None, bool]:
    """
    Fetch a page of messages (for backfill).

    Args:
        client: Optional client instance
        page_token: Pagination token
        limit: Number of messages to fetch
        sort_dir: Sort direction

    Returns:
        Tuple of (messages, next_page_token, has_more)
    """
    if client is None:
        client = GroupsIOClient()

    response = client.get_messages(
        limit=limit,
        page_token=page_token,
        sort_dir=sort_dir,
    )

    messages = [msg.to_message() for msg in response.data]
    return messages, response.next_page_token, response.has_more


# Test function
def test_connection() -> bool:
    """
    Test API connectivity with a single request.

    Returns:
        True if successful, False otherwise
    """
    try:
        client = GroupsIOClient()
        response = client.get_messages(limit=1)
        print(f"✓ Connected successfully!")
        print(f"  Total messages in group: {response.total_count:,}")
        if response.data:
            msg = response.data[0]
            print(f"  Latest message: {msg.subject[:50]}..." if msg.subject else "")
        return True
    except Exception as e:
        print(f"✗ Connection failed: {e}")
        return False


if __name__ == "__main__":
    # Run connectivity test when executed directly
    logging.basicConfig(level=logging.DEBUG)
    test_connection()
