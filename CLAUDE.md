# Parachute - Monorepo Development Guide

**Essential guidance for Claude Code when working with the Parachute monorepo.**

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

## Monorepo Structure

```
parachute/                     # This monorepo (you are here)
├── CLAUDE.md                 # This file - overall guidance
├── daily/                    # Parachute Daily - local voice journaling
│   ├── lib/                 # Dart source code
│   └── pubspec.yaml         # Flutter dependencies
├── chat/                     # Parachute Chat - AI assistant app
│   ├── lib/                 # Dart source code
│   └── pubspec.yaml         # Flutter dependencies
└── base/                     # Parachute Base - backend server
    ├── claude.md            # Server-specific development guide
    ├── lib/                 # JavaScript source
    ├── server.js            # Express API server
    └── package.json         # Node dependencies
```

**Key Files (start here when exploring):**
- `daily/` - Local-first voice journaling app (Alpha priority, runs standalone)
- `chat/` - AI chat assistant (requires base server)
- `base/claude.md` - Backend API, session management, Claude SDK integration

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
│  │                     Express Server (server.js)                        │  │
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
                    │  └── AGENTS.md            │  ← System prompt override
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
| **Base (Node.js)** | AI orchestration, session management, MCP | Single server instance |
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

### Base (Node.js - Backend server)
```bash
cd base
npm install                        # Install dependencies
npm start                          # Start server (port 3333)
npm run dev                        # Start with auto-reload
npm test                           # Run tests
VAULT_PATH=~/Parachute npm start   # Point to your vault
```

### Full Stack Development (Chat + Base)
```bash
# Terminal 1: Start base server
cd base && VAULT_PATH=~/Parachute npm run dev

# Terminal 2: Run Chat app
cd chat && flutter run -d macos
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

Stored in `{vault}/Chat/sessions/*.md`:

```markdown
---
session_id: abc-123-def
agent: .agents/vault-agent.md
title: "Project Discussion"
created_at: 2025-12-20T10:30:00Z
sdk_session_id: claude-session-xyz
---

### User | 10:30 AM
First message from user

### Assistant | 10:30 AM
Response from assistant
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

- **Stability Fixes (Phase 4)** - SSE heartbeat, session cleanup, request timeouts, recursion protection
- **Session Context Bug Fix** - Fixed `state.sessionId` not updating, causing context loss
- **SSE Disconnect Fix** - Changed `req.on('close')` to `res.on('close')` for proper client detection
- **E2E Test Suite** - 21 comprehensive tests for sessions, streaming, and error handling
- **Performance Tracking** - File-based tracing with API endpoints for Claude Code access
- **Streaming Throttle** - Reduced UI updates during streaming (50ms throttle)
- **Import Old Chats** - Claude/ChatGPT history import with onboarding flow
- **Session Continuation** - Continued sessions load prior messages correctly
- **AGENTS.md** - Personal context template system

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

1. **Base**: Update `base/lib/session-manager-v2.js`
2. **Chat**: Update `chat/lib/features/chat/models/chat_session.dart`
3. Consider migration path for existing sessions (see `base/scripts/migrate-vault.js`)

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

---

## Debugging Tips

### App Not Connecting to Agent

1. Check agent is running: `curl http://localhost:3333/api/health`
2. Verify URL in App Settings matches server
3. Check server logs for errors: `npm run dev` shows request logs
4. Ensure firewall allows port 3333

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
| `base/claude.md` | Base server - API, sessions, Claude SDK |
| `base/DESIGN.md` | Architectural decisions and rationale |

---

**Last Updated**: December 29, 2025
