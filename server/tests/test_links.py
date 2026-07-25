"""
Tests for the deep link endpoints.

Verifies:
1. The association file iOS fetches is valid JSON with the app ID and path
2. Shared post links publish nothing about the post
"""


class TestAppSiteAssociation:
    """Tests for GET /.well-known/apple-app-site-association."""

    def test_returns_json(self, client):
        response = client.get("/.well-known/apple-app-site-association")

        assert response.status_code == 200
        assert response.headers["content-type"].startswith("application/json")

    def test_declares_app_and_shared_post_path(self, client):
        response = client.get("/.well-known/apple-app-site-association")
        details = response.json()["applinks"]["details"]

        assert details[0]["appIDs"] == ["K25Q76L89U.com.psp.classifieds"]
        assert details[0]["components"][0]["/"] == "/p/*"

    def test_legacy_location_matches(self, client):
        """iOS 12 and earlier look for the file at the domain root."""
        well_known = client.get("/.well-known/apple-app-site-association")
        legacy = client.get("/apple-app-site-association")

        assert legacy.status_code == 200
        assert legacy.json() == well_known.json()


class TestSharedPostLink:
    """Tests for GET /p/{message_id}."""

    def test_returns_html(self, client):
        response = client.get("/p/1001")

        assert response.status_code == 200
        assert response.headers["content-type"].startswith("text/html")

    def test_publishes_no_post_content(self, client, sample_messages):
        """Classifieds data must never reach the web."""
        message = sample_messages[0]
        response = client.get(f"/p/{message['id']}")

        assert message["subject"] not in response.text
        assert message["snippet"] not in response.text
        assert message["body"] not in response.text
        assert message["name"] not in response.text
        assert "groups.parkslopeparents.com" not in response.text

    def test_identical_for_every_id(self, client):
        """The page reveals nothing, including whether a post exists."""
        known = client.get("/p/1001")
        unknown = client.get("/p/999999")

        assert unknown.status_code == known.status_code
        assert unknown.text == known.text

    def test_asks_search_engines_not_to_index(self, client):
        response = client.get("/p/1001")

        assert response.headers["X-Robots-Tag"] == "noindex, nofollow"

    def test_non_numeric_post_id_returns_422(self, client):
        response = client.get("/p/not-a-number")

        assert response.status_code == 422
