# Parachute - System Architecture

**Version:** 4.0
**Date:** December 8, 2025
**Status:** Active Development - Local-First, Voice-First

---

## Vision

**Parachute** is open & interoperable extended mind technology—a connected tool for connected thinking.

We build local-first, voice-first AI tooling that gives people agency over their digital minds. Technology should support natural human cognition, not force us into unnatural patterns.

**Key Insight:** "The AI that knows you best wins. But people won't share their real context with tools they don't trust. Local-first + voice-first = more honest, richer context = better AI = stronger lock-in through value, not coercion."

---

## Overview

Parachute is a **local-first, voice-first** cross-platform capture tool that exports to wherever you work. We don't compete with your note system; we feed it.

**Core Philosophy**: "One folder, one file system that organizes your data to enable it to be open and interoperable"

All user data lives in a **configurable vault** (default: `~/Parachute/`):

- **Captures** (`{vault}/{captures}/`) - Voice recordings and notes (subfolder name configurable)
- **Spheres** (`{vault}/{spheres}/`) - Themed knowledge containers with system prompts (subfolder name configurable)

**Platform-Specific Defaults:**

- **macOS/Linux:** `~/Parachute/`
- **Android:** `/storage/emulated/0/Android/data/.../files/Parachute`
- **iOS:** App Documents directory

**Primary Platforms:** macOS and Android (iOS coming soon)

**Vault Compatibility:** Works with existing Obsidian, Logseq, and other markdown-based note-taking vaults. Users can point Parachute at their existing vault and configure subfolder names to match their organization.

This architecture enables notes to "cross-pollinate" between spheres while remaining canonical and portable.

---

## High-Level Architecture

### Local-First Design (Current - Nov 2025)

```
┌─────────────────────────────────────────────────────────────┐
│                     Flutter Frontend                        │
│                  (macOS, Android primary)                   │
│                    PRIMARY INTERFACE                        │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  ┌──────────┐  │
│  │ Spheres  │  │ Recorder │  │   Files   │  │ Settings │  │
│  │  Screen  │  │  Screen  │  │  Browser  │  │  Screen  │  │
│  └──────────┘  └──────────┘  └───────────┘  └──────────┘  │
│       │              │              │              │        │
│       └──────────────┴──────────────┴──────────────┘        │
│                        │                                    │
│              ┌─────────▼─────────┐                          │
│              │  Riverpod State   │                          │
│              │    Management     │                          │
│              └─────────┬─────────┘                          │
│                        │                                    │
│         ┌──────────────┼──────────────┐                     │
│         │              │              │                     │
│    ┌────▼─────┐  ┌────▼─────┐  ┌────▼─────┐               │
│    │ Storage  │  │   Git    │  │  Whisper │               │
│    │ Service  │  │ Service  │  │  Service │               │
│    │(Metadata)│  │  (Sync)  │  │  (Local) │               │
│    └────┬─────┘  └────┬─────┘  └──────────┘               │
└─────────┼─────────────┼────────────────────────────────────┘
          │             │
          │             │ Git Push/Pull
          │             ▼
          │    ┌─────────────────┐
          │    │  Git Repository │
          │    │  (GitHub)       │
          │    └─────────────────┘
          │
          ▼
┌──────────────────────────┐
│    Local File System     │
│                          │
│  ~/Parachute/            │
│  ├── captures/           │
│  │   ├── *.opus         │
│  │   ├── *.md           │
│  │   └── *.json         │
│  └── spheres/            │
│      ├── CLAUDE.md       │
│      └── sphere.jsonl    │
└──────────────────────────┘
```

**Note:** AI agent functionality is provided by [parachute-agent](https://github.com/OpenParachutePBC/parachute-agent) (separate repo, Node.js).

### Key Architectural Principles

1. **Flutter App is Self-Contained**: No backend required for core features
2. **Git for Sync**: Standard Git operations to GitHub
3. **Local Services**: Whisper, storage, Git all run locally
4. **File-First**: All data in `~/Parachute/`, human-readable formats
5. **JSONL for Metadata**: Git-friendly, human-readable, no binary databases

---

## Data Flow: Recording a Voice Note

```
1. User records audio in RecordingScreen
   └─→ Flutter AudioRecorder captures audio
   └─→ VAD monitors for silence (auto-pause mode)

2. On silence (1s) or manual pause
   └─→ SmartChunker triggers transcription of chunk
   └─→ Local Whisper transcribes segment
   └─→ Display in real-time

3. User stops recording
   └─→ Final segment transcribed
   └─→ Saves Opus audio to ~/Parachute/captures/
   └─→ Saves markdown transcript
   └─→ Saves JSON metadata

4. Title Generation (Optional - Gemma 2B)
   └─→ TitleGenerationService generates smart title
   └─→ Updates recording metadata

5. Git Sync (If configured)
   └─→ GitService adds files to staging
   └─→ Commits: "Add recording: YYYY-MM-DD_HH-MM-SS"
   └─→ Pushes to GitHub (async, background)

6. Recording appears in list
   └─→ Loaded from local filesystem
   └─→ No backend required
```

**Key Points:**

- Everything happens locally first
- Git sync is optional and asynchronous
- Backend not involved in recording flow
- Works completely offline
- Audio pipeline: `Mic → OS Suppression → High-Pass Filter → VAD → SmartChunker → Whisper`

---

## Technology Choices

### Frontend: Flutter (PRIMARY)

**Why Flutter?**

- One codebase → iOS, Android, macOS, Windows, Linux
- Beautiful UI with 60/120fps animations
- Hot reload for fast development
- Primary development platform

**State Management:** Riverpod

- Type-safe, compile-time checking
- Modern, well-documented
- Great for async operations

**Local Services:**

- `record` package for audio capture
- `sherpa_onnx` for Android transcription
- Platform-specific Parakeet for iOS/macOS (Apple Neural Engine)
- `git2dart` for native Git operations
- `flutter_gemma` for on-device title generation

### Data Storage: File System + JSONL

**Why JSONL over SQLite for sphere metadata?**

- Human-readable and git-friendly
- No binary files to merge
- Simple append-only operations
- Easy to parse and debug
- Standard format, works with any tools

---

## Data Model

### Core Entities

```
Captures (voice recordings, canonical notes)
  ├─ Stored in ~/Parachute/captures/
  ├─ .md file (transcript)
  ├─ .opus file (compressed audio)
  ├─ .json file (metadata)
  └─ Can be linked to multiple Spheres

Spheres (themed knowledge containers)
  ├─ Stored in ~/Parachute/spheres/<name>/
  ├─ CLAUDE.md (system prompt for AI)
  ├─ sphere.jsonl (linked captures & metadata)
  └─ files/ (sphere-specific files)
```

### File System Architecture

**Note:** Vault location and subfolder names are configurable.

```
{vault}/                                # Configurable (default: ~/Parachute/)
├── {captures}/                         # Configurable (default: captures/)
│   ├── 2025-11-24_10-30-00.md        # Transcript
│   ├── 2025-11-24_10-30-00.opus      # Audio (compressed)
│   └── 2025-11-24_10-30-00.json      # Recording metadata
│
└── {spheres}/                          # Configurable (default: spheres/)
    ├── work/
    │   ├── CLAUDE.md                   # System prompt
    │   ├── sphere.jsonl                # Linked captures & metadata
    │   └── files/                      # Sphere-specific files
    │
    └── personal/
        ├── CLAUDE.md
        ├── sphere.jsonl
        └── files/
```

### sphere.jsonl Format

Metadata stored as JSON Lines (one JSON object per line):

```jsonl
{"type":"link","capture":"2025-11-24_10-30-00","linkedAt":"2025-11-24T10:35:00Z","context":"Meeting notes from standup"}
{"type":"tag","name":"project-alpha","addedAt":"2025-11-24T10:36:00Z"}
{"type":"note","content":"Key insight about architecture","createdAt":"2025-11-24T10:40:00Z"}
```

**Entry Types:**

- `link` - Links a capture to this sphere with optional context
- `tag` - Adds a tag for organization
- `note` - Sphere-specific notes (not in captures/)

**Why "Spheres"?**

The term speaks to the holistic, interconnected nature of knowledge—ideas don't live in flat boxes but in overlapping domains of thought. A capture can exist in multiple spheres simultaneously with different context in each.

### Recording Metadata (JSON)

```json
{
  "id": "2025-11-24_10-30-00",
  "title": "Morning thoughts on architecture",
  "createdAt": "2025-11-24T10:30:00Z",
  "duration": 180,
  "hasAudio": true,
  "hasTranscript": true,
  "transcriptionStatus": "complete",
  "spheres": ["work", "personal"]
}
```

---

## Key Architectural Decisions

### Decision 1: Local-First Architecture

**Choice:** All data local by default in `~/Parachute/`, cloud sync optional

**Rationale:**

- Privacy by default - you control what leaves your device
- Works offline
- Fast performance
- User owns their data
- Aligns with brand philosophy (trust through openness)
- Data is portable and interoperable

### Decision 2: Voice-First Interface

**Choice:** Voice capture as primary input method

**Rationale:**

- More natural than typing for most people
- Low compute requirements - runs locally on modest hardware
- Context-rich by default - people share more authentically via voice
- Gets out of the way - technology that meets people where they are
- Opens path to pendants, watches, ambient devices

### Decision 3: JSONL for Sphere Metadata

**Choice:** JSONL files instead of SQLite for sphere data

**Rationale:**

- Git-friendly (no binary merge conflicts)
- Human-readable (can edit with any text editor)
- Simple append-only operations
- Easy to parse and debug
- Works with existing tools (grep, jq, etc.)

**Trade-offs:**

- No SQL queries (need to parse file)
- Less efficient for large datasets
- No ACID transactions

**Migration path:** If spheres grow very large, could add indexing or move specific spheres to SQLite while keeping JSONL as source of truth.

### Decision 4: Git for Sync

**Choice:** Standard Git operations instead of custom sync infrastructure

**Rationale:**

- Standard workflows - familiar to developers
- No custom infrastructure - use existing Git hosting
- Version history - built-in with Git
- Flexibility - works with any Git provider
- E2E encryption possible - encrypted Git repos

**Implementation:**

- Frontend: `git2dart` (libgit2 bindings via FFI)
- Auth: GitHub Personal Access Tokens
- Trigger: Auto-commit after each recording save
- Background: Periodic sync (every 5 minutes)

### Decision 5: Platform-Adaptive Transcription

**Choice:** Different transcription engines per platform

**Rationale:**

- iOS/macOS: Parakeet v3 (Apple Neural Engine, CoreML)
- Android: Sherpa-ONNX (ONNX Runtime)
- Best performance on each platform
- All local, no cloud dependency

### Decision 6: Vault-Style Architecture

**Choice:** Configurable vault location and subfolder names

**Rationale:**

- **Interoperability:** Users can use Parachute alongside Obsidian, Logseq, etc.
- **Flexibility:** Support different organizational preferences
- **Platform-specific:** Android needs external storage, iOS needs app sandbox
- **Portability:** Can move vault to different locations

**Implementation:**

- `FileSystemService` manages all path logic in Flutter
- Platform-specific defaults
- Subfolder names stored in `SharedPreferences`

---

## Git-Based Synchronization

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Git Repository                           │
│                      (GitHub)                               │
│                                                              │
│  ~/Parachute/                                               │
│  ├── captures/                                              │
│  │   ├── 2025-11-24_10-30-00.md (transcript)              │
│  │   ├── 2025-11-24_10-30-00.opus (audio)                 │
│  │   └── 2025-11-24_10-30-00.json (metadata)              │
│  └── spheres/                                                │
│      └── work/                                              │
│          ├── CLAUDE.md (system prompt)                     │
│          └── sphere.jsonl (links & metadata)               │
└─────────────────────────────────────────────────────────────┘
         ▲                                    ▲
         │ git push                           │ git pull
         │                                    │
    ┌────┴─────┐                         ┌───┴──────┐
    │  Phone   │                         │  Laptop  │
    │(Android) │                         │ (macOS)  │
    │          │                         │          │
    │ • git2dart                        │ • git2dart│
    │ • Auto-commit                     │ • Auto-commit
    │ • GitHub PAT                      │ • GitHub PAT
    └──────────┘                         └──────────┘
```

### Key Principles

1. **Git Replaces Custom Sync** - Standard Git operations
2. **Frontend Only** - No backend needed for sync
3. **Shared Repository** - All devices sync to same repo
4. **Local-First** - Works offline, syncs when available
5. **Audio Compression** - Opus codec before upload (smaller than WAV)

### Conflict Resolution

- Strategy: Optimistic (most captures are new files)
- Detection: Check for merge conflicts
- Resolution: "Last write wins" for different files
- Future: UI for manual resolution if needed

---

## Security Considerations

### Current (Local-First)

- All data stored locally
- GitHub PAT stored in flutter_secure_storage
- Private repositories only
- User controls Git provider
- No cloud dependency for core features

### API Keys (for AI features)

- Anthropic API key stored securely
- Never transmitted to our servers
- User provides their own key

### Future Enhancements

- SSH key support for Git authentication
- GPG signing for commits
- Git-crypt for encrypted repos

---

## Development Workflow

### Local Development

```bash
flutter pub get
flutter run -d macos      # or android, chrome
flutter test              # Run all tests
```

### Testing Strategy

- Unit tests for services (VAD, SmartChunker, etc.)
- Widget tests for UI components
- 116+ tests for audio pipeline

See [docs/development/testing.md](docs/development/testing.md) for detailed testing guide.

---

## Competitive Positioning

### vs. Voice-First Hardware (Friend, Omi)

- They're focused on always-on recording → privacy nightmare
- Parachute: Local-first = you control what's captured

### vs. Note-Taking Tools (Obsidian, Notion)

- Desktop-first → not where thinking happens
- Parachute: Voice-first capture that exports to wherever you work

### vs. AI Assistants (ChatGPT, Claude)

- Cloud-dependent → no privacy, no offline
- Parachute: Local-first with your actual context

---

## Open Questions

### Current

- [ ] Best UX for sphere management and linking?
- [ ] How to surface relevant captures in AI conversations?
- [ ] iOS Git support timeline?

### Future

- [ ] MCP integrations for connecting to other tools?
- [ ] Knowledge graph visualization?
- [ ] Plugin ecosystem (Obsidian model)?

---

## References

- **MCP Specification:** https://modelcontextprotocol.io/
- **Flutter Docs:** https://docs.flutter.dev/
- **Riverpod Docs:** https://riverpod.dev/
- **git2dart:** https://github.com/SkinnyMind/git2dart

---

## Next Steps

See [ROADMAP.md](ROADMAP.md) for detailed feature queue.

**Current Focus (Nov 2025):**

1. Stability and reliability improvements
2. Sphere management and organization
3. Export integrations (to ChatGPT, Claude, etc.)

**Future Work:**

- Personalized local LLM with deep personal context
- MCP integrations
- Knowledge graph visualization
- iOS Git support

---

**Last Updated:** December 8, 2025
**Status:** Active Development - Flutter App Only

**Version History:**

- v4.0 (Dec 8, 2025): Removed Go backend (moved to parachute-agent repo)
- v3.0 (Nov 24, 2025): Renamed Spaces→Spheres, SQLite→JSONL, added pitch philosophy
- v2.2 (Nov 6, 2025): Git sync implementation complete
- v2.1 (Nov 1, 2025): Added vault-style architecture with configurable paths
- v2.0 (Oct 27, 2025): Added space.sqlite knowledge system architecture
- v1.0 (Oct 20, 2025): Initial architecture with ACP integration
