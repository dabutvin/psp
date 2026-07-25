"""
Tests for the deep link endpoints.

Verifies:
1. The association file iOS fetches is valid JSON with the app ID and path
2. Shared post links render a page with the post details and Open Graph tags
3. Unknown or malformed post ids fail gracefully
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


class TestSharedPostPage:
    """Tests for GET /p/{message_id}."""

    def test_returns_html(self, client):
        response = client.get("/p/1001")

        assert response.status_code == 200
        assert response.headers["content-type"].startswith("text/html")

    def test_includes_post_details(self, client):
        response = client.get("/p/1001")

        assert "For Sale: Vintage Chair" in response.text
        assert "Alice Smith" in response.text
        assert "$50" in response.text

    def test_includes_open_graph_tags(self, client):
        """Link previews in iMessage and Slack read these."""
        response = client.get("/p/1001")

        assert 'property="og:title"' in response.text
        assert 'property="og:description"' in response.text

    def test_preview_title_does_not_repeat_price(self, client):
        """The sample subject already ends in $50."""
        response = client.get("/p/1001")

        assert '<meta property="og:title" content="For Sale: Vintage Chair $50">' in response.text

    def test_preview_title_adds_missing_price(self, client, mock_db):
        mock_db.messages[0]["subject"] = "For Sale: Vintage Chair"
        mock_db.messages[0]["body"] = "Asking $50, pick up in Park Slope."

        response = client.get("/p/1001")

        assert '<meta property="og:title" content="For Sale: Vintage Chair - Asking $50">' in response.text

    def test_links_to_groups_io(self, client):
        """The fallback for recipients without the app."""
        response = client.get("/p/1001")

        assert "https://groups.parkslopeparents.com/g/Classifieds/message/1" in response.text

    def test_strips_markup_from_post_content(self, client, mock_db):
        """Subjects come from email, so they must not be able to inject markup."""
        mock_db.messages[0]["subject"] = 'FS: <script>alert("x")</script> chair'

        response = client.get("/p/1001")

        assert "<script>" not in response.text

    def test_escapes_special_characters(self, client, mock_db):
        mock_db.messages[0]["subject"] = 'FS: "Chair" & table'

        response = client.get("/p/1001")

        assert "&quot;Chair&quot; &amp; table" in response.text

    def test_unknown_post_returns_404_page(self, client):
        response = client.get("/p/999999")

        assert response.status_code == 404
        assert response.headers["content-type"].startswith("text/html")
        assert "Post not found" in response.text

    def test_non_numeric_post_id_returns_422(self, client):
        response = client.get("/p/not-a-number")

        assert response.status_code == 422
