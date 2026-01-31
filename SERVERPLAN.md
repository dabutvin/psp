# Park Slope Parents Message Ingestion System

## Overview
A system to ingest messages from the groups.io API, store them in a database, keep up-to-date with new posts, and expose a read-only API for an iPhone app.

## Phase 1: Foundation & Connectivity

### 1.1 Project Setup
- [ ] Initialize Python project with virtual environment
- [ ] Create `requirements.txt` with dependencies:
  - `requests` - API calls
  - `psycopg2-binary` or `asyncpg` - PostgreSQL driver
  - `python-dotenv` - environment variable management
  - `fastapi` + `uvicorn` - read-only API server (Phase 5)
- [ ] Create `.env` file for credentials (gitignored):
  - `GROUPS_IO_API_TOKEN`
  - `GROUPS_IO_GROUP_ID`
  - `DATABASE_URL` (e.g. `postgresql://user:pass@localhost/psp`)
- [ ] Create basic config module

### 1.2 Database Schema
PostgreSQL for concurrent access (API + poller + backfill). Schema:

```sql
CREATE TABLE messages (
    id BIGINT PRIMARY KEY,               -- groups.io message id
    topic_id BIGINT,
    group_id INTEGER,
    created TIMESTAMPTZ,
    updated TIMESTAMPTZ,
    subject TEXT,
    body TEXT,
    snippet TEXT,
    name TEXT,                           -- sender display name
    sender_email TEXT,                   -- extracted email for reply-to
    msg_num INTEGER,
    is_reply BOOLEAN,
    is_plain_text BOOLEAN,
    reply_to TEXT,
    fetched_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_messages_created ON messages(created DESC);
CREATE INDEX idx_messages_topic_id ON messages(topic_id);
CREATE INDEX idx_messages_msg_num ON messages(msg_num);
CREATE INDEX idx_messages_id_created ON messages(id DESC, created DESC);  -- for cursor pagination

CREATE TABLE hashtags (
    id SERIAL PRIMARY KEY,
    message_id BIGINT REFERENCES messages(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    color_hex TEXT
);

CREATE INDEX idx_hashtags_name ON hashtags(name);
CREATE INDEX idx_hashtags_message_id ON hashtags(message_id);

CREATE TABLE attachments (
    id SERIAL PRIMARY KEY,
    message_id BIGINT REFERENCES messages(id) ON DELETE CASCADE,
    attachment_index INTEGER,            -- 0, 1, 2... within message
    download_url TEXT,
    thumbnail_url TEXT,
    filename TEXT,
    media_type TEXT                      -- e.g. "image/jpeg"
);

CREATE INDEX idx_attachments_message_id ON attachments(message_id);

CREATE TABLE sync_state (
    id INTEGER PRIMARY KEY DEFAULT 1,
    last_fetch_at TIMESTAMPTZ,
    newest_message_id BIGINT,
    oldest_message_id BIGINT,
    backfill_page_token BIGINT           -- for resumable backfill
);
```

### 1.3 API Client Module
- [ ] Create `api_client.py` with:
  - `get_messages(limit, page_token, sort_dir)` - basic fetch
  - Rate limiting / retry logic
  - Error handling
- [ ] Test connectivity with a single API call

## Phase 2: Fetch New Messages

### 2.1 Fetch Strategy
- Fetch new messages using `sort_dir=desc` (newest first)
- Stop when we see a message ID we already have
- Store `newest_message_id` in sync_state
- Run externally via cron/launchd (every 15-30 min)

### 2.2 Fetch Implementation
- [x] Create `fetch.py` module
- [x] Implement deduplication (skip messages already in DB)
- [x] Log fetch activity
- [x] CLI: `python cli.py fetch`

## Phase 3: Backfill (Historical Data)

### 3.1 Backfill Strategy
**IMPORTANT: Be gentle with the API!**
- ~704,790 messages total
- At 100 messages per request = ~7,048 API calls needed
- Plan: 1 request per 5-10 seconds = ~10-20 hours total
- **Newest first**: Start with recent messages so app is useful right away
- Make backfill **resumable** (save page_token to DB)
- Run in background, can stop/start anytime

### 3.2 Backfill Implementation
- [x] Create `backfill.py` module
- [x] Use `sort_dir=desc` to go newest→oldest (recent messages first!)
- [x] Track progress via `backfill_page_token` in sync_state
- [x] Configurable delay between requests (default: 5s)
- [x] CLI: `python cli.py backfill --delay=5`
- [x] Graceful shutdown on Ctrl+C (SIGINT/SIGTERM)
- [x] Status check: `python cli.py backfill --status`
- [x] Reset option: `python cli.py backfill --reset`

## Phase 4: Production Hardening

### 4.1 Scheduling
- [ ] Add scheduler (cron or APScheduler) for automatic polling
- [ ] Consider simple systemd service or similar

### 4.2 Observability
- [ ] Structured logging
- [ ] Simple stats: messages ingested, last poll time, etc.

### 4.3 Full-Text Search (PostgreSQL)
Use PostgreSQL's built-in full-text search:

```sql
-- Add tsvector column for search
ALTER TABLE messages ADD COLUMN search_vector tsvector;

-- Populate search vector
UPDATE messages SET search_vector = 
    to_tsvector('english', coalesce(subject, '') || ' ' || coalesce(body, ''));

-- Create GIN index for fast search
CREATE INDEX idx_messages_search ON messages USING GIN(search_vector);

-- Trigger to keep search_vector updated
CREATE OR REPLACE FUNCTION messages_search_trigger() RETURNS trigger AS $$
BEGIN
    NEW.search_vector := to_tsvector('english', coalesce(NEW.subject, '') || ' ' || coalesce(NEW.body, ''));
    RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER messages_search_update
    BEFORE INSERT OR UPDATE ON messages
    FOR EACH ROW EXECUTE FUNCTION messages_search_trigger();
```

Search query:
```sql
SELECT * FROM messages 
WHERE search_vector @@ plainto_tsquery('english', 'baby stroller')
ORDER BY ts_rank(search_vector, plainto_tsquery('english', 'baby stroller')) DESC;
```

## Phase 5: Read-Only API (iPhone App Backend)

### 5.1 API Framework
- [ ] Add FastAPI to requirements (lightweight, async, auto-generates OpenAPI docs)
- [ ] Create `server.py` - main API application
- [ ] Read-only endpoints only (no writes from clients)

### 5.2 API Endpoints

```
GET /api/v1/messages
  Query params:
    - limit (default: 20, max: 100)
    - cursor (pagination - message ID, fetch posts older than this)
    - since (ISO timestamp - messages after this date)
    - hashtag (filter by hashtag name: ForSale, ForFree, ISO)
    - search (full-text search query)
  Returns: {
    messages: [{
      id, subject, snippet, created, name, sender_email,
      hashtags: [{name, color_hex}],
      attachments: [{download_url, thumbnail_url, filename}],
      price,        // extracted, nullable
      category      // derived from hashtags
    }],
    has_more: bool,
    next_cursor: string   // ID of last message, use for next page
  }
  
  **Cursor Pagination (for infinite scroll)**:
  - Default sort: newest first (created DESC)
  - cursor = message ID of last item in current page
  - Query: WHERE id < cursor ORDER BY created DESC LIMIT 20
  - Stable during new inserts (unlike offset-based)
  
  Example flow:
    1. GET /messages?hashtag=ForSale&limit=20
       → returns messages, next_cursor="262078200"
    2. GET /messages?hashtag=ForSale&limit=20&cursor=262078200
       → returns older messages, next_cursor="262078150"
    3. ... repeat until has_more=false

GET /api/v1/messages/{id}
  Returns: single message with full body (for detail view)
  Includes: all fields above + full body text

GET /api/v1/topics/{topic_id}/messages
  Returns: all messages in a thread/topic (for conversation view)

GET /api/v1/hashtags
  Returns: list of hashtags with message counts
  Example: [{ name: "ForSale", color_hex: "#8ec2ee", count: 239261 }]

GET /api/v1/stats
  Returns: { total_messages, newest_message_date, last_sync }

```

### 5.3 iPhone App Considerations
- **Response format**: JSON, optimized for mobile (include snippets, avoid huge bodies in list views)
- **Pagination**: Cursor-based preferred (stable during new message inserts)
- **Caching headers**: ETags or Last-Modified for efficient polling
- **Compression**: gzip responses (FastAPI/uvicorn handle this)
- **CORS**: Configure if needed for any web clients

### 5.4 Derived Fields (computed on server)
Server extracts/computes these fields so clients don't need to parse:

- **price**: Extract from subject/body using regex
  ```python
  import re
  
  def extract_price(subject: str, body: str) -> str | None:
      """Extract first price found in subject or body."""
      text = f"{subject} {body}"
      # Match patterns: $40, $40.00, asking $50, $1,000
      patterns = [
          r'\$[\d,]+(?:\.\d{2})?',           # $40, $40.00, $1,000
          r'asking\s*\$?[\d,]+',              # asking $50, asking 50
          r'[\d,]+\s*(?:dollars|obo)',        # 50 dollars, 40 obo
      ]
      for pattern in patterns:
          match = re.search(pattern, text, re.IGNORECASE)
          if match:
              return match.group(0)
      return None
  ```

- **category**: Derive from hashtags (ForSale, ForFree, ISO)
- **sender_email**: Parse from `name` field if format is "Name <email@example.com>"
  ```python
  import re
  
  def extract_email(name: str) -> str | None:
      """Extract email from 'Display Name <email@example.com>' format."""
      match = re.search(r'<([^>]+@[^>]+)>', name)
      return match.group(1) if match else None
  ```

### 5.5 Image/Attachment Handling
**Approach**: Pass through original groups.io URLs. Client handles auth via WebView cookie sharing.

- API responses include original `download_url` and `thumbnail_url` from groups.io
- Example: `https://groups.parkslopeparents.com/g/Classifieds/attachment/725415/0/IMG_1286.jpg`
- iPhone app authenticates user via WebView login to groups.parkslopeparents.com
- Cookies shared with URLSession, images load directly
- No server proxy needed - reduces complexity and bandwidth

### 5.6 Deployment Options
- **Simple**: Run on a VPS (DigitalOcean, Linode) with uvicorn + nginx
- **Serverless**: Works well with managed Postgres (Supabase, Neon, RDS)
- **Container**: Dockerfile for easy deployment anywhere

### 5.7 Security
- [ ] Rate limiting (slowapi or nginx)
- [ ] Optional API key for app authentication
- [ ] No sensitive data exposed (emails already visible in source data)
- [ ] HTTPS only in production

---

## File Structure (Proposed)
```
psp/
├── .env                  # API_TOKEN, GROUP_ID (gitignored)
├── .gitignore
├── requirements.txt
├── config.py             # Load env vars, constants
├── db.py                 # Database connection, schema init
├── api_client.py         # groups.io API wrapper
├── models.py             # Data classes for messages
├── fetch.py              # Fetch new messages
├── backfill.py           # Historical backfill
├── cli.py                # Main entry point
├── server.py             # FastAPI read-only API
├── routers/
│   ├── messages.py       # /api/v1/messages endpoints
│   ├── topics.py         # /api/v1/topics endpoints
│   └── hashtags.py       # /api/v1/hashtags endpoints
└── alembic/              # Database migrations (optional)
```

---

## Next Steps (Immediate)
1. Set up project structure and dependencies
2. Implement database schema
3. Build API client with single test call
4. Implement basic polling loop
5. **Only after polling works:** begin careful backfill
6. **After data exists:** build read-only API for iPhone app

---

## API Reference (Quick)
```bash
# Get newest messages
curl "https://groups.io/api/v1/getmessages?group_id=8407&sort_dir=desc&limit=100" \
  -H "Authorization: Bearer $API_TOKEN"

# Paginate (backfill)
curl "https://groups.io/api/v1/getmessages?group_id=8407&sort_dir=asc&limit=100&page_token=100" \
  -H "Authorization: Bearer $API_TOKEN"
```

Response fields we care about:
- `total_count` - total messages in group
- `has_more` - more pages available
- `next_page_token` - cursor for next page
- `data[]` - array of message objects
