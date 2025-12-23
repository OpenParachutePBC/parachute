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
├── app/                      # Flutter mobile/desktop app
│   ├── CLAUDE.md            # App-specific development guide
│   ├── lib/                 # Dart source code
│   └── pubspec.yaml         # Flutter dependencies
└── agent/                    # Node.js agent backend
    ├── claude.md            # Agent-specific development guide
    ├── lib/                 # JavaScript source
    ├── server.js            # Express API server
    └── package.json         # Node dependencies
```

**Key Files (start here when exploring):**
- `app/CLAUDE.md` - Flutter app development patterns, providers, UI
- `agent/claude.md` - Backend API, session management, Claude SDK integration

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
                    │  ├── agent-sessions/     │  ← Chat history (markdown)
                    │  ├── captures/            │  ← Voice recordings
                    │  ├── .agents/             │  ← Agent definitions
                    │  └── AGENTS.md            │  ← Your personal context
                    │                           │
                    │  (synced via Syncthing)   │
                    └───────────────────────────┘
```

---

## Component Relationship

### Current Architecture: Client-Server

| Component | Role | Location |
|-----------|------|----------|
| **App (Flutter)** | UI client, voice recording, local storage | Runs on each device |
| **Agent (Node.js)** | AI orchestration, session management | Single server instance |
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

### App (Flutter)
```bash
cd app
flutter pub get                    # Install dependencies
flutter run -d macos               # Run on macOS
flutter run -d android             # Run on Android
flutter analyze                    # Check for issues
flutter test                       # Run tests
```

### Agent (Node.js)
```bash
cd agent
npm install                        # Install dependencies
npm start                          # Start server (port 3333)
npm run dev                        # Start with auto-reload
npm test                           # Run tests
VAULT_PATH=~/Parachute npm start   # Point to your vault
```

### Full Stack Development
```bash
# Terminal 1: Start agent
cd agent && VAULT_PATH=~/Parachute npm run dev

# Terminal 2: Run app
cd app && flutter run -d macos
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

Stored in `{vault}/agent-sessions/*.md`:

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

### Captures (Voice Recordings)

Stored in `{vault}/captures/YYYY-MM/`:

```
2025-12/
├── 2025-12-20_14-30-22.md     # Transcript
├── 2025-12-20_14-30-22.opus   # Audio file
└── 2025-12-20_14-30-22.json   # Metadata
```

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

- **Import Old Chats** - Claude/ChatGPT history import with onboarding flow
- **Session Continuation** - Continued sessions load prior messages correctly
- **Date Sorting** - Fixed timezone bug for Today/This Week grouping
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

1. **Agent**: Add route in `agent/server.js`
2. **App**: Add method in `app/lib/features/chat/services/chat_service.dart`
3. **App**: Add provider in `app/lib/features/chat/providers/chat_providers.dart`
4. Update CLAUDE.md files with new endpoint documentation

### Modifying Session Storage Format

1. **Agent**: Update `agent/lib/session-manager.js`
2. **App**: Update `app/lib/features/chat/models/chat_session.dart`
3. Consider migration path for existing sessions

### Adding App Feature Flags

1. **Service**: `app/lib/core/services/feature_flags_service.dart`
2. **Providers**: `app/lib/core/providers/feature_flags_provider.dart`
3. **UI**: Settings screen in `app/lib/features/settings/`

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

1. Check `agent-sessions/` directory has markdown files
2. Verify session IDs match between app and server
3. Server restart clears in-memory session cache (but markdown persists)

### Voice Recording Issues

1. Check microphone permissions in system settings
2. Verify transcription model is downloaded
3. Check `captures/` directory for saved files

---

## Related Documentation

| Path | Description |
|------|-------------|
| `app/CLAUDE.md` | Flutter app patterns, providers, UI |
| `app/lib/features/recorder/CLAUDE.md` | Voice recording feature details |
| `agent/claude.md` | Agent API, sessions, Claude SDK |
| `agent/DESIGN.md` | Architectural decisions and rationale |

---

**Last Updated**: December 22, 2025
