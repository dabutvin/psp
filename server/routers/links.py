"""
Deep link router.

Serves the Apple app-site-association file plus a placeholder for the URLs that
shared post links use. iOS hands those links to the app when the recipient has it
installed. When they don't, the link deliberately goes nowhere: no post content
is ever published to the web.

Endpoints:
- GET /.well-known/apple-app-site-association - Universal link association file
- GET /apple-app-site-association - Same file at the legacy location
- GET /p/{message_id} - Placeholder for a shared post link
"""

from fastapi import APIRouter
from fastapi.responses import HTMLResponse, JSONResponse

from core.config import get_ios_app_id

router = APIRouter()

# Path pattern the app is allowed to handle. Kept narrow so the rest of the API
# keeps working as a plain web service.
SHARED_POST_PATH = "/p/*"


def _association_response() -> JSONResponse:
    return JSONResponse(
        content={
            "applinks": {
                "details": [
                    {
                        "appIDs": [get_ios_app_id()],
                        "components": [
                            {"/": SHARED_POST_PATH, "comment": "Shared post links"}
                        ],
                    }
                ]
            }
        },
        media_type="application/json",
        headers={"Cache-Control": "public, max-age=3600"},
    )


@router.get("/.well-known/apple-app-site-association", include_in_schema=False)
async def apple_app_site_association():
    """
    The file iOS fetches to confirm this domain may open the app.

    Apple requires it over HTTPS as JSON with no redirects, which is why it sits
    at the domain root rather than under /api/v1.
    """
    return _association_response()


@router.get("/apple-app-site-association", include_in_schema=False)
async def apple_app_site_association_legacy():
    """Same association file, at the pre-iOS 13 location."""
    return _association_response()


# Deliberately static: it takes no id into account, reads nothing from the
# database, and says nothing about the post. Classifieds content stays inside the
# app, so a link without the app is a dead end rather than a public web page.
_PLACEHOLDER_PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>PSP Classifieds</title>
<style>
  :root { color-scheme: light dark; }
  body {
    font: -apple-system-body, 17px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    margin: 0 auto; padding: 48px 20px; max-width: 30rem; text-align: center;
  }
  p { color: #6b7280; }
</style>
</head>
<body>
<h1>PSP Classifieds</h1>
<p>This link opens in the PSP Classifieds app on iPhone. Posts are only available
in the app.</p>
</body>
</html>
"""


@router.get("/p/{message_id}", include_in_schema=False, response_class=HTMLResponse)
async def shared_post(message_id: int):
    """
    Placeholder for a shared post link.

    Recipients with the app installed never load this - iOS opens the app
    instead. The id is part of the URL only so the app can read it; nothing here
    varies by post.
    """
    return HTMLResponse(
        _PLACEHOLDER_PAGE,
        headers={
            "Cache-Control": "public, max-age=3600",
            "X-Robots-Tag": "noindex, nofollow",
        },
    )
