# Parachute - Multi-Repo Development Guide

**Essential guidance for Claude Code when working with the Parachute ecosystem.**

This is the **coordinator repo** with git submodules. Each module has its own repository:
- [parachute-daily](https://github.com/OpenParachutePBC/parachute-daily) - Local voice journaling
- [parachute-chat](https://github.com/OpenParachutePBC/parachute-chat) - AI chat assistant
- [parachute-base](https://github.com/OpenParachutePBC/parachute-base) - Backend server

---

## Vision & Philosophy

**Parachute** is open & interoperable extended mind technology—a connected tool for connected thinking.

We build local-first, voice-first AI tooling that gives people agency over their digital minds. Technology should support natural human cognition, not force us into unnatural patterns.

**Core Principles:**
- **Local-First** - Your data stays on your devices; you control what goes to the cloud
- **Voice-First** - More natural than typing; meets people where they actually think
- **Open & Interoperable** - Standard formats (markdown, JSONL), works with Obsidian/Logseq
- **Prosocial, Not Surveillance** - You control what's captured and where it goes
- **Thoughtful AI** - Enhance thinking, don't replace it

---

## Repository Structure

```
parachute/                     # Coordinator repo (you are here)
├── CLAUDE.md                 # This file - cross-repo guidance
├── .gitmodules               # Submodule configuration
├── scripts/                  # Utility scripts
│   └── install-android.sh    # Android deployment with data preservation
├── daily/                    # Submodule → parachute-daily
├── chat/                     # Submodule → parachute-chat
└── base/                     # Submodule → parachute-base
    ├── parachute/            # Python server (FastAPI) - primary
    ├── tests/                # Python tests
    ├── pyproject.toml        # Python config
    └── node/                 # Node.js server (legacy)
```

**Individual Repos (source of truth):**
- `parachute-daily` - Standalone voice journaling (Flutter)
- `parachute-chat` - AI chat assistant (Flutter, requires base)
- `parachute-base` - Backend server (Python primary, Node.js legacy in `node/`)

**Cloning with submodules:**
```bash
git clone --recurse-submodules https://github.com/OpenParachutePBC/parachute.git

# Or if already cloned:
git submodule update --init --recursive
```

**Working with submodules:**
```bash
# Pull latest from all submodules
git submodule update --remote

# Push changes in a submodule (work in the submodule directory)
cd daily
git add . && git commit -m "..." && git push

# Update parent to track new submodule commit
cd ..
git add daily && git commit -m "Update daily submodule"
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USER DEVICES                                    │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │  iPhone/Android │  │  macOS/Windows  │  │   Obsidian      │             │
│  │  (Flutter App)  │  │  (Flutter App)  │  │   (Plugin)      │             │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘             │
│           │                    │                    │                       │
│           └────────────────────┼────────────────────┘                       │
│                                ▼                                            │
│                    ┌───────────────────────┐                                │
│                    │    HTTP/SSE Client    │                                │
└────────────────────┴───────────┬───────────┴────────────────────────────────┘
                                 │
                                 ▼ (port 3333)
┌────────────────────────────────────────────────────────────────────────────┐
│                         AGENT SERVER (one instance)                         │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                     FastAPI Server (Python)                           │  │
│  │                                                                       │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │  │
│  │  │ /api/chat/*  │  │ /api/agents  │  │ /api/captures│               │  │
│  │  └──────┬───────┘  └──────────────┘  └──────────────┘               │  │
│  │         │                                                            │  │
│  │         ▼                                                            │  │
│  │  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐      │  │
│  │  │ Orchestrator │──────│ Claude SDK   │      │ Session Mgr  │      │  │
│  │  │              │      │ (API calls)  │      │ (markdown)   │      │  │
│  │  └──────────────┘      └──────────────┘      └──────────────┘      │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                    │                                        │
└────────────────────────────────────┼────────────────────────────────────────┘
                                     │
                                     ▼
                    ┌───────────────────────────┐
                    │   Knowledge Vault (local) │
                    │                           │
                    │  ~/Parachute/             │
                    │  ├── Daily/               │  ← Parachute Daily module
                    │  │   ├── journals/        │  ← Daily entries (markdown)
                    │  │   ├── assets/          │  ← Audio, photos
                    │  │   └── index.db         │  ← SQLite RAG index
                    │  ├── Chat/                │  ← Parachute Chat module
                    │  │   ├── sessions/        │  ← Chat history (markdown)
                    │  │   ├── contexts/        │  ← Personal context files
                    │  │   └── assets/          │  ← Generated images, audio
                    │  ├── .agents/             │  ← Agent definitions
                    │  └── CLAUDE.md            │  ← System prompt override
                    │                           │
                    │  (synced via Syncthing)   │
                    └───────────────────────────┘
```

---

## Component Relationship

### Current Architecture: Modular Ecosystem

| Component | Role | Location |
|-----------|------|----------|
| **Daily (Flutter)** | Voice journaling, local-first, standalone | Runs on each device |
| **Chat (Flutter)** | AI chat assistant, requires backend | Runs on each device |
| **Base (Python)** | AI orchestration, session management, MCP | Single server instance |
| **Vault** | Data storage (markdown files) | Local + Syncthing sync |

### Communication Flow

1. **User speaks/types** → App records/captures
2. **App sends message** → `POST /api/chat/stream` to Agent
3. **Agent orchestrates** → Claude SDK for AI, saves to vault markdown
4. **SSE stream back** → Real-time updates to App UI
5. **Syncthing syncs** → Vault changes replicate to other devices

### Key Design Decisions

- **One Agent server, many App clients** - Simplifies orchestration
- **Vault as source of truth** - Markdown files are portable, human-readable
- **Sessions stored as markdown** - Can be read/edited in any text editor
- **Agent can operate in any cwd** - Chat with external codebases

---

## Quick Commands

### Daily (Flutter - Local-first journaling)
```bash
cd daily
flutter pub get                    # Install dependencies
flutter run -d macos               # Run on macOS
flutter run -d android             # Run on Android
flutter analyze                    # Check for issues
```

### Chat (Flutter - AI assistant)
```bash
cd chat
flutter pub get                    # Install dependencies
flutter run -d macos               # Run on macOS
flutter run -d android             # Run on Android
flutter analyze                    # Check for issues
```

### Base (Python - Backend server)

**Recommended: Use the CLI script**
```bash
cd base
./parachute.sh setup   # One-time: create venv, install deps
./parachute.sh start   # Start server in background
./parachute.sh stop    # Stop server
./parachute.sh restart # Restart server
./parachute.sh status  # Check server status
./parachute.sh logs    # Tail server logs
./parachute.sh help    # Show all commands
```

**As a macOS service (recommended for development)**
```bash
cd base
./parachute.sh service-install  # Install as launchd service (autostarts at login)
./parachute.sh service-restart  # Restart after code changes
./parachute.sh service-stop     # Stop the service
```

**Manual setup (first time only)**
```bash
cd base
python -m venv venv                # Create virtual environment
source venv/bin/activate           # Activate venv (macOS/Linux)
pip install -r requirements.txt    # Install dependencies
```

**Manual start (alternative to CLI)**
```bash
cd base && source venv/bin/activate
VAULT_PATH=~/Parachute python -m parachute.server  # Direct start
# or
python -m supervisor.main          # With supervisor (recommended)
```

### Base/Node (Node.js - Legacy backend)
```bash
cd base/node
npm install                        # Install dependencies
npm start                          # Start server (port 3333)
npm run dev                        # Start with auto-reload
npm test                           # Run tests
```

### Full Stack Development (Chat + Base)

**Option 1: Using the service (recommended)**
```bash
# One-time setup
cd base && ./parachute.sh service-install

# Then just run the chat app - server is always running
cd chat && flutter run -d macos

# After base code changes
cd base && ./parachute.sh service-restart
```

**Option 2: Manual terminals**
```bash
# Terminal 1: Start Python base server
cd base && source venv/bin/activate && VAULT_PATH=~/Parachute python -m parachute.server

# Terminal 2: Run Chat app
cd chat && flutter run -d macos
```

### Android Deployment
```bash
# Install to Android device (preserves app data)
./scripts/install-android.sh              # Install both apps
./scripts/install-android.sh chat         # Install only chat
./scripts/install-android.sh daily        # Install only daily
./scripts/install-android.sh chat daylight:35859  # Specific device

# The script handles:
# - Multiple device selection (prompts if >1 connected)
# - Network device auto-connect (e.g., daylight:35859)
# - Data preservation on reinstall (-r flag)
```

---

## Configuration

### Agent Server URL

The app connects to the agent at `http://localhost:3333` by default. To change:

1. **In App Settings UI**: Go to Settings → AI Chat → Server URL
2. **For remote server**: Use your server's hostname (e.g., `http://mbp:3333`)

**Important**: Changes take effect immediately (no restart needed).

### Environment Variables (Agent)

| Variable | Default | Description |
|----------|---------|-------------|
| `VAULT_PATH` | `./sample-vault` | Path to your knowledge vault |
| `PORT` | `3333` | Server port |
| `HOST` | `0.0.0.0` | Bind address (0.0.0.0 for network access) |

---

## Data Model

### Sessions (Chat History)

Sessions use a **lightweight pointer architecture**:
- Markdown files contain only frontmatter metadata (no message content)
- SDK JSONL files at `~/.claude/projects/` are the source of truth for messages
- This enables easy future migration to SQLite

Stored in `{vault}/Chat/sessions/*.md`:

```markdown
---
sdk_session_id: "abc-123-def"
title: "Project Discussion"
created_at: "2025-12-20T10:30:00Z"
last_accessed: "2025-12-20T11:00:00Z"
archived: false
message_count: 12
source: "parachute"
---
```

For imported Claude Code sessions:
```markdown
---
sdk_session_id: "claude-code-session-xyz"
title: "Parachute Development"
working_directory: "/Users/name/project"
model: "claude-opus-4-5-20250514"
source: "claude-code"
message_count: 45
---
```

### Assets (Audio, Images)

Stored in `{vault}/assets/YYYY-MM/`:

```
assets/
└── 2025-12/
    ├── 2025-12-20_14-30-22.opus   # Audio file
    ├── gen_abc123.png             # Generated image
    └── photo_xyz789.jpg           # Captured photo
```

Audio transcripts are embedded in Daily journal entries or Chat sessions.

### Agents (AI Personas)

Stored in `{vault}/.agents/*.md`:

```markdown
---
name: Vault Agent
description: Your personal knowledge assistant
model: claude-sonnet-4-20250514
---

You are a helpful assistant with access to the user's vault...
```

---

## Current Development Focus

### Recently Completed

- **Claude Code Session Import** - Import sessions from `~/.claude/projects/` with lightweight markdown pointers
- **Model Display** - Shows which model (Opus 4.5, Sonnet 4, etc.) is being used in the chat app bar
- **Graceful Abort Handling** - Stop button no longer crashes server; partial progress saved
- **Account Default Model** - No hardcoded model; uses account's default, displays actual model used
- **Flat Session Structure** - Simplified `Chat/sessions/` without subfolders
- **Stability Fixes (Phase 4)** - SSE heartbeat, session cleanup, request timeouts, recursion protection
- **Session Context Bug Fix** - Fixed `state.sessionId` not updating, causing context loss
- **SSE Disconnect Fix** - Changed `req.on('close')` to `res.on('close')` for proper client detection
- **E2E Test Suite** - 21 comprehensive tests for sessions, streaming, and error handling
- **Performance Tracking** - File-based tracing with API endpoints for Claude Code access
- **Streaming Throttle** - Reduced UI updates during streaming (50ms throttle)
- **Import Old Chats** - Claude/ChatGPT history import with onboarding flow
- **Session Continuation** - Continued sessions load prior messages correctly
- **CLAUDE.md** - Personal context template system

### Priority Issues

1. **Voice Input for Chat** - Use transcription to fill chat text box
2. **Audio File Organization** - Standardize with para:uuid and year-month folders
3. **Offline Mode** - Show local sessions when server is unreachable

### Future Considerations

- **RAG Indexing** - Full-text search across vault (vault-search.js foundation exists)
- **Multiple Agent Servers** - Each client could run its own server
- **iOS Support** - Full feature parity with macOS/Android

---

## Common Tasks

### Adding a New API Endpoint

1. **Base**: Add route in `base/server.js`
2. **Chat**: Add method in `chat/lib/features/chat/services/chat_service.dart`
3. **Chat**: Add provider in `chat/lib/features/chat/providers/chat_providers.dart`
4. Update CLAUDE.md files with new endpoint documentation

### Modifying Session Storage Format

1. **Base**: Update `base/parachute/core/session_manager.py`
2. **Chat**: Update `chat/lib/features/chat/models/chat_session.dart`
3. Consider migration path for existing sessions

### Adding Feature Flags (Chat App)

1. **Service**: `chat/lib/core/services/feature_flags_service.dart`
2. **Providers**: `chat/lib/core/providers/feature_flags_provider.dart`
3. **UI**: Settings screen in `chat/lib/features/settings/`

---

## Git Workflow

**CRITICAL: DO NOT commit or push without user approval!**

1. Make code changes
2. Tell user what changed
3. Ask user to test
4. Wait for confirmation
5. **Ask permission to commit**
6. **Ask permission to push**

Always use `git --no-pager` to prevent pager blocking output.

### Submodule Workflow

**IMPORTANT: After pushing changes to any submodule, always update the parent repo!**

When you commit and push to a submodule (daily, chat, or base):

```bash
# 1. Commit and push in the submodule
cd base  # or chat, daily
git add . && git commit -m "..." && git push

# 2. Update parent repo to track new submodule commit
cd /Users/unforced/Parachute/Build/repos/parachute
git add base  # or chat, daily (whichever changed)
git commit -m "Update base submodule"
git push
```

This ensures the parent repo always points to the correct submodule commits, so `git clone --recurse-submodules` works correctly for others.

---

## Debugging Tips

### App Not Connecting to Agent

1. Check agent is running: `curl http://localhost:3333/api/health`
2. Verify URL in App Settings matches server
3. Check server logs for errors: `npm run dev` shows request logs
4. Ensure firewall allows port 3333

### Restarting the Server

**IMPORTANT: Never restart the server in the middle of a user's chat session!**

When code changes require a server restart:
1. **Inform the user** that a restart is needed
2. **Ask permission** before restarting
3. **Wait for user confirmation** - they may be in the middle of an important conversation

**Option 1: CLI Script (recommended)**
```bash
./server.sh restart    # Graceful restart
./server.sh status     # Verify it's running
```

**Option 2: In-App Control**
- Go to Settings → Advanced → Server Management
- Click "Restart" button
- Requires supervisor to be running (`./server.sh supervisor`)

**Option 3: Manual restart**
```bash
lsof -ti:3333 | xargs kill -9 2>/dev/null
cd base && source venv/bin/activate && VAULT_PATH=~/Parachute python -m parachute.server &
```

### Chat History Not Loading

1. Check `Chat/sessions/` directory has markdown files
2. Verify session IDs match between app and server
3. Server restart clears in-memory session cache (but markdown persists)

### Voice Recording Issues

1. Check microphone permissions in system settings
2. Verify transcription model is downloaded
3. Check `assets/` directory for saved audio files

### Performance Issues

1. **Check performance data**: `curl http://localhost:3333/api/perf/report`
2. **Get slow events only**: `curl "http://localhost:3333/api/perf/events?slow=true"`
3. **Filter by operation**: `curl "http://localhost:3333/api/perf/events?name=MessageBubble.build"`
4. Performance data written to `{vault}/.parachute/perf/`

---

## Testing

### Base Server E2E Tests
```bash
cd base
npm run test:e2e              # Run against current vault
npm run test:e2e:isolated     # Run with temp test vault (recommended)
```

### Chat App Tests
```bash
cd chat
flutter test                  # Run all tests
flutter analyze               # Check for issues
```

### Daily App Tests
```bash
cd daily
flutter test                  # Run all tests
flutter analyze               # Check for issues
```

---

## Related Documentation

| Path | Description |
|------|-------------|
| `daily/CLAUDE.md` | Daily app - local-first voice journaling |
| `chat/CLAUDE.md` | Chat app - AI assistant with Riverpod patterns |
| `base/README.md` | Python base server - API, sessions, Claude SDK |
| `base/node/claude.md` | Node.js base server (legacy) |
| `base/node/DESIGN.md` | Architectural decisions and rationale |

---

**Last Updated**: January 2, 2026
