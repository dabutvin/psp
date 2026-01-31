# PSP Server

Backend server for the Park Slope Parents Classifieds app. Ingests messages from groups.io and provides a read-only API.

## Deployment

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

## CLI Commands

```bash
uv run python cli.py init-db              # Initialize database schema
uv run python cli.py test-api             # Test groups.io API connectivity
uv run python cli.py fetch                # Fetch new messages
uv run python cli.py backfill --delay=5   # Backfill historical data
uv run python cli.py serve --reload       # Start API server (dev mode)
uv run python cli.py stats                # Show system statistics
uv run python cli.py migrate-search       # Populate search vectors
```

## Project Structure

```
server/
├── pyproject.toml      # Dependencies and project config
├── Dockerfile          # Container image definition
├── docker-compose.yml  # Multi-container orchestration
├── cli.py              # Command-line interface
├── config.py           # Configuration/settings
├── db.py               # Database connection and schema
├── models.py           # Pydantic data models
├── api_client.py       # Groups.io API client
├── fetch.py            # Fetch new messages
├── backfill.py         # Historical backfill
├── server.py           # FastAPI server
├── logging_config.py   # Structured logging
├── stats.py            # System statistics
├── migrations.py       # Database migrations
└── routers/            # API route handlers
    ├── messages.py     # /api/v1/messages
    ├── hashtags.py     # /api/v1/hashtags
    └── stats.py        # /api/v1/stats
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `GROUPS_IO_API_TOKEN` | API token for groups.io | Required |
| `GROUPS_IO_GROUP_ID` | Group ID for PSP Classifieds | 8407 |
| `DATABASE_URL` | PostgreSQL connection string | Required |
| `BACKFILL_DELAY_SECONDS` | Delay between backfill requests | 5 |
