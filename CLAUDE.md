# CLAUDE.md

**Essential guidance for Claude Code when working with Parachute.**

---

## Current Development Focus

**🚧 Active Feature**: Git-Based Sync Foundation

- **Strategic Pivot** (Nov 5, 2025): Use Git for multi-device sync instead of custom backend
- Git replaces backend sync infrastructure (backend now only for agentic AI)
- Library chosen: `git2dart` (libgit2 bindings for Flutter)
- GitHub Personal Access Tokens for authentication
- Auto-commit after each recording save
- Frontend and backend sync to same Git repository

**See**: [docs/architecture/git-sync-strategy.md](docs/architecture/git-sync-strategy.md)

**Previous Focus** (Space SQLite Knowledge System) is **deferred** until Git sync is stable.
**See**: [docs/features/space-sqlite-knowledge-system.md](docs/features/space-sqlite-knowledge-system.md)

---

## Quick Commands

```bash
# Backend
cd backend && make run          # Start server
cd backend && make test         # Run tests

# Flutter
cd app && flutter run -d macos  # Run app
cd app && flutter test          # Run tests

# Full test suite
./test.sh                       # All tests

# Web testing with Playwright
cd app && flutter run -d chrome --web-port=8090  # Run in Chrome (background)
# Then use Playwright MCP tools to test at http://localhost:8090
```

---

## Project Overview

**Parachute**: Second brain app with Claude AI via Agent Client Protocol (ACP) + integrated voice recorder.

**Stack:** Go backend (Fiber, SQLite) + Flutter frontend (Riverpod)

**Architecture:** `Flutter → HTTP/WebSocket → Go → JSON-RPC → ACP → Claude`

**Data Architecture:**

- All data in configurable vault (default location varies by platform)
- `{vault}/{captures}/` - Voice recordings (subfolder name configurable via Settings)
- `{vault}/{spaces}/` - AI spaces with CLAUDE.md system prompts (subfolder name configurable)
- Each space has `space.sqlite` for structured knowledge management
- **Platform-specific defaults:**
  - macOS/Linux: `~/Parachute/`
  - Android: External storage `/storage/emulated/0/Android/data/.../files/Parachute`
  - iOS: App Documents directory
- **Compatibility:** Works with Obsidian, Logseq, and other markdown vaults

**App Structure:** Three main tabs in bottom navigation:

- **Spaces** - Browse AI spaces and conversations with Claude
- **Recorder** - Voice recording with Omi device support and local Whisper transcription
- **Files** - Browse entire `~/Parachute/` directory structure

---

## CRITICAL Bug Preventions

### ⚠️ #1: Flutter Type Casting (MOST COMMON ERROR)

**NEVER do this:**

```dart
❌ final List<dynamic> data = response.data as List<dynamic>;  // CRASHES!
```

**ALWAYS do this:**

```dart
✅ final Map<String, dynamic> data = response.data as Map<String, dynamic>;
   final List<dynamic> spaces = data['spaces'] as List<dynamic>;
```

**Why:** API endpoints return `{"spaces": [...]}`, not `[...]`

### ⚠️ #2: ACP Protocol Requirements

```go
✅ ProtocolVersion: 1           // int, not string
✅ McpServers: []MCPServer{}    // REQUIRED, even if empty (no omitempty)
```

**Method names:** `initialize`, `session/new`, `session/prompt`, `session/update`
**Parameters:** Use `camelCase` (`sessionId`, `cwd`), not `snake_case`

### ⚠️ #3: Flutter Riverpod

**All widgets using providers MUST be wrapped in `ProviderScope`:**

```dart
runApp(ProviderScope(child: ParachuteApp()));
```

### ⚠️ #4: Authentication

Backend tries `ANTHROPIC_API_KEY` env var, then falls back to `~/.claude/.credentials.json`

### ⚠️ #5: File Paths

- Vault location is configurable and platform-specific (see Data Architecture)
- Use `FileSystemService` to get correct paths - NEVER hardcode paths
- Backend expects absolute paths to vault root
- Frontend may use relative paths in API calls
- Always convert appropriately in backend handlers

### ⚠️ #6: Subfolder Names

- Default subfolder names are `captures/` and `spaces/`
- Users can customize these via Settings → Subfolder Names
- Use `FileSystemService.capturesPath` and `FileSystemService.spacesPath`
- NEVER assume hardcoded subfolder names in code

---

## Git Workflow

**DO NOT commit before user testing!**

1. Make code change
2. Tell user what changed
3. Ask user to test
4. Wait for confirmation
5. Ask permission to commit
6. Commit only after approval

**Why:** Avoids messy history with reverts and bug-filled commits.

---

## Common Quick Fixes

```bash
# Port in use
lsof -ti :8080 | xargs kill

# Flutter clean build
cd app && flutter clean && flutter pub get

# Rebuild backend after Go changes
cd backend && make build

# Check Parachute folder structure
ls -la ~/Parachute/
```

**Flutter package name:** `package:app/...` (not `parachute`)

**WebSocket not streaming?** Check client calls `subscribe(conversationId)` after connecting.

---

## Documentation Structure

### Core Documentation

- **[README.md](README.md)** - Project overview and quick start
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - System design and technical decisions
- **[ROADMAP.md](ROADMAP.md)** - Current focus + future features queue
- **[CLAUDE.md](CLAUDE.md)** - This file - developer guidance

### Feature Documentation

- **[docs/features/space-sqlite-knowledge-system.md](docs/features/space-sqlite-knowledge-system.md)** - Current feature in development
- **[docs/merger-plan.md](docs/merger-plan.md)** - COMPLETED: Recorder integration history

### Development Guides

- **[docs/development/testing.md](docs/development/testing.md)** - Testing guide
- **[docs/development/workflow.md](docs/development/workflow.md)** - Development workflow
- **[docs/architecture/](docs/architecture/)** - ACP, database, WebSocket details

### Component-Specific Docs

- **[backend/CLAUDE.md](backend/CLAUDE.md)** - Backend-specific context
- **[app/CLAUDE.md](app/CLAUDE.md)** - Frontend-specific context
- **[app/lib/features/recorder/CLAUDE.md](app/lib/features/recorder/CLAUDE.md)** - Voice recorder feature

### Recorder & Omi Device

- **[docs/recorder/](docs/recorder/)** - Omi integration docs, testing guides
- **[firmware/](firmware/)** - Omi device firmware source code (Zephyr RTOS)
- **[firmware/README.md](firmware/README.md)** - Build and flash firmware
- **[app/assets/firmware/](app/assets/firmware/)** - Pre-built firmware binaries for OTA

---

## Space CLAUDE.md System Prompt Strategy

Each space has a `CLAUDE.md` file that serves as a **persistent system prompt** for conversations in that space. This is a core part of Parachute's second brain architecture.

### Purpose

- Define the context and purpose of the space
- Guide Claude's behavior and responses
- Reference available knowledge (linked notes, projects, etc.)
- Set expectations for how to use space-specific data

### Dynamic Variables (Planned)

When space.sqlite feature is complete, system prompts will support:

- `{{note_count}}` - Number of linked notes in this space
- `{{recent_tags}}` - Most used tags (last 30 days)
- `{{recent_notes}}` - Last 5 referenced notes
- `{{notes_tagged:X}}` - Count of notes with specific tag
- `{{active_projects}}` - List of projects with status=active

### Example: Project Space

```markdown
# Parachute Development Space

You are assisting with development of Parachute, a second brain app.

## Context

This space tracks development discussions, architecture decisions, and feature planning.

## Available Knowledge

- Linked Notes: {{note_count}} voice recordings and written notes
- Recent Topics: {{recent_tags}}
- Active Features: {{active_projects}}

## Guidelines

- Reference architecture docs when discussing design
- Link new insights to this space for future reference
- Connect ideas across different development discussions
```

### Best Practices

1. **Make context explicit** - State what the space is for
2. **Reference available knowledge** - Show what exists in the space
3. **Set behavioral guidelines** - How should Claude behave here?
4. **Enable discovery** - Encourage Claude to suggest connections
5. **Maintain continuity** - Reference past conversations and notes

**See**: [docs/features/space-sqlite-knowledge-system.md#claude-md-system-prompt-strategy](docs/features/space-sqlite-knowledge-system.md#claude-md-system-prompt-strategy)

---

## Project Status

### ✅ Completed

**Foundation (Sep-Oct 2025)**

- Backend foundation (Go + Fiber + SQLite + ACP)
- Frontend foundation (Flutter + Riverpod)
- Conversation management and streaming
- Omi device integration

**Recorder Integration (Oct 2025)**

- Vault-style folder system with configurable location
- Configurable subfolder names (captures/, spaces/)
- Obsidian/Logseq compatibility
- Local Whisper transcription (on-device models)
- Gemma 2B title generation with HuggingFace integration
- 4-step onboarding flow with model downloads
- Background download support with progress persistence
- File browser with markdown preview

**Local-First Recording (Nov 5, 2025)**

- Live transcription UI with journal-style interface
- Manual pause-based chunking for intentional thought capture
- Instant screen navigation (non-blocking initialization)
- Complete final segment transcription before save
- Recordings load from local filesystem (no backend dependency)
- Markdown + WAV files saved to `~/Parachute/captures/`
- Immediate discard without unnecessary processing

### 🚧 In Progress (Nov 2025)

**Git-Based Sync Foundation (Current)**

- Library research and selection (✅ completed: chose git2dart)
- Proof-of-concept with git2dart
- GitHub PAT integration
- Core sync operations (commit, push, pull)
- Conflict handling basics

### 🔜 Next Up

- Backend Git integration (go-git library)
- Space SQLite Knowledge System (deferred until Git sync stable)
- Smart note management (auto-suggest, tagging)
- Knowledge graph visualization

**See [ROADMAP.md](ROADMAP.md) for full feature queue**

---

## Development Principles

1. **Local-First** - User owns their data, always
2. **Privacy by Default** - No tracking, no ads
3. **Open & Interoperable** - Standard formats (markdown, SQLite)
4. **One Folder** - All data in `~/Parachute/`, portable and open
5. **Cross-Pollination** - Notes link to multiple spaces, ideas flow
6. **Thoughtful AI** - Enhance thinking, don't replace it

---

## Quick Reference: File System Layout

**Note:** Vault location and subfolder names are configurable. Default structure shown below.

```
{vault}/                                # Configurable location (default: ~/Parachute/)
├── {captures}/                         # Configurable name (default: captures/)
│   ├── YYYY-MM-DD_HH-MM-SS.md         # Transcript
│   ├── YYYY-MM-DD_HH-MM-SS.wav        # Audio
│   └── YYYY-MM-DD_HH-MM-SS.json       # Metadata
│
└── {spaces}/                           # Configurable name (default: spaces/)
    ├── space-name/
    │   ├── CLAUDE.md                   # System prompt
    │   ├── space.sqlite                # 🆕 Knowledge metadata
    │   └── files/                      # Space-specific files
    │
    └── another-space/
        ├── CLAUDE.md
        ├── space.sqlite
        └── files/
```

**Customization:** Users can:

- Change vault location via Settings → Parachute Folder → Change Location
- Rename `captures/` and `spaces/` subfolders via Settings → Subfolder Names
- Point vault to existing Obsidian/Logseq vaults for interoperability

---

## First-Time Setup (Onboarding)

Parachute includes a 4-step onboarding flow that runs on first launch:

### Step 1: Welcome

- Explains vault-based architecture
- Shows Obsidian/Logseq compatibility
- Displays current vault location

### Step 2: Whisper Model Setup

- Download local Whisper model for transcription
- Three model sizes: Tiny (75 MB), Base (142 MB), Small (466 MB)
- Users can skip and download later
- Background downloads supported

### Step 3: Gemma Model Setup (Optional)

- Download Gemma 2B model for AI-powered title generation (5.4 GB)
- **Requires HuggingFace Token** (models are gated)
- Token input UI with show/hide toggle
- Users can skip if not using AI features
- Background downloads supported

### Step 4: Advanced Features

- Explains Omi device integration
- Can be enabled later in Settings

### Implementation Details

- Onboarding state stored in `SharedPreferences` (`parachute_has_seen_onboarding`)
- Download progress persists across screens (can start in onboarding, monitor in Settings)
- All downloads are optional and can continue in background
- HuggingFace token saved securely via `StorageService`

**Code locations:**

- `app/lib/features/onboarding/screens/onboarding_flow.dart` - Main coordinator
- `app/lib/features/onboarding/screens/steps/` - Individual step widgets
- `app/lib/features/settings/screens/settings_screen.dart` - Post-onboarding model management

---

## When Working on Features

1. **Read the feature doc first** - Check `docs/features/` for detailed specs
2. **Update todos** - Use the TodoWrite tool to track implementation steps
3. **Follow the plan** - Feature docs have implementation phases
4. **Test incrementally** - Don't build everything before testing
5. **Update docs** - Keep feature docs current as you learn
6. **Ask before committing** - Follow git workflow above

---

## Need Help?

- **Architecture questions?** → [ARCHITECTURE.md](ARCHITECTURE.md)
- **What's next?** → [ROADMAP.md](ROADMAP.md)
- **Current feature details?** → [docs/features/](docs/features/)
- **Backend specifics?** → [backend/CLAUDE.md](backend/CLAUDE.md)
- **Frontend specifics?** → [app/CLAUDE.md](app/CLAUDE.md)

Read these files as needed for specific tasks. Context is your friend!

---

**Last Updated**: November 5, 2025
**Next Review**: After Git Sync Phase 1 completion
