# Parachute - System Architecture

**Version:** 2.1
**Date:** November 5, 2025
**Status:** Active Development - Git-Based Sync Foundation

---

## Overview

Parachute is a cross-platform second brain application that provides a beautiful interface for interacting with Claude AI via the Agent Client Protocol (ACP). It combines local-first file management, voice recording with Omi device support, and structured knowledge management through space-specific SQLite databases.

**Core Philosophy**: "One folder, one file system that organizes your data to enable it to be open and interoperable"

All user data lives in a **configurable vault** (default: `~/Parachute/`):

- **Captures** (`{vault}/{captures}/`) - Canonical voice recordings and notes (subfolder name configurable)
- **Spaces** (`{vault}/{spaces}/`) - AI contexts with system prompts and knowledge databases (subfolder name configurable)

**Platform-Specific Defaults:**

- **macOS/Linux:** `~/Parachute/`
- **Android:** `/storage/emulated/0/Android/data/.../files/Parachute`
- **iOS:** App Documents directory

**Vault Compatibility:** Works with existing Obsidian, Logseq, and other markdown-based note-taking vaults. Users can point Parachute at their existing vault and configure subfolder names to match their organization.

This architecture enables notes to "cross-pollinate" between spaces while remaining canonical and portable.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Flutter Frontend                        │
│           (iOS, Android, Web, Desktop)                      │
│                                                             │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐   │
│  │   Spaces    │  │     Chat     │  │    Settings     │   │
│  │   Screen    │  │    Screen    │  │     Screen      │   │
│  └─────────────┘  └──────────────┘  └─────────────────┘   │
│         │                 │                  │              │
│         └─────────────────┴──────────────────┘              │
│                        │                                    │
│              ┌─────────▼─────────┐                          │
│              │  Riverpod State   │                          │
│              │    Management     │                          │
│              └─────────┬─────────┘                          │
│                        │                                    │
│         ┌──────────────┴──────────────┐                     │
│         │                             │                     │
│    ┌────▼─────┐              ┌────────▼────────┐           │
│    │ API      │              │   WebSocket     │           │
│    │ Service  │              │   Service       │           │
│    │ (HTTP)   │              │   (Real-time)   │           │
│    └────┬─────┘              └────────┬────────┘           │
└─────────┼────────────────────────────┼────────────────────┘
          │                            │
          │    Network (HTTP/WS)       │
          │                            │
┌─────────▼────────────────────────────▼────────────────────┐
│                                                            │
│                    Go Backend Service                     │
│                  (Single Binary, Port 8080)               │
│                                                            │
│  ┌──────────────────────────────────────────────────┐    │
│  │              REST API + WebSocket                │    │
│  │                                                   │    │
│  │  /api/auth          - Authentication             │    │
│  │  /api/spaces        - Space CRUD                 │    │
│  │  /api/conversations - Conversation management    │    │
│  │  /api/messages      - Send messages              │    │
│  │  /ws                - WebSocket chat streaming   │    │
│  └───────────────────────┬──────────────────────────┘    │
│                          │                                │
│  ┌───────────────────────▼──────────────────────────┐    │
│  │            Business Logic Layer                   │    │
│  │                                                   │    │
│  │  • Space Service      - Manage Spaces            │    │
│  │  • Conversation Service - Manage conversations   │    │
│  │  • Session Service    - ACP session lifecycle    │    │
│  │  • Permission Service - Handle tool permissions  │    │
│  └───────────────────────┬──────────────────────────┘    │
│                          │                                │
│  ┌───────────────────────▼──────────────────────────┐    │
│  │            ACP Integration Layer                  │    │
│  │                                                   │    │
│  │  Spawns: npx @zed-industries/claude-code-acp     │    │
│  │  Communication: JSON-RPC 2.0 (stdin/stdout)      │    │
│  │  Methods: initialize, new_session, session/prompt│    │
│  │  Events: session/update (streaming)              │    │
│  └───────────────────────┬──────────────────────────┘    │
│                          │                                │
│  ┌───────────────────────▼──────────────────────────┐    │
│  │             Storage Layer (SQLite)                │    │
│  │                                                   │    │
│  │  Tables: spaces, conversations, messages,        │    │
│  │          sessions, users (future)                │    │
│  └──────────────────────────────────────────────────┘    │
│                                                            │
└────────────────────────────────────────────────────────────┘
                          │
                          │
              ┌───────────▼──────────────┐
              │  File System             │
              │                          │
              │  • Spaces directories    │
              │  • CLAUDE.md files       │
              │  • .mcp.json configs     │
              │  • User files            │
              └──────────────────────────┘
```

---

## Communication Flow: Sending a Message

```
1. User types message in Flutter app
   └─→ Flutter UI captures input

2. Flutter calls REST API
   └─→ POST /api/messages
       {
         "conversation_id": "uuid",
         "content": "Tell me about X"
       }

3. Go backend receives request
   └─→ Stores user message in database
   └─→ Retrieves conversation history
   └─→ Loads Space's CLAUDE.md file
   └─→ Builds ACP prompt with context

4. Backend calls ACP via claude-code-acp subprocess
   └─→ JSON-RPC request: session/prompt
   └─→ Includes: message + history + CLAUDE.md context

5. ACP streams response via session/update notifications
   └─→ Backend receives: text chunks, tool calls, permissions

6. Backend emits WebSocket events to Flutter
   └─→ Events: message_chunk, tool_call, permission_request

7. Flutter receives events and updates UI in real-time
   └─→ Displays streaming text
   └─→ Shows tool execution
   └─→ Prompts for permissions if needed

8. On completion, backend stores assistant message
   └─→ Database updated with full conversation
```

---

## Technology Choices

### Backend: Go

**Why Go?**

- Single binary deployment (~10-50MB memory footprint)
- Excellent concurrency (goroutines) for WebSocket handling
- AI-friendly (works great with AI coding assistants)
- Fast compilation, simple syntax, reliable
- Great for web APIs

**Framework:** Fiber

- Express-like API (familiar to many developers)
- Built-in WebSocket support
- Fast and lightweight
- Great documentation

**Database:** SQLite

- Embedded (no separate server needed)
- Perfect for single-user/small deployments
- Works everywhere (mobile, desktop, server)
- Easy to back up (single file)
- Migration path to PostgreSQL when needed

### Frontend: Flutter

**Why Flutter?**

- One codebase → iOS, Android, Web, Desktop
- Beautiful UI with 60/120fps animations
- Hot reload for fast development
- Material Design 3 + Cupertino widgets
- Massive ecosystem, Google-backed

**State Management:** Riverpod

- Type-safe, compile-time checking
- Modern, well-documented
- Better than Provider (older) and Bloc (verbose)
- Great for async operations

**HTTP Client:** Dio

- Interceptors for JWT tokens
- Request/response logging
- Error handling and retries
- Well-tested and maintained

**WebSocket:** web_socket_channel

- Official Dart package
- Cross-platform
- Simple, reliable

### ACP Integration: Hybrid Approach

**Why Hybrid (not pure Go SDK)?**

- `claude-code-acp` is battle-tested by Zed
- Official, maintained by Zed/Anthropic
- Automatic updates
- Lower risk than early-stage Go SDK

**How it works:**

```go
// Spawn subprocess
cmd := exec.Command("npx", "@zed-industries/claude-code-acp")
cmd.Env = append(os.Environ(), "ANTHROPIC_API_KEY="+apiKey)
stdin, _ := cmd.StdinPipe()
stdout, _ := cmd.StdoutPipe()
cmd.Start()

// Communicate via JSON-RPC 2.0
// Write requests to stdin
// Read responses/notifications from stdout
```

**Alternative:** `github.com/joshgarnett/agent-client-protocol-go`

- Pure Go implementation
- Early stage but viable
- Consider for future if Node.js dependency becomes problematic

---

## Data Model

### Core Entities

```
User (future multi-user support)
  └─ has many Spaces
      ├─ CLAUDE.md file (persistent system prompt)
      ├─ space.sqlite (🆕 space-specific knowledge database)
      ├─ files/ directory (space-specific files)
      ├─ Links to Captures via space.sqlite
      └─ has many Conversations
          └─ has many Messages
              ├─ role: "user" | "assistant"
              ├─ content: text
              └─ metadata: tool calls, etc.

Captures (voice recordings, canonical notes)
  ├─ Stored in ~/Parachute/captures/
  ├─ .md file (transcript)
  ├─ .wav file (audio)
  ├─ .json file (metadata)
  └─ Can be linked to multiple Spaces

Session (ACP session tracking)
  └─ belongs to Conversation
  └─ tracks ACP session_id
  └─ lifecycle: active → inactive on app restart
```

### File System Architecture

**Note:** Vault location and subfolder names are configurable. Default structure shown below.

```
{vault}/                                # Configurable location (default: ~/Parachute/)
├── {captures}/                         # Configurable name (default: captures/)
│   ├── 2025-10-26_00-00-17.md        # Transcript
│   ├── 2025-10-26_00-00-17.wav       # Audio
│   └── 2025-10-26_00-00-17.json      # Recording metadata
│
└── {spaces}/                           # Configurable name (default: spaces/)
    ├── regen-hub/
    │   ├── CLAUDE.md                   # System prompt
    │   ├── space.sqlite                # 🆕 Knowledge database
    │   └── files/                      # Space-specific files
    │
    └── personal/
        ├── CLAUDE.md
        ├── space.sqlite                # 🆕 Different context
        └── files/
```

**Vault Management:**

- Location configured via `FileSystemService` (Flutter)
- Stored in `SharedPreferences` for persistence
- Can be changed via Settings → Parachute Folder → Change Location
- Subfolder names (`captures/` and `spaces/`) also configurable
- Enables integration with existing Obsidian/Logseq vaults

### Backend Database Schema (SQLite)

The backend maintains a central SQLite database for app metadata:

```sql
-- Spaces
CREATE TABLE spaces (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,              -- Future: FK to users
    name TEXT NOT NULL,
    path TEXT NOT NULL UNIQUE,          -- Absolute path to ~/Parachute/spaces/<name>
    icon TEXT,                          -- Emoji icon
    color TEXT,                         -- Hex color code
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

-- Conversations
CREATE TABLE conversations (
    id TEXT PRIMARY KEY,
    space_id TEXT NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
    title TEXT NOT NULL,                -- Auto-generated from first message
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

-- Messages
CREATE TABLE messages (
    id TEXT PRIMARY KEY,
    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    metadata TEXT                       -- JSON: tool calls, permissions, etc.
);

-- Sessions (ACP session tracking)
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,                -- ACP session_id
    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    created_at INTEGER NOT NULL,
    last_used_at INTEGER NOT NULL,
    is_active INTEGER DEFAULT 1,        -- Boolean: 1=active, 0=inactive
    UNIQUE(conversation_id)             -- One active session per conversation
);
```

### Space-Specific Database Schema (space.sqlite)

**NEW**: Each space has its own `space.sqlite` file for knowledge management:

```sql
-- Metadata about the space database
CREATE TABLE space_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- Core table: Links captures with space-specific context
CREATE TABLE relevant_notes (
    id TEXT PRIMARY KEY,                      -- UUID for this link
    capture_id TEXT NOT NULL,                 -- Links to capture's JSON id
    note_path TEXT NOT NULL,                  -- Relative: captures/YYYY-MM-DD_HH-MM-SS.md
    linked_at INTEGER NOT NULL,               -- Unix timestamp
    context TEXT,                             -- Space-specific interpretation
    tags TEXT,                                -- JSON array: ["tag1", "tag2"]
    last_referenced INTEGER,                  -- Track when used in conversation
    metadata TEXT,                            -- JSON: extensible per-space
    UNIQUE(capture_id)                        -- One entry per capture per space
);

-- Indexes for performance
CREATE INDEX idx_relevant_notes_tags ON relevant_notes(tags);
CREATE INDEX idx_relevant_notes_last_ref ON relevant_notes(last_referenced);
CREATE INDEX idx_relevant_notes_linked_at ON relevant_notes(linked_at DESC);

-- Optional: Custom tables for specific space types (future)
-- Spaces can extend their schema with domain-specific tables
```

**Key Design Points**:

- Notes stay canonical in `~/Parachute/captures/` (never duplicated)
- `space.sqlite` stores _relationships_ and _context_, not content
- Same capture can be linked to multiple spaces with different context
- Enables "cross-pollination" of ideas between spaces

---

## Key Architectural Decisions

### Decision 1: Monorepo Structure

**Choice:** Single repo with `backend/` and `app/` directories

**Rationale:**

- Easier to coordinate changes
- Shared documentation in one place
- Single issue tracker
- Can split later if needed

**Trade-offs:**

- Larger repo size
- Different build processes in one repo

### Decision 2: Hybrid ACP Approach

**Choice:** Spawn `claude-code-acp` Node.js subprocess (not pure Go SDK)

**Rationale:**

- Battle-tested by Zed
- Official, maintained by Zed/Anthropic
- Gets updates automatically
- Lower risk for MVP

**Trade-offs:**

- Node.js dependency
- Slightly more complex process management

**Alternative Considered:** Pure Go SDK (`github.com/joshgarnett/agent-client-protocol-go`)

- May revisit in future if Node.js becomes problematic

### Decision 3: SQLite for MVP

**Choice:** SQLite (not PostgreSQL)

**Rationale:**

- Embedded, no separate server
- Works everywhere (mobile, desktop, server)
- Perfect for single-user application
- Easy backups (single file)

**Migration Path:** Move to PostgreSQL when adding:

- Multi-user support
- Team features
- Cloud sync with conflict resolution

### Decision 4: JWT Authentication

**Choice:** JWT tokens (not session cookies)

**Rationale:**

- Stateless
- Mobile-friendly
- Standard approach for API authentication
- Works across domains (future web app)

**Implementation:**

- Store in Flutter secure storage (iOS Keychain, Android Keystore)
- Include in Authorization header
- Short-lived access tokens (future: refresh tokens)

### Decision 5: Local-First Architecture

**Choice:** All data local by default in `~/Parachute/`, cloud sync optional (future)

**Rationale:**

- Privacy by default
- Works offline
- Fast performance
- User owns their data
- Aligns with brand philosophy (openness, control)
- Data is portable and interoperable

**Future Cloud Features:**

- Optional sync for multi-device
- Optional team Spaces
- User chooses what to sync

### Decision 6: Space SQLite Knowledge System (NEW - Oct 2025)

**Choice:** Each space has its own `space.sqlite` database for knowledge management

**Rationale:**

- Notes stay canonical in `~/Parachute/captures/` (never duplicated)
- Enables space-specific context and tags for same note
- Allows cross-pollination between spaces
- Structured querying via SQL
- Extensible per-space (custom tables)
- Local-first, portable

**Trade-offs:**

- Multiple SQLite databases to manage
- Need to coordinate between backend DB and space DBs
- More complex backup strategy

**Alternative Considered:**

- Central knowledge graph database
- Tags in backend DB only
- Rejected because they would either duplicate notes or trap them in single spaces

### Decision 7: Vault-Style Architecture with Configurable Paths (NEW - Nov 2025)

**Choice:** Configurable vault location and subfolder names, Obsidian/Logseq compatible

**Rationale:**

- **Interoperability:** Users can use Parachute alongside Obsidian, Logseq, etc.
- **Flexibility:** Support different organizational preferences
- **Platform-specific:** Android needs external storage, iOS needs app sandbox
- **User control:** Vault location visible and changeable in Settings
- **Portability:** Can move vault to different locations (cloud folder, etc.)

**Implementation:**

- `FileSystemService` manages all path logic in Flutter
- Platform-specific defaults (macOS: `~/Parachute/`, Android: external storage)
- Subfolder names stored in `SharedPreferences` (keys: `parachute_captures_folder_name`, `parachute_spaces_folder_name`)
- Backend remains path-agnostic (receives absolute paths from frontend)

**Trade-offs:**

- More complex path management (can't hardcode `~/Parachute/captures/`)
- Need to handle path validation and migration
- Users could break things by pointing at invalid locations

**Alternative Considered:**

- Hardcoded `~/Parachute/` location
- Rejected because it limits interoperability and platform compatibility

---

## Git-Based Synchronization (Nov 2025 - Strategic Pivot)

### Architecture Overview

**Strategic Decision**: Use Git for multi-device sync instead of custom backend infrastructure.

```
┌─────────────────────────────────────────────────────────────┐
│                     Git Repository                           │
│                  (GitHub/GitLab/Self-hosted)                │
│                                                              │
│  ~/Parachute/                                               │
│  ├── captures/                                              │
│  │   ├── 2025-11-05_10-30-00.md (transcript)              │
│  │   ├── 2025-11-05_10-30-00.wav (audio)                  │
│  │   └── 2025-11-05_10-30-00.json (metadata)              │
│  └── spaces/                                                │
│      └── my-space/                                          │
│          ├── CLAUDE.md (system prompt)                     │
│          ├── space.sqlite (knowledge graph)                │
│          └── files/                                         │
└─────────────────────────────────────────────────────────────┘
         ▲                                    ▲
         │ git push                           │ git pull
         │                                    │
    ┌────┴─────┐                         ┌───┴──────┐
    │ Frontend │                         │ Backend  │
    │ (Mobile) │                         │ (Laptop) │
    │          │                         │          │
    │ • git2dart                        │ • go-git  │
    │ • Auto-commit                     │ • Pre-pull│
    │ • GitHub PAT                      │ • Post-push│
    └──────────┘                         └──────────┘
```

### Key Principles

1. **Git Replaces Custom Sync** - Standard Git operations instead of custom API
2. **Backend Optional** - Frontend works standalone, backend only for agentic AI
3. **Shared Repository** - Both frontend and backend sync to same repo
4. **Local-First** - Works offline, syncs when available
5. **Standard Tools** - Any Git hosting (GitHub, GitLab, self-hosted)

### Implementation Details

**Frontend (Flutter)**

- Library: `git2dart` (libgit2 bindings via FFI)
- Auth: GitHub Personal Access Tokens (SSH keys future)
- Operations: clone, pull, commit, push
- Trigger: Auto-commit after each recording save
- Status: Sync indicator in UI

**Backend (Go)**

- Library: `go-git` (pure Go implementation)
- Workflow: Pull → AI task → Commit → Push
- Verification: Check frontend/backend on compatible commits
- Role: Only for long-running agentic AI tasks

**Conflict Resolution**

- Strategy: Optimistic (most captures are new files)
- Detection: Check for merge conflicts
- Resolution: "Last write wins" for different files (MVP)
- Future: UI for manual resolution, LLM-assisted merging

### Benefits

- **Standard workflows** - Familiar to developers
- **No custom infrastructure** - Use existing Git hosting
- **E2E encryption** - Git repos can be encrypted
- **Version history** - Built-in with Git
- **Flexibility** - Works with any Git provider

### Trade-offs

- **Binary files** - Audio files may need Git LFS eventually
- **Learning curve** - Users need basic Git understanding
- **Conflict complexity** - Manual resolution needed for complex cases

**See**: [docs/architecture/git-sync-strategy.md](../architecture/git-sync-strategy.md) for detailed implementation plan

---

## Security Considerations

### MVP (Local-only)

- User provides their own Anthropic API key
- Stored securely (Flutter secure storage)
- Never transmitted to our servers (we don't have servers yet)
- All data local

### Git Sync (Current Focus)

- GitHub Personal Access Tokens stored in flutter_secure_storage
- Private repositories only
- User controls Git provider (can self-host)
- E2E encrypted repos possible (future)

### Future Enhancements

- SSH key support for Git authentication
- GPG signing for commits
- Git-crypt for encrypted repos
- Federated sync options

---

## Scalability Considerations

### Current (MVP)

- Single Go binary per user/device
- SQLite database per user
- No shared infrastructure needed
- Can deploy on Mac Mini, Render, Fly.io, etc.

### Future Growth Path

**Phase 1: Multi-device for single user**

- Cloud sync service
- Conflict resolution
- Still using SQLite per user

**Phase 2: Team features**

- PostgreSQL for shared data
- Role-based permissions
- Team Spaces

**Phase 3: SaaS platform**

- Multi-tenant architecture
- Usage metering
- Horizontal scaling

---

## Development Workflow

### Local Development

```bash
# Terminal 1: Backend
cd backend
go run cmd/server/main.go

# Terminal 2: Frontend
cd app
flutter run
```

### Testing Strategy

**Backend:**

- Unit tests for business logic
- Integration tests for ACP client
- API tests for endpoints

**Frontend:**

- Widget tests for UI components
- Integration tests for user flows
- Golden tests for visual regression (optional)

**End-to-End:**

- Test message flow from Flutter → Backend → ACP → Backend → Flutter
- Test tool execution flow
- Test permission handling

---

## Deployment Options

### MVP Options

1. **Local only**
   - Run on same machine as user
   - Simplest to start

2. **Mac Mini + Tailscale**
   - Backend on Mac Mini
   - Tailscale for private network
   - Access from mobile via VPN
   - Free, private

3. **Render.com**
   - $7/month for persistent service
   - Public or private
   - Easy deploy from Git

4. **Fly.io**
   - Pay-as-you-go
   - Global edge deployment
   - Good for scaling later

**Recommendation:** Start local, deploy to Mac Mini for mobile testing, move to Render/Fly for beta users.

---

## Open Questions

### Current Feature (Space SQLite)

- [ ] Should spaces support custom table templates?
- [ ] How to handle bulk linking operations?
- [ ] Should spaces be able to auto-subscribe to notes by tag?
- [ ] What's the discovery UX for notes that should be linked?

### General

- [ ] **Authentication for MVP:** API key only vs. account system? (Current: API key only)
- [ ] **Mobile priority:** iOS first, Android first, or both?
- [ ] **Deployment:** Where to host for beta testing? (Current: Local-first)
- [ ] **MCP configuration:** UI for managing MCP servers or file-only?
- [ ] **Context restoration strategy:** Full history vs. summarization?

---

## References

- **ACP Specification:** https://agentclientprotocol.com/
- **MCP Specification:** https://modelcontextprotocol.io/
- **Fiber Docs:** https://docs.gofiber.io/
- **Flutter Docs:** https://docs.flutter.dev/
- **Riverpod Docs:** https://riverpod.dev/

---

## Next Steps

See [ROADMAP.md](ROADMAP.md) for detailed feature queue and timeline.

**Current Focus (Nov 2025):**

1. Implement Space SQLite Knowledge System
   - Backend: SpaceDatabaseService and APIs
   - Frontend: Note linking UI
   - Frontend: Space note browser
   - Integration: Chat references and CLAUDE.md variables

**Future Work:**

- Multi-device sync (E2E encrypted)
- Smart note management (auto-suggest, tagging)
- Knowledge graph visualization
- Custom space templates

---

**Last Updated:** November 1, 2025
**Status:** Active Development - Space SQLite Knowledge System

**Version History:**

- v2.1 (Nov 1, 2025): Added vault-style architecture with configurable paths, Obsidian/Logseq compatibility
- v2.0 (Oct 27, 2025): Added space.sqlite knowledge system architecture
- v1.0 (Oct 20, 2025): Initial architecture with ACP integration
