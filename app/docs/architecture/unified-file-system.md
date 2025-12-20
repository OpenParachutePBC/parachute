# Unified File System Architecture

**Purpose:** Design a file-first architecture where everything lives in a simple folder structure that syncs across devices via the backend.

**Philosophy:** Files are the source of truth. Databases are just indexes for performance.

---

## Core Concept

```
~/Parachute/                      # Root folder (configurable location)
├── captures/                     # All voice recordings & transcripts
│   ├── 2025-10-25_14-30-22.wav
│   ├── 2025-10-25_14-30-22.md   # Transcript markdown
│   ├── 2025-10-25_15-45-10.wav
│   ├── 2025-10-25_15-45-10.md
│   └── ...
│
└── spaces/                       # All AI chat spaces
    ├── work/
    │   ├── CLAUDE.md             # Space context for Claude
    │   ├── .space.json           # Space metadata
    │   ├── files/                # Space-specific files
    │   │   ├── document.pdf
    │   │   └── notes.txt
    │   └── conversations/
    │       ├── 2025-10-25_project-planning.md
    │       ├── 2025-10-26_code-review.md
    │       └── ...
    │
    ├── personal/
    │   ├── CLAUDE.md
    │   ├── .space.json
    │   └── conversations/
    │       └── ...
    │
    └── research/
        ├── CLAUDE.md
        ├── .space.json
        ├── files/
        └── conversations/
```

---

## File System Details

### Captures Folder (`captures/`)

**Purpose:** Store all voice recordings and their transcripts

**Structure:**
```
captures/
├── {timestamp}.wav              # Audio file
├── {timestamp}.md               # Transcript (markdown)
└── {timestamp}.json             # Metadata (optional index)
```

**Metadata Format** (`{timestamp}.json`):
```json
{
  "id": "uuid-here",
  "timestamp": "2025-10-25T14:30:22Z",
  "duration": 125.5,
  "source": "omi|phone|desktop",
  "deviceId": "omi-abc123",
  "transcribed": true,
  "transcriptionMode": "api|local",
  "modelUsed": "whisper-1|base|small|medium",
  "tags": ["meeting", "ideas"],
  "linkedToSpace": "work",
  "linkedToConversation": "2025-10-25_project-planning"
}
```

**Transcript Format** (`{timestamp}.md`):
```markdown
# Recording - October 25, 2025 2:30 PM

**Duration:** 2m 5s
**Source:** Omi Device
**Transcribed:** Whisper API

---

[Transcribed text goes here...]

---

## Tags
#meeting #ideas

## Linked
- Space: work
- Conversation: 2025-10-25_project-planning
```

---

### Spaces Folder (`spaces/`)

**Purpose:** Organize AI chat contexts with persistent memory

**Space Structure:**
```
spaces/{space-name}/
├── CLAUDE.md                    # AI context/memory
├── .space.json                  # Space metadata
├── files/                       # Files relevant to this space
│   └── ...
└── conversations/               # All conversations in this space
    └── {date}_{title}.md
```

**Space Metadata** (`.space.json`):
```json
{
  "id": "uuid-here",
  "name": "Work",
  "path": "/Users/alice/Parachute/spaces/work",
  "createdAt": "2025-10-25T10:00:00Z",
  "updatedAt": "2025-10-25T14:30:00Z",
  "mcpServers": ["filesystem", "brave-search"],
  "icon": "💼",
  "color": "#2E7D32"
}
```

**CLAUDE.md Format:**
```markdown
# Work Space

This space is for all work-related tasks and conversations.

## Context
- Current project: Parachute development
- Tech stack: Go backend, Flutter frontend
- Focus areas: File sync, ACP integration

## Guidelines
- Keep conversations focused on work topics
- Reference relevant files in the files/ folder
- Link to related recordings when needed

## Files
- See files/ folder for project documents
```

**Conversation Format** (`{date}_{title}.md`):
```markdown
# Project Planning - October 25, 2025

**Space:** Work
**Created:** 2025-10-25 14:30:22
**Updated:** 2025-10-25 15:45:10

---

## Messages

### User (14:30:22)
Let's plan out the file sync architecture...

### Claude (14:30:35)
Great! Here's my suggestion for the architecture...

### User (14:32:10)
[References recording: 2025-10-25_14-30-22.md]
I just recorded some thoughts on this...

---

## Linked Resources
- Recording: captures/2025-10-25_14-30-22.md
- Files: files/architecture-diagram.png
```

---

## Sync Strategy

### Client → Backend (Upload)

**What syncs:**
- New/modified files in `captures/`
- New/modified files in `spaces/`
- Metadata updates

**When:**
- On file creation/modification
- On app startup (check for unsynced changes)
- On network reconnection
- Manual sync trigger

**How:**
1. Client scans file system for changes since last sync
2. Computes file hashes to detect modifications
3. Uploads new/modified files to backend
4. Backend stores files and updates index
5. Backend broadcasts changes to other devices via WebSocket

### Backend → Client (Download)

**What syncs:**
- Files created/modified on other devices
- Files created via web interface

**When:**
- On app startup (pull latest)
- On WebSocket notification (real-time)
- On manual refresh

**How:**
1. Backend notifies client of changes via WebSocket
2. Client requests changed files
3. Backend streams files to client
4. Client writes files to local file system
5. Client updates local index

### Conflict Resolution

**Strategy:** Last-write-wins with conflict files

**Process:**
1. Detect conflict (same file modified on multiple devices)
2. Keep latest version based on timestamp
3. Save conflicted version as `{filename}.conflict.{timestamp}.{ext}`
4. Notify user of conflict for manual review

**Example:**
```
Original: 2025-10-25_meeting.md
Conflict: 2025-10-25_meeting.conflict.2025-10-25T15-30-22.md
```

---

## Backend Storage

### File Storage
- Use object storage (S3-compatible or local filesystem)
- Path structure mirrors client structure:
  ```
  /user-{userId}/captures/{filename}
  /user-{userId}/spaces/{spaceName}/{path}
  ```

### Database (Index Only)

**Purpose:** Fast queries, search, metadata

**Tables:**

**`files`**
```sql
CREATE TABLE files (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  path TEXT NOT NULL,              -- Relative path: captures/xyz.wav
  type TEXT NOT NULL,              -- capture|space|conversation|file
  hash TEXT NOT NULL,              -- SHA-256 of content
  size_bytes INTEGER NOT NULL,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  synced_at TIMESTAMP,
  metadata JSONB,                  -- Flexible metadata storage
  UNIQUE(user_id, path)
);
```

**`sync_state`**
```sql
CREATE TABLE sync_state (
  user_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  last_sync_at TIMESTAMP NOT NULL,
  PRIMARY KEY (user_id, device_id)
);
```

**`captures`** (Index for fast queries)
```sql
CREATE TABLE captures (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  file_id TEXT NOT NULL REFERENCES files(id),
  timestamp TIMESTAMP NOT NULL,
  duration REAL,
  source TEXT,                     -- omi|phone|desktop
  device_id TEXT,
  transcribed BOOLEAN DEFAULT false,
  transcription_file_id TEXT REFERENCES files(id),
  tags TEXT[],
  linked_space_id TEXT,
  linked_conversation_id TEXT,
  created_at TIMESTAMP NOT NULL
);
```

**`spaces`** (Index for fast queries)
```sql
CREATE TABLE spaces (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  path TEXT NOT NULL,              -- spaces/work
  icon TEXT,
  color TEXT,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  UNIQUE(user_id, name)
);
```

**`conversations`** (Index for fast queries)
```sql
CREATE TABLE conversations (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  space_id TEXT NOT NULL REFERENCES spaces(id),
  title TEXT NOT NULL,
  file_id TEXT NOT NULL REFERENCES files(id),
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
```

---

## Implementation Phases

### Phase 3A: Local File System Foundation
1. ✅ Define folder structure
2. Implement file system watcher (detect changes)
3. Create local file index (SQLite)
4. Update recorder to save to `captures/` folder
5. Update spaces to use `spaces/` folder structure
6. Migration tool (move existing data to new structure)

### Phase 3B: Backend File Storage
1. Add file storage endpoints (upload/download)
2. Implement file hashing and change detection
3. Create sync state tracking
4. Add database tables for file index
5. WebSocket notifications for changes

### Phase 3C: Sync Service
1. Client-side sync service
2. Upload new/modified files
3. Download remote changes
4. Conflict detection and resolution
5. Background sync with retry logic

### Phase 3D: Advanced Features
1. Selective sync (choose which spaces to sync)
2. Offline mode with queue
3. Bandwidth optimization (compression, delta sync)
4. Encryption at rest and in transit
5. File versioning/history

---

## Benefits of This Architecture

### 1. **Simplicity**
- Files are human-readable
- Easy to understand and debug
- Works with standard tools (text editors, grep, etc.)

### 2. **Portability**
- Export = just copy the folder
- Backup = standard file backup
- No vendor lock-in

### 3. **Reliability**
- Files are the source of truth
- Database can be rebuilt from files
- No database corruption issues

### 4. **Flexibility**
- Easy to add new file types
- User can organize files manually if needed
- Works with external tools (Syncthing, Dropbox, etc.)

### 5. **Performance**
- Database indexes provide fast queries
- File system provides fast reads
- Best of both worlds

### 6. **Offline-First**
- Everything works locally first
- Sync happens in background
- No internet required for core functionality

---

## Technical Considerations

### File System Watching
- Use `fsnotify` (Go) or `FileSystemWatcher` (C#) on client
- Watch `~/Parachute/` for changes
- Debounce rapid changes (avoid duplicate syncs)

### File Hashing
- Use SHA-256 for content hash
- Store hash in metadata
- Compare hashes to detect changes

### Timestamps
- Use file modification time + hash
- Server timestamp is source of truth for conflicts
- ISO 8601 format for consistency

### Paths
- Always use forward slashes (cross-platform)
- Store relative paths in database
- Resolve to absolute paths on client

### Security
- Encrypt files in transit (TLS)
- Encrypt files at rest (backend storage)
- User authentication via JWT
- File access control (user can only access their files)

---

## Migration Path

### From Current State

**Recorder:**
- Move from app-specific storage to `~/Parachute/captures/`
- Convert existing recordings to new format
- Update storage service to use new paths

**Spaces:**
- Already uses file system for CLAUDE.md
- Extend to store conversations as markdown files
- Add `.space.json` metadata
- Migrate existing conversations from database to files

**Timeline:**
1. Implement new file structure (local only)
2. Add sync service (basic upload/download)
3. Add real-time sync (WebSocket)
4. Add conflict resolution
5. Polish and optimize

---

## Questions to Resolve

1. **Root folder location:**
   - Default: `~/Parachute/`
   - Configurable in settings?
   - Platform-specific defaults?

2. **Naming conventions:**
   - Timestamps: ISO 8601 or filesystem-safe?
   - Spaces: kebab-case, snake_case, or preserve original?

3. **Metadata:**
   - Store in separate `.json` files or embed in markdown?
   - Trade-off: convenience vs. redundancy

4. **Sync frequency:**
   - Real-time (every change)?
   - Batched (every N seconds)?
   - Manual + auto?

5. **Storage limits:**
   - Client storage limits?
   - Server storage limits per user?
   - Quota warnings?

---

## Next Steps

1. Review and approve architecture
2. Implement Phase 3A (local file system)
3. Test with existing data
4. Implement Phase 3B (backend storage)
5. Implement Phase 3C (sync service)

---

**Status:** 📝 Design Complete - Ready for Review
**Last Updated:** 2025-10-25
