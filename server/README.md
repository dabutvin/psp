# PSP Server

Backend server for the Park Slope Parents Classifieds app. Ingests messages from groups.io and provides a read-only API.

## Setup

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
   docker compose up -d
   ```

4. **Configure environment:**
   ```bash
   cp env.example .env
   # Edit .env with your GROUPS_IO_API_TOKEN
   # DATABASE_URL is pre-configured for Docker
   ```

5. **Initialize database:**
   ```bash
   uv run python cli.py init-db
   ```

5. **Test API connection:**
   ```bash
   uv run python cli.py test-api
   ```

## Commands

```bash
# Initialize database schema
uv run python cli.py init-db

# Test groups.io API connectivity
uv run python cli.py test-api

# Poll for new messages (Phase 2)
uv run python cli.py poll

# Backfill historical data (Phase 3)
uv run python cli.py backfill --delay=5

# Start API server (Phase 5)
uv run python cli.py serve --host=0.0.0.0 --port=8000

# Or use the installed script (after uv sync)
uv run psp init-db
uv run psp test-api
```

## Project Structure

```
server/
├── pyproject.toml   # Dependencies and project config
├── cli.py           # Command-line interface
├── config.py        # Configuration/settings
├── db.py            # Database connection and schema
├── models.py        # Pydantic data models
├── api_client.py    # Groups.io API client
├── poller.py        # Live polling (Phase 2)
├── backfill.py      # Historical backfill (Phase 3)
├── server.py        # FastAPI server (Phase 5)
└── routers/         # API route handlers (Phase 5)
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `GROUPS_IO_API_TOKEN` | API token for groups.io | Required |
| `GROUPS_IO_GROUP_ID` | Group ID for PSP Classifieds | 8407 |
| `DATABASE_URL` | PostgreSQL connection string | Required |
| `POLL_INTERVAL_MINUTES` | How often to poll for new messages | 15 |
| `BACKFILL_DELAY_SECONDS` | Delay between backfill requests | 5 |
