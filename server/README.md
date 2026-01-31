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

# Fetch new messages until caught up
uv run python cli.py fetch
uv run python cli.py fetch --max=500 --dry-run  # preview without inserting

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
├── fetch.py         # Fetch new messages
├── backfill.py      # Historical backfill (Phase 3)
├── server.py        # FastAPI server (Phase 5)
└── routers/         # API route handlers (Phase 5)
```

## Scheduling

To run fetch periodically, use cron or launchd:

```bash
# Example crontab entry (every 15 minutes)
*/15 * * * * cd /path/to/psp/server && uv run python cli.py fetch >> /var/log/psp-fetch.log 2>&1
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `GROUPS_IO_API_TOKEN` | API token for groups.io | Required |
| `GROUPS_IO_GROUP_ID` | Group ID for PSP Classifieds | 8407 |
| `DATABASE_URL` | PostgreSQL connection string | Required |
| `BACKFILL_DELAY_SECONDS` | Delay between backfill requests | 5 |
