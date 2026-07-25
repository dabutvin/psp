"""
Deep link router.

Serves the Apple app-site-association file plus the web page that shared post
links point at. A link sent over iMessage opens the app when the recipient has
it installed, and falls back to this page when they don't.

Endpoints:
- GET /.well-known/apple-app-site-association - Universal link association file
- GET /apple-app-site-association - Same file at the legacy location
- GET /p/{message_id} - Landing page for a shared post
"""

import html
import re

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, JSONResponse
from slowapi import Limiter
from slowapi.util import get_remote_address

from core.config import get_ios_app_id
from core.database import get_database
from core.logging import get_logger
from core.models import extract_price

logger = get_logger(__name__)
limiter = Limiter(key_func=get_remote_address)

router = APIRouter()

CLASSIFIEDS_URL = "https://groups.parkslopeparents.com/g/Classifieds"
MESSAGE_URL = CLASSIFIEDS_URL + "/message/{msg_num}"

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


@router.get("/p/{message_id}", include_in_schema=False, response_class=HTMLResponse)
@limiter.limit("60/minute")
async def shared_post(request: Request, message_id: int):
    """
    Web fallback for a shared post link.

    Recipients with the app installed never see this - iOS hands the link to the
    app instead. Everyone else gets the post summary and a link to groups.io,
    and link previews (iMessage, Slack) read the Open Graph tags.
    """
    db = get_database()

    row = await db.fetchrow(
        """
        SELECT id, subject, snippet, body, name, msg_num
        FROM messages
        WHERE id = $1
        """,
        message_id,
    )

    if not row:
        logger.info(f"Shared post link for unknown message: {message_id}")
        return HTMLResponse(_render_not_found(), status_code=404)

    return HTMLResponse(
        _render_post(
            subject=row["subject"],
            snippet=row["snippet"] or row["body"],
            sender=row["name"],
            price=extract_price(row["subject"], row["body"]),
            msg_num=row["msg_num"],
        ),
        headers={"Cache-Control": "public, max-age=300"},
    )


def _plain_text(value: str | None, limit: int = 200) -> str:
    """Strip tags and collapse whitespace so a body is safe to show as a summary."""
    if not value:
        return ""

    text = re.sub(r"<[^>]+>", " ", value)
    text = html.unescape(text)
    text = re.sub(r"\s+", " ", text).strip()

    if len(text) > limit:
        text = text[:limit].rstrip() + "…"

    return text


_PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} - PSP Classifieds</title>
<meta property="og:site_name" content="PSP Classifieds">
<meta property="og:type" content="website">
<meta property="og:title" content="{og_title}">
<meta property="og:description" content="{description}">
<meta name="twitter:card" content="summary">
<style>
  :root {{ color-scheme: light dark; }}
  body {{
    font: -apple-system-body, 17px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    margin: 0 auto; padding: 32px 20px; max-width: 34rem;
  }}
  h1 {{ font-size: 1.5rem; line-height: 1.3; margin: 0 0 8px; }}
  .price {{ font-weight: 600; color: #1a7f37; margin: 0 0 8px; }}
  .meta {{ color: #6b7280; font-size: 0.95rem; margin: 0 0 20px; }}
  .body {{ margin: 0 0 28px; }}
  .cta {{
    display: inline-block; padding: 12px 20px; border-radius: 12px;
    background: #1a7f37; color: #fff; text-decoration: none; font-weight: 600;
  }}
  .note {{ color: #6b7280; font-size: 0.9rem; margin-top: 24px; }}
</style>
</head>
<body>
<h1>{title}</h1>
{price_block}
{meta_block}
<p class="body">{description}</p>
<a class="cta" href="{cta_url}">{cta_label}</a>
<p class="note">{note}</p>
</body>
</html>
"""


def _render_post(
    subject: str | None,
    snippet: str | None,
    sender: str | None,
    price: str | None,
    msg_num: int | None,
) -> str:
    plain_title = _plain_text(subject, limit=120) or "PSP Classifieds post"
    title = html.escape(plain_title)
    description = html.escape(_plain_text(snippet) or "A post from the Park Slope Parents classifieds.")

    # Subjects often already quote the price, so only add it when it's missing
    if price and price not in plain_title:
        og_title = f"{title} - {html.escape(price)}"
    else:
        og_title = title
    price_block = f'<p class="price">{html.escape(price)}</p>' if price else ""
    meta_block = f'<p class="meta">Posted by {html.escape(sender)}</p>' if sender else ""

    if msg_num:
        cta_url = MESSAGE_URL.format(msg_num=msg_num)
        cta_label = "View on groups.io"
    else:
        cta_url = CLASSIFIEDS_URL
        cta_label = "Browse the classifieds"

    return _PAGE.format(
        title=title,
        og_title=og_title,
        description=description,
        price_block=price_block,
        meta_block=meta_block,
        cta_url=cta_url,
        cta_label=cta_label,
        note="Have the PSP Classifieds app? This link opens the post right in it.",
    )


def _render_not_found() -> str:
    return _PAGE.format(
        title="Post not found",
        og_title="PSP Classifieds",
        description="This post is no longer available.",
        price_block="",
        meta_block="",
        cta_url=CLASSIFIEDS_URL,
        cta_label="Browse the classifieds",
        note="",
    )
