# Git-Based Sync Strategy

**Status**: 🚧 In Active Development
**Priority**: P0 - Core Architecture
**Last Updated**: November 5, 2025

---

## Strategic Vision

Parachute is transitioning to a **local-first, Git-based synchronization model** where:

1. **All data lives in `~/Parachute/`** - A single folder containing captures and spaces
2. **Git handles sync** - GitHub/GitLab repos instead of custom backend sync
3. **Backend is optional** - Only needed for agentic AI tasks, not sync
4. **Multi-device via Git** - Phone, laptop, backend all sync to same repo

---

## Architecture

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
    │ • Capture voice                   │ • Agentic AI │
    │ • Local Whisper                   │ • Long tasks │
    │ • Local LLM                       │ • Complex ops│
    │ • Git sync                        │ • Git sync   │
    └──────────┘                         └──────────┘
```

---

## Key Principles

1. **Shared Git Repository** - Both frontend and backend operate on the same repo
2. **Local-First** - Everything works offline; sync when available
3. **Git Handles Conflicts** - Built-in merge strategies for basic conflicts
4. **Optional Backend** - Mobile-only users work without backend (single-device mode)
5. **Backend as Agent Runner** - When present, backend handles long-running AI tasks
6. **Sync Verification** - Both sides verify they're on the same Git branch/commit

---

## Implementation Roadmap

### Phase 1: Git Sync Foundation (Current)

**Goal**: Enable basic Git synchronization for voice captures

#### Step 1: Research & Choose Git Library ✅ (In Progress)

- Evaluate Flutter Git libraries:
  - `git2dart` (libgit2 bindings - native performance)
  - `dart_git` (pure Dart - portable but slower)
  - CLI wrapper (system `git` - simple but platform-dependent)
- Document trade-offs and recommendation
- Create proof-of-concept

#### Step 2: GitHub PAT Integration

- Settings screen for GitHub Personal Access Token
- Secure token storage via `flutter_secure_storage`
- Test authentication against GitHub API
- UI for repo selection/creation

#### Step 3: Basic Git Operations

- Initialize repo in `~/Parachute/` if not exists
- Commit after saving recording (auto-commit)
- Push to remote (GitHub private repo)
- Pull on app startup
- Sync status indicator in UI

#### Step 4: Conflict Handling (Basic)

- Detect merge conflicts
- For now: "Last write wins" on different files
- Alert user to conflicts
- Manual resolution UI (future enhancement)

---

### Phase 2: Backend Git Integration

**Goal**: Backend syncs to same repo for agentic AI

#### Tasks

- Backend uses `go-git` library
- Pull before running AI tasks
- Commit AI-generated content with descriptive messages
- Push results back to repo
- Verify frontend/backend on compatible commits

---

### Phase 3: Advanced Sync Features

**Goal**: Polish multi-device experience

#### Features

- Background sync (periodic pull/push)
- Sync settings (auto/manual, frequency)
- Conflict resolution UI
- LLM-assisted merge (experimental)
- Offline indicator and queue
- Sync history/log viewer

---

## Current Status

### ✅ Completed (Nov 5, 2025)

- **Local-first recording** - Saves to `~/Parachute/captures/`
- **Recordings load from local filesystem** - No backend dependency
- **Live transcription UI** - Manual pause-based chunking
- **Instant UI responsiveness** - Non-blocking initialization
- **Git library research** - Comprehensive analysis complete
- **git2dart POC** - All tests passing ✅
  - Repository initialization
  - File staging (text + binary)
  - Committing with signatures
  - Status checking
  - Commit history
  - Audio file handling validated

**POC Results**: See [docs/research/git-poc-results.md](../research/git-poc-results.md)

### 🚧 In Progress (Week of Nov 5)

- **Phase 2: GitHub Integration**
  - Implement clone, push, pull operations
  - GitHub PAT authentication
  - Basic error handling

### 📋 Upcoming

- Auto-commit on capture save
- Sync status indicator
- Conflict detection and resolution
- Backend Git integration (go-git)

---

## User Experience Goals

### Single Device (No Git Sync)

```
Record → Transcribe → Save to ~/Parachute/captures/
```

✅ Works completely offline
✅ No configuration needed

### Multi-Device with Git Sync

```
Device A: Record → Commit → Push
Device B: Pull → See new recording
```

✅ Seamless sync across devices
✅ Standard Git workflow (familiar to developers)

### With Backend (Agentic AI)

```
Mobile: Record → Push
Backend: Pull → AI Processing → Commit → Push
Mobile: Pull → See AI results
```

✅ Long-running tasks handled by backend
✅ Results sync back via Git

---

## Technical Decisions

### Authentication: GitHub Personal Access Tokens

- **Pros**: Simple, well-documented, works everywhere
- **Cons**: Manual rotation, less secure than SSH keys
- **Future**: Support SSH keys (more complex setup)

### Conflict Strategy: Optimistic with Alerts

- **Approach**: Try auto-merge, alert on conflicts
- **Rationale**: Most captures are append-only (new files)
- **Future**: LLM-assisted conflict resolution

### Commit Strategy: Auto-commit on Save

- **Approach**: Every recording = 1 commit
- **Message Format**: `"Add recording: YYYY-MM-DD_HH-MM-SS"`
- **Rationale**: Granular history, easy to sync

---

## Open Questions

1. **Large binary files** - Should we use Git LFS for audio files?
2. **Sync frequency** - Push immediately or batch commits?
3. **Branch strategy** - Single `main` branch or per-device branches?
4. **Backend hosting** - Support cloud-hosted backends syncing to user repos?

---

## Related Documents

- [ARCHITECTURE.md](../../ARCHITECTURE.md) - Overall system design
- [ROADMAP.md](../../ROADMAP.md) - Development timeline
- [local-first-recording.md](../features/local-first-recording.md) - Recording architecture

---

## Related Documents

- [POC Results](../research/git-poc-results.md) - Detailed test results and findings
- [Git Libraries Comparison](../research/git-libraries-comparison.md) - Library evaluation

---

**Last Action**: ✅ POC completed successfully - All tests passing
**Next Action**: Implement Phase 2 (GitHub Integration with PAT authentication)
