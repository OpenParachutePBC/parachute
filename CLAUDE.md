# CLAUDE.md

**Essential guidance for Claude Code when working with Parachute.**

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

**Key Insight:** "The AI that knows you best wins. But people won't share their real context with tools they don't trust. Local-first + voice-first = more honest, richer context = better AI = stronger lock-in through value, not coercion."

---

## Current Development Focus

**🎯 Status**: Stability & reliability focus (Nov 24, 2025)

**Primary Platforms:** macOS and Android (iOS coming soon with additional team members)

### Recently Completed

**Reliability Improvements (Nov 20-24, 2025)**: ✅ Complete
- Critical memory leak fixes and dead code removal
- Stylistic lint fixes
- Async bug fixes and race condition prevention
- GitSync initialization race condition fix
- Standardized FileSystemService usage

**Auto-Pause Voice Recording (Nov 10, 2025)**: ✅ Complete

Automatic silence detection with intelligent noise suppression:

- ✅ VAD (Voice Activity Detection) - RMS energy-based speech detection
- ✅ SmartChunker - Auto-segment on 1s silence
- ✅ OS-level noise suppression (echoCancel, autoGain, noiseSuppress)
- ✅ High-pass filter (80Hz cutoff) - Removes low-frequency rumble
- ✅ Visual debug overlay with real-time audio graphs
- ✅ 116 comprehensive tests covering all components

**Audio Pipeline**: `Mic → OS Suppression → High-Pass Filter → VAD → SmartChunker → Whisper`

**Recording UI Polish (Nov 6-13, 2025)**: ✅ Complete

- ✅ Context field with voice input (record → transcribe → insert)
- ✅ Background transcription service (continues when app backgrounded)
- ✅ Immediate recording persistence (no data loss on exit)
- ✅ Google Keep-inspired notes grid/list view

**Git Sync (Nov 6-17, 2025)**: ✅ Complete

- Local-first architecture with Git-based sync to GitHub
- Auto-commit on recording save, periodic background sync
- Native Git on macOS/Android (iOS pending)

### Next Up

**Sphere Management** - Organize captures into themed spheres with JSONL metadata

**Focus Areas:**
- Reliability and stability improvements
- Sphere linking and organization
- Export/integration with external AI tools (ChatGPT, Claude, etc.)

**Deferred:** AI chat features (backend-dependent) - will return once core capture is rock-solid

---

## Quick Commands

```bash
# Flutter (primary development)
cd app && flutter run -d macos  # Run on macOS
cd app && flutter run -d chrome --web-port=8090  # Run in browser
cd app && flutter test          # Run tests

# Full test suite
./test.sh                       # All tests

# Backend (optional - for AI chat features)
cd backend && make run          # Start server
cd backend && make test         # Run tests
```

---

## Project Overview

**Parachute**: Voice-first capture tool that exports to wherever you work. We don't compete with your note system; we feed it.

**Stack:** Flutter app (Riverpod) with optional Go backend for AI features

**Architecture:** Local-first with Git sync to GitHub

**Data Architecture:**

- All data in configurable vault (default location varies by platform)
- `{vault}/{captures}/` - Voice recordings (subfolder name configurable)
- `{vault}/{spheres}/` - Themed spheres with CLAUDE.md system prompts
- **Platform-specific defaults:**
  - macOS/Linux: `~/Parachute/`
  - Android: External storage `/storage/emulated/0/Android/data/.../files/Parachute`
  - iOS: App Documents directory
- **Compatibility:** Works with Obsidian, Logseq, and other markdown vaults

**App Structure:** Three main tabs in bottom navigation:

- **Spheres** - Organize and browse themed knowledge spheres
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
   final List<dynamic> spheres = data['spheres'] as List<dynamic>;
```

**Why:** API endpoints return `{"spheres": [...]}`, not `[...]`

### ⚠️ #2: ACP Protocol Requirements (Backend only)

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

### ⚠️ #4: Authentication (Backend only)

Backend tries `ANTHROPIC_API_KEY` env var, then falls back to `~/.claude/.credentials.json`

### ⚠️ #5: File Paths

- Vault location is configurable and platform-specific (see Data Architecture)
- Use `FileSystemService` to get correct paths - NEVER hardcode paths
- Always use `FileSystemService.capturesPath` and `FileSystemService.spheresPath`
- NEVER assume hardcoded subfolder names in code

### ⚠️ #6: Git Sync Race Conditions

- GitSync initialization is async - don't assume it's ready immediately
- Check `isInitialized` before performing Git operations
- Use proper state management for sync status

---

## Git Workflow

**🚨 CRITICAL: DO NOT commit or push without user approval! 🚨**

1. Make code change
2. Tell user what changed
3. Ask user to test
4. Wait for confirmation
5. **Ask permission to commit**
6. Commit only after approval
7. **Ask permission to push**
8. Push only after approval

**Why:** Avoids messy history with reverts and bug-filled commits.

**⚠️ WARNING**: Never auto-commit or auto-push. Always wait for explicit user approval for BOTH actions.

**Important:** Always use `git --no-pager` when running git commands in bash (prevents pager from blocking output).

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

### Development Guides

- **[docs/development/testing.md](docs/development/testing.md)** - Testing guide
- **[docs/development/workflow.md](docs/development/workflow.md)** - Development workflow
- **[docs/architecture/](docs/architecture/)** - ACP, database, WebSocket details

### Component-Specific Docs

- **[backend/CLAUDE.md](backend/CLAUDE.md)** - Backend-specific context (AI chat features)
- **[app/CLAUDE.md](app/CLAUDE.md)** - Frontend-specific context
- **[app/lib/features/recorder/CLAUDE.md](app/lib/features/recorder/CLAUDE.md)** - Voice recorder feature

### Recorder & Omi Device

- **[docs/recorder/](docs/recorder/)** - Omi integration docs, testing guides
- **[firmware/](firmware/)** - Omi device firmware source code (Zephyr RTOS)
- **[app/assets/firmware/](app/assets/firmware/)** - Pre-built firmware binaries for OTA

---

## Sphere System (formerly "Spaces")

Spheres are themed knowledge containers. Each sphere has a `CLAUDE.md` file that serves as a **persistent system prompt** for AI conversations in that sphere.

### Why "Spheres"?

The term "sphere" speaks to the holistic, interconnected nature of knowledge—ideas don't live in flat boxes but in overlapping domains of thought. A capture can exist in multiple spheres simultaneously.

### Sphere Structure

```
{vault}/{spheres}/
├── work/
│   ├── CLAUDE.md           # System prompt for this sphere
│   ├── sphere.jsonl        # Linked captures and metadata
│   └── files/              # Sphere-specific files
│
└── personal/
    ├── CLAUDE.md
    ├── sphere.jsonl
    └── files/
```

### CLAUDE.md System Prompt

Each sphere's CLAUDE.md defines context for AI interactions:

```markdown
# Work Sphere

You are assisting with professional projects and work-related thinking.

## Context
This sphere contains work discussions, project planning, and professional development.

## Guidelines
- Keep responses focused and actionable
- Reference past discussions when relevant
- Suggest connections between related projects
```

### sphere.jsonl Format

Metadata stored as JSON Lines (one JSON object per line):

```jsonl
{"type":"link","capture":"2025-11-24_10-30-00","linkedAt":"2025-11-24T10:35:00Z"}
{"type":"tag","name":"project-alpha","addedAt":"2025-11-24T10:36:00Z"}
{"type":"note","content":"Key insight about...","createdAt":"2025-11-24T10:40:00Z"}
```

**Why JSONL over SQLite:**
- Human-readable and git-friendly
- No binary files to merge
- Simple append-only operations
- Easy to parse and debug

---

## Project Status

### ✅ Completed

**Foundation (Sep-Oct 2025)**

- Flutter app with Riverpod state management
- Backend foundation (Go + Fiber) - optional for AI features
- Omi device integration

**Recorder Integration (Oct 2025)**

- Vault-style folder system with configurable location
- Obsidian/Logseq compatibility
- Local Whisper transcription (on-device models)
- Gemma 2B title generation
- 3-step onboarding flow

**Local-First Recording (Nov 5, 2025)**

- Live transcription UI with journal-style interface
- Auto-pause VAD-based chunking
- Recordings load from local filesystem
- Markdown + audio files saved to vault

**Git Sync (Nov 6-17, 2025)**

- Native Git on macOS and Android
- GitHub OAuth integration
- Auto-commit on save, periodic background sync
- iOS support pending

**Reliability (Nov 20-24, 2025)**

- Memory leak fixes
- Race condition prevention
- Code cleanup and standardization

### 🔜 Next Up

- Sphere management and organization
- Export integrations (to ChatGPT, Claude, etc.)
- iOS Git support
- Cross-sphere knowledge linking

### 🔮 Future

- Personalized local LLM with deep personal context
- MCP integrations for connecting to other tools
- Knowledge graph visualization

---

## Development Principles

1. **Local-First** - User owns their data, always
2. **Voice-First** - Natural capture where thinking actually happens
3. **Open & Interoperable** - Standard formats (markdown, JSONL), no lock-in
4. **Privacy by Default** - No tracking, no ads, you control what leaves your device
5. **Prosocial** - Technology that serves human cognition, not extracts from it
6. **Cross-Pollination** - Ideas flow between spheres, nothing siloed

---

## Quick Reference: File System Layout

**Note:** Vault location and subfolder names are configurable. Default structure shown below.

```
{vault}/                                # Configurable location (default: ~/Parachute/)
├── {captures}/                         # Configurable name (default: captures/)
│   ├── YYYY-MM-DD_HH-MM-SS.md         # Transcript
│   ├── YYYY-MM-DD_HH-MM-SS.opus       # Audio (compressed)
│   └── YYYY-MM-DD_HH-MM-SS.json       # Metadata
│
└── {spheres}/                          # Configurable name (default: spheres/)
    ├── sphere-name/
    │   ├── CLAUDE.md                   # System prompt
    │   ├── sphere.jsonl                # Linked captures & metadata
    │   └── files/                      # Sphere-specific files
    │
    └── another-sphere/
        ├── CLAUDE.md
        ├── sphere.jsonl
        └── files/
```

**Customization:** Users can:

- Change vault location via Settings → Parachute Folder → Change Location
- Rename `captures/` and `spheres/` subfolders via Settings → Subfolder Names
- Point vault to existing Obsidian/Logseq vaults for interoperability

---

## First-Time Setup (Onboarding)

Parachute includes a 3-step onboarding flow that runs on first launch:

### Step 1: Welcome

- Explains vault-based architecture
- Shows Obsidian/Logseq compatibility
- Displays current vault location

### Step 2: Transcription Setup (Parakeet v3)

- Shows Parakeet v3 model info (~500 MB on Apple, ~640 MB on Android)
- Models download automatically on first use
- Users can optionally download immediately or skip

### Step 3: Title Generation Setup

- Choose title generation mode: API (Gemini), Local (Gemma), or Disabled
- Download Gemma models for offline title generation
- Users can skip and configure later in Settings

---

## Session Workflow

Use structured sessions to maintain focus and ensure quality across context windows.

### Session Commands

- **`/session-start <objective>`** - Initialize a session with a clear goal
- **`/session-check`** - Mid-session coherence check
- **`/session-end`** - Clean shutdown and handoff

### Session Files

- **`claude-session.md`** - Current session state (objective, tasks, verification plan)
- **`ROADMAP.md`** - Strategic view, updated when significant work completes
- **Git history** - Source of truth for what was actually done

### Session Principles

1. **One feature at a time** - Don't try to do everything at once
2. **Test as you go** - Don't wait until the end to verify
3. **Verify before "done"** - Actually test that changes work (see below)
4. **Keep session state current** - Update `claude-session.md` as tasks complete
5. **Clean handoffs** - End sessions with clear state for next session

---

## Verification Practices

**Never mark a feature complete without verifying it actually works.**

### Before Declaring "Done"

1. **Run unit tests**: `cd app && flutter test`
2. **Manual verification**: Actually use the feature
3. **UI testing with Playwright MCP**: For UI changes, use Playwright to verify flows

### Using Playwright MCP for Verification

For UI changes, verify with actual browser testing:

1. Launch the app in web mode:
   ```bash
   cd app && flutter run -d chrome --web-port=8090
   ```

2. Use Playwright MCP to:
   - Navigate to the relevant screen
   - Test the actual user flow
   - Take screenshots if helpful
   - Verify the feature works end-to-end

3. Note: Flutter web renders to canvas, so use accessibility labels/semantics for targeting elements

### Why This Matters

From [Anthropic's research on long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents):
- Agents tend to "one-shot" projects or declare work complete prematurely
- Real verification (not just "it compiles") catches issues early
- Structured progress tracking prevents drift and forgotten tasks

---

## When Working on Features

1. **Start with `/session-start`** - Establish clear objectives
2. **Read existing code first** - Understand patterns before changing
3. **Update todos** - Use the TodoWrite tool to track implementation steps
4. **Test incrementally** - Don't build everything before testing
5. **Verify with Playwright MCP** - For UI changes, actually test in browser
6. **Focus on reliability** - Stability over new features
7. **Ask before committing** - Follow git workflow above
8. **End with `/session-end`** - Clean handoff for next session

---

## Need Help?

- **Architecture questions?** → [ARCHITECTURE.md](ARCHITECTURE.md)
- **What's next?** → [ROADMAP.md](ROADMAP.md)
- **Implementation guides?** → [docs/implementation/](docs/implementation/)
- **Backend specifics?** → [backend/CLAUDE.md](backend/CLAUDE.md)
- **Frontend specifics?** → [app/CLAUDE.md](app/CLAUDE.md)

Read these files as needed for specific tasks. Context is your friend!

---

**Last Updated**: November 30, 2025
**Next Review**: After Sphere management implementation
