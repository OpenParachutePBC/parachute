# Space Notes API Documentation

**Version:** 1.0
**Last Updated:** November 3, 2025

## Overview

The Space Notes API enables linking voice captures to spaces with space-specific context, tags, and metadata. This allows notes to exist canonically in `~/Parachute/captures/` while being referenced and contextualized differently across multiple spaces.

## Base URL

```
http://localhost:8080/api/spaces/:id/notes
```

---

## Endpoints

### 1. Link Note to Space

Links a capture to a space with optional context and tags.

**Endpoint:** `POST /api/spaces/:id/notes`

**Path Parameters:**
- `id` (string, required) - Space ID

**Request Body:**
```json
{
  "capture_id": "uuid-string",
  "note_path": "captures/2025-11-03_10-30-45.md",
  "context": "Space-specific interpretation of this note",
  "tags": ["tag1", "tag2"]
}
```

**Request Fields:**
- `capture_id` (string, required) - Unique identifier for the capture
- `note_path` (string, required) - Relative path to the note file (e.g., `captures/YYYY-MM-DD_HH-MM-SS.md`)
- `context` (string, optional) - Space-specific context or interpretation
- `tags` (array of strings, optional) - Tags specific to this space

**Response:** `201 Created`
```json
{
  "message": "note linked successfully",
  "space_id": "space-uuid",
  "capture_id": "capture-uuid"
}
```

**Behavior:**
- If the capture is already linked to this space, the context and tags will be updated (upsert)
- The `linked_at` timestamp is set automatically
- The actual note file remains in `~/Parachute/captures/`

**Example:**
```bash
curl -X POST http://localhost:8080/api/spaces/abc-123/notes \
  -H "Content-Type: application/json" \
  -d '{
    "capture_id": "capture-456",
    "note_path": "captures/2025-11-03_10-30-45.md",
    "context": "Discussion about regenerative farming practices",
    "tags": ["farming", "regeneration", "soil-health"]
  }'
```

**Error Responses:**
- `400 Bad Request` - Missing required fields (`capture_id` or `note_path`)
- `404 Not Found` - Space not found
- `500 Internal Server Error` - Database error

---

### 2. Get Notes for Space

Retrieves all notes linked to a space with optional filtering and pagination.

**Endpoint:** `GET /api/spaces/:id/notes`

**Path Parameters:**
- `id` (string, required) - Space ID

**Query Parameters:**
- `tags` (string, optional) - Comma-separated list of tags to filter by (e.g., `tags=farming,soil`)
- `start_date` (string, optional) - Filter notes linked after this date (RFC3339 format)
- `end_date` (string, optional) - Filter notes linked before this date (RFC3339 format)
- `limit` (integer, optional) - Maximum number of notes to return (default: 50)
- `offset` (integer, optional) - Number of notes to skip (default: 0)

**Response:** `200 OK`
```json
{
  "notes": [
    {
      "id": "link-uuid",
      "capture_id": "capture-uuid",
      "note_path": "captures/2025-11-03_10-30-45.md",
      "linked_at": "2025-11-03T10:30:45Z",
      "context": "Space-specific context",
      "tags": ["tag1", "tag2"],
      "last_referenced": "2025-11-03T15:45:00Z",
      "metadata": {}
    }
  ],
  "total": 1
}
```

**Ordering:** Notes are returned in reverse chronological order (most recently linked first)

**Example:**
```bash
# Get all notes
curl http://localhost:8080/api/spaces/abc-123/notes

# Filter by tags
curl "http://localhost:8080/api/spaces/abc-123/notes?tags=farming,soil"

# Pagination
curl "http://localhost:8080/api/spaces/abc-123/notes?limit=10&offset=20"

# Date range
curl "http://localhost:8080/api/spaces/abc-123/notes?start_date=2025-11-01T00:00:00Z&end_date=2025-11-03T23:59:59Z"
```

**Error Responses:**
- `404 Not Found` - Space not found
- `500 Internal Server Error` - Database error

---

### 3. Update Note Context

Updates the space-specific context and/or tags for a linked note.

**Endpoint:** `PUT /api/spaces/:id/notes/:capture_id`

**Path Parameters:**
- `id` (string, required) - Space ID
- `capture_id` (string, required) - Capture ID

**Request Body:**
```json
{
  "context": "Updated space-specific context",
  "tags": ["new", "tags"]
}
```

**Request Fields:**
- `context` (string, optional) - New context (omit to keep existing)
- `tags` (array of strings, optional) - New tags (omit to keep existing)

**Note:** At least one field (`context` or `tags`) must be provided.

**Response:** `200 OK`
```json
{
  "message": "note context updated successfully",
  "space_id": "space-uuid",
  "capture_id": "capture-uuid"
}
```

**Example:**
```bash
# Update only context
curl -X PUT http://localhost:8080/api/spaces/abc-123/notes/capture-456 \
  -H "Content-Type: application/json" \
  -d '{"context": "Updated interpretation"}'

# Update only tags
curl -X PUT http://localhost:8080/api/spaces/abc-123/notes/capture-456 \
  -H "Content-Type: application/json" \
  -d '{"tags": ["updated", "tags"]}'

# Update both
curl -X PUT http://localhost:8080/api/spaces/abc-123/notes/capture-456 \
  -H "Content-Type: application/json" \
  -d '{
    "context": "New context",
    "tags": ["new", "tags"]
  }'
```

**Error Responses:**
- `400 Bad Request` - No fields provided
- `404 Not Found` - Space or note not found
- `500 Internal Server Error` - Database error

---

### 4. Unlink Note from Space

Removes the link between a capture and a space. The note file itself is not deleted.

**Endpoint:** `DELETE /api/spaces/:id/notes/:capture_id`

**Path Parameters:**
- `id` (string, required) - Space ID
- `capture_id` (string, required) - Capture ID

**Response:** `200 OK`
```json
{
  "message": "note unlinked successfully",
  "space_id": "space-uuid",
  "capture_id": "capture-uuid"
}
```

**Example:**
```bash
curl -X DELETE http://localhost:8080/api/spaces/abc-123/notes/capture-456
```

**Error Responses:**
- `404 Not Found` - Space or note not found
- `500 Internal Server Error` - Database error

---

### 5. Get Note Content with Space Context

Retrieves the full note content along with space-specific metadata. Also tracks that this note was referenced.

**Endpoint:** `GET /api/spaces/:id/notes/:capture_id/content`

**Path Parameters:**
- `id` (string, required) - Space ID
- `capture_id` (string, required) - Capture ID

**Response:** `200 OK`
```json
{
  "capture_id": "capture-uuid",
  "note_path": "captures/2025-11-03_10-30-45.md",
  "content": "# Note Title\n\nNote content here...",
  "space_context": "Space-specific context",
  "tags": ["tag1", "tag2"],
  "linked_at": "2025-11-03T10:30:45Z",
  "last_referenced": "2025-11-03T15:45:00Z"
}
```

**Side Effect:** Updates `last_referenced` timestamp to track note usage

**Example:**
```bash
curl http://localhost:8080/api/spaces/abc-123/notes/capture-456/content
```

**Error Responses:**
- `404 Not Found` - Space, note, or file not found
- `500 Internal Server Error` - Database or file system error

---

### 6. Get Database Statistics

Retrieves comprehensive statistics about a space's database.

**Endpoint:** `GET /api/spaces/:id/database/stats`

**Path Parameters:**
- `id` (string, required) - Space ID

**Response:** `200 OK`
```json
{
  "schema_version": "1",
  "space_id": "space-uuid",
  "created_at": 1699027845,
  "total_notes": 42,
  "all_tags": ["farming", "soil", "regeneration", "biodiversity"],
  "recent_notes": [
    {
      "id": "link-uuid",
      "capture_id": "capture-uuid",
      "note_path": "captures/2025-11-03_10-30-45.md",
      "linked_at": "2025-11-03T10:30:45Z",
      "context": "Context",
      "tags": ["tag1"],
      "last_referenced": null,
      "metadata": {}
    }
  ],
  "metadata": {
    "schema_version": "1",
    "space_id": "space-uuid",
    "created_at": "1699027845"
  },
  "tables": ["space_metadata", "relevant_notes"]
}
```

**Example:**
```bash
curl http://localhost:8080/api/spaces/abc-123/database/stats
```

**Error Responses:**
- `404 Not Found` - Space not found
- `500 Internal Server Error` - Database error

---

### 7. Query Database Table

Retrieves all rows from a specific table in the space database.

**Endpoint:** `GET /api/spaces/:id/database/tables/:table_name`

**Path Parameters:**
- `id` (string, required) - Space ID
- `table_name` (string, required) - Table name (e.g., `relevant_notes`, `space_metadata`)

**Security:** Table names are validated to prevent SQL injection. Only alphanumeric characters and underscores are allowed.

**Response:** `200 OK`
```json
{
  "table_name": "relevant_notes",
  "columns": ["id", "capture_id", "note_path", "linked_at", "context", "tags", "last_referenced", "metadata"],
  "rows": [
    {
      "id": "link-uuid",
      "capture_id": "capture-uuid",
      "note_path": "captures/2025-11-03_10-30-45.md",
      "linked_at": 1699027845,
      "context": "Context",
      "tags": ["tag1", "tag2"],
      "last_referenced": null,
      "metadata": null
    }
  ],
  "row_count": 1
}
```

**Example:**
```bash
curl http://localhost:8080/api/spaces/abc-123/database/tables/relevant_notes
curl http://localhost:8080/api/spaces/abc-123/database/tables/space_metadata
```

**Error Responses:**
- `404 Not Found` - Space not found
- `500 Internal Server Error` - Table not found or database error

---

## Data Model

### Space Database Schema

Each space has a `space.sqlite` database with the following structure:

#### `space_metadata` Table

```sql
CREATE TABLE space_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
```

**Standard Metadata:**
- `schema_version` - Database schema version (currently "1")
- `space_id` - UUID of the space
- `created_at` - Unix timestamp of database creation

#### `relevant_notes` Table

```sql
CREATE TABLE relevant_notes (
    id TEXT PRIMARY KEY,                -- UUID for this link
    capture_id TEXT NOT NULL,           -- Links to capture's JSON id
    note_path TEXT NOT NULL,            -- Relative: captures/YYYY-MM-DD_HH-MM-SS.md
    linked_at INTEGER NOT NULL,         -- Unix timestamp
    context TEXT,                       -- Space-specific interpretation
    tags TEXT,                          -- JSON array: ["tag1", "tag2"]
    last_referenced INTEGER,            -- Unix timestamp
    metadata TEXT,                      -- JSON: extensible per-space
    UNIQUE(capture_id)                  -- One entry per capture per space
);

CREATE INDEX idx_relevant_notes_tags ON relevant_notes(tags);
CREATE INDEX idx_relevant_notes_last_ref ON relevant_notes(last_referenced);
CREATE INDEX idx_relevant_notes_linked_at ON relevant_notes(linked_at DESC);
```

---

## Use Cases

### 1. Cross-Pollination Between Spaces

The same voice recording can be linked to multiple spaces with different context:

```bash
# Link to "Regen Hub" space with farming context
curl -X POST http://localhost:8080/api/spaces/regen-hub/notes \
  -d '{"capture_id": "abc-123", "note_path": "captures/note.md",
       "context": "Farming insight", "tags": ["farming"]}'

# Link same note to "Personal" space with different context
curl -X POST http://localhost:8080/api/spaces/personal/notes \
  -d '{"capture_id": "abc-123", "note_path": "captures/note.md",
       "context": "Personal reflection", "tags": ["journal"]}'
```

### 2. Smart Context in CLAUDE.md

Use note statistics in space system prompts:

```markdown
# Space Overview

Total notes: {{note_count}}
Recent topics: {{recent_tags}}
Architecture discussions: {{notes_tagged:architecture}}

## Recent Activity
{{recent_notes}}
```

### 3. Tracking Note Usage

When notes are referenced in conversations, the `last_referenced` timestamp is automatically updated, allowing you to see which notes are most valuable in each space.

---

## Best Practices

1. **Descriptive Context:** Use the `context` field to explain why this note is relevant to this space
2. **Consistent Tagging:** Use a consistent tag vocabulary within each space for better filtering
3. **Link Thoughtfully:** Not every note needs to be in every space - link intentionally
4. **Clean Up:** Unlink notes that are no longer relevant to keep spaces focused
5. **Use Statistics:** Check database stats periodically to understand your knowledge patterns

---

## Future Enhancements

- **Bulk Operations:** Link multiple notes at once
- **Smart Suggestions:** Auto-suggest spaces for new notes based on content
- **Tag Autocomplete:** Suggest tags based on existing notes
- **Semantic Search:** Find notes by meaning, not just tags
- **Note Collections:** Group related notes within a space

---

## Related Documentation

- [Development Guide](../development/space-sqlite.md) - How to work with space.sqlite
- [Feature Specification](../features/space-sqlite-knowledge-system.md) - Full feature details
- [Architecture](../../ARCHITECTURE.md) - System design overview
