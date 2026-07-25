# PSP Server

Backend server for the Park Slope Parents Classifieds app. Ingests messages from groups.io and provides a read-only API.

## Deployment

### 1. Supabase for Postgres

### 2. Fly.io for app container

```
# deploy app
fly secrets set DATABASE_URL="postgresql://postgres:PASSWORD@db.xxxxx.supabase.co:5432/postgres"
fly secrets set GROUPS_IO_API_TOKEN=""
fly deploy

# deploy fetcher
fly secrets set -a psp-fetcher DATABASE_URL="postgresql://postgres:PASSWORD@db.xxxxx.supabase.co:5432/postgres"
fly secrets set -a psp-fetcher GROUPS_IO_API_TOKEN=""
fly deploy -c fly.fetcher.toml

# set schedule for the fetch
fly machines list -a psp-fetcher
fly machine update <MACHINE_ID> --schedule "hourly" -a psp-fetcher --yes

```


### 3. Logs

```
# API logs
fly logs -a psp-api

# Fetcher logs  
fly logs -a psp-fetcher

# Check fetcher status/schedule
fly machines list -a psp-fetcher



```

### 4. Troubleshooting

```
# Check stats
fly ssh console -a psp-api -C "uv run python cli.py stats"

# manual run commands
fly ssh console -C "uv run python cli.py init-db"
fly ssh console -C "uv run python cli.py backfill --delay=5 --max=1000"
fly ssh console -C "uv run python cli.py fetch"

# list machines
fly machines list
fly machines list -a psp-fetcher  

# ssh into container
flyctl ssh console
flyctl -a psp-fetcher ssh console

# change scale count
fly scale count 1
fly scale count 1 -a psp-fetcher
```

## Docker

### 1. Start the Database

```bash
docker compose up -d postgres
```

### 2. Start the API Server

```bash
export GROUPS_IO_API_TOKEN=your_token_here
docker compose up -d api
```

### 3. Run the Fetcher

Pulls new messages from groups.io and exits:

```bash
docker compose run fetcher
```


### 4. Run Backfill

Import historical messages (runs until complete or stopped):

```bash
docker compose run backfill
```

View progress:

```bash
docker logs -f psp-backfill
```

---

## Local Development Setup

1. **Install uv** (if you haven't already):
   ```bash
   curl -LsSf https://astral.sh/uv/install.sh | sh
   ```

2. **Install dependencies:**
   ```bash
   cd server
   uv sync
   ```

3. **Start PostgreSQL:**
   ```bash
   docker compose up -d postgres
   ```

4. **Configure environment:**
   ```bash
   cp env.example .env
   # Edit .env with your GROUPS_IO_API_TOKEN
   ```

5. **Initialize database:**
   ```bash
   uv run python cli.py init-db
   ```

6. **Test API connection:**
   ```bash
   uv run python cli.py test-api
   ```

7. **Start the server:**
   ```bash
   uv run python cli.py serve --reload
   ```

8. **Run unit tests:**
   ```bash
   uv run pytest tests/ -v
   ```

## CLI Commands

```bash
uv run python cli.py init-db              # Initialize database schema
uv run python cli.py migrate              # Run all pending database migrations
uv run python cli.py migrate --status     # Show migration status
uv run python cli.py test-api             # Test groups.io API connectivity
uv run python cli.py fetch                # Fetch new messages
uv run python cli.py backfill --delay=5   # Backfill historical data
uv run python cli.py serve --reload       # Start API server (dev mode)
uv run python cli.py stats                # Show system statistics
uv run python cli.py migrate-search       # Populate search vectors (legacy)
```

### Migrations

When deploying updates that include database schema changes, run migrations:

```bash
# Check what migrations are pending
uv run python cli.py migrate --status

# Run all pending migrations
uv run python cli.py migrate
```

On Fly.io:
```bash
fly ssh console -a psp-api -C "uv run python cli.py migrate"
```

To run the full schema initialization (safe to run on existing databases - uses `IF NOT EXISTS`):
```bash
fly ssh console -C "sh -c 'cd /app && /app/.venv/bin/python -m core.database'"
```

## Project Structure

```
server/
├── pyproject.toml      # Dependencies and project config
├── Dockerfile          # Container image definition
├── docker-compose.yml  # Multi-container orchestration
├── cli.py              # Command-line interface
├── server.py           # FastAPI server entry point
├── core/               # Core infrastructure
│   ├── config.py       # Configuration/settings
│   ├── database.py     # Database connection and schema
│   ├── logging.py      # Structured logging
│   ├── models.py       # Pydantic data models
│   ├── stats.py        # System statistics
│   └── migrations.py   # Database migrations
├── sync/               # Data synchronization
│   ├── client.py       # Groups.io API client
│   ├── fetch.py        # Fetch new messages
│   └── backfill.py     # Historical backfill
├── routers/            # API route handlers
│   ├── messages.py     # /api/v1/messages
│   ├── hashtags.py     # /api/v1/hashtags
│   ├── links.py        # Universal links: /.well-known/... and /p/{id}
│   └── stats.py        # /api/v1/stats
└── tests/              # Unit tests
    ├── conftest.py     # Pytest fixtures and mock database
    └── test_messages_hashtag_filter.py
```

## Shared Post Links

When someone shares a post from the iOS app, the link points here rather than at
groups.io, so that tapping it opens the app.

| Route | Purpose |
|-------|---------|
| `GET /.well-known/apple-app-site-association` | Tells iOS this domain may open the app for `/p/*`. Must stay at the domain root, be served as JSON, and never redirect. |
| `GET /apple-app-site-association` | Same file, for iOS 12 and earlier |
| `GET /p/{message_id}` | Web page for a shared post: title, price, sender, and a link to the message on groups.io |

iOS hands `/p/{id}` links straight to the app when the recipient has it
installed, so they only ever see the web page when they don't. Link previews in
iMessage and Slack read the Open Graph tags on that page.

The app ID in the association file defaults to the shipping app
(`K25Q76L89U.com.psp.classifieds`) and can be overridden with `IOS_TEAM_ID` and
`IOS_BUNDLE_ID`. On the app side, `psp-api.fly.dev` has to be listed in the
Associated Domains entitlement, and the App ID needs the Associated Domains
capability enabled in the Apple Developer portal.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `GROUPS_IO_API_TOKEN` | API token for groups.io | Required |
| `GROUPS_IO_GROUP_ID` | Group ID for PSP Classifieds | 8407 |
| `DATABASE_URL` | PostgreSQL connection string | Required |
| `BACKFILL_DELAY_SECONDS` | Delay between backfill requests | 5 |
| `IOS_TEAM_ID` | Apple team ID for the universal link association file | K25Q76L89U |
| `IOS_BUNDLE_ID` | iOS bundle ID for the universal link association file | com.psp.classifieds |

