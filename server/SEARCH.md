# Search Architecture

This document explains how search works in the PSP Classifieds app.

## Overview

The app uses a **client-server architecture** with PostgreSQL full-text search (FTS) on the backend.

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   SwiftUI   │────▶│   FastAPI   │────▶│  PostgreSQL │
│  SearchView │     │  /messages  │     │     FTS     │
└─────────────┘     └─────────────┘     └─────────────┘
```

## iOS Client

### SearchView (`Views/SearchView.swift`)

- Presents modally with a search bar
- Shows recent searches before user starts typing
- Displays results as scrollable `PostCardView` items
- Tapping a result opens a paginated detail view

### SearchViewModel (`ViewModels/SearchViewModel.swift`)

Manages search state and logic:

```swift
func search() async {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return }
    
    isSearching = true
    let response = try await api.getPosts(search: query, limit: 50)
    results = response.messages
    addToRecentSearches(query)
    isSearching = false
}
```

### Recent Searches

- Stored locally in `UserDefaults`
- Limited to 10 most recent queries
- Duplicates are moved to the top instead of re-added
- Users can swipe to delete individual items or clear all

## API Request

The `APIClient` sends the search query as a URL parameter:

```
GET /api/v1/messages?search=couch&limit=50
```

## Server-Side Implementation

### Endpoint (`routers/messages.py`)

The `/messages` endpoint accepts a `search` query parameter and builds a dynamic SQL query:

```python
if search:
    conditions.append(f"m.search_vector @@ plainto_tsquery('english', ${param_idx})")
    params.append(search)
```

### PostgreSQL Full-Text Search

Each message has a `search_vector` column (`tsvector` type) that contains tokenized and stemmed words from the `subject` and `body` fields.

**How the search vector is built:**

```sql
to_tsvector('english', coalesce(subject, '') || ' ' || coalesce(body, ''))
```

**How queries are matched:**

```sql
search_vector @@ plainto_tsquery('english', 'user search terms')
```

### Database Schema

| Column | Type | Purpose |
|--------|------|---------|
| `search_vector` | `tsvector` | Pre-computed search tokens |
| `idx_messages_search` | GIN index | Fast full-text lookups |

### Automatic Updates

A database trigger automatically updates the `search_vector` column whenever a message is inserted or updated.

For messages created before the trigger existed, run:

```bash
python cli.py migrate-search
```

## Search Features

PostgreSQL's `english` text search configuration provides:

- **Stemming**: "running" matches "run", "runs", "ran"
- **Stop words**: Common words like "the", "a", "is" are ignored
- **Case insensitive**: "Couch" matches "couch", "COUCH"
- **Word boundaries**: Searches match whole words, not substrings

## Performance

- **GIN Index**: Enables sub-millisecond lookups even with thousands of messages
- **Rate Limited**: 60 requests/minute per client
- **Caching**: Results include ETag headers for client-side caching

## Testing

Search functionality can be tested with:

```bash
curl "https://psp-api.fly.dev/api/v1/messages?search=couch&limit=5"
```
