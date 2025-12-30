# Parachute Build - Development Guide

**AI-powered development assistant that works with external codebases.**

---

## Overview

Parachute Build is a Flutter app for AI-assisted software development. Unlike Parachute Chat (which operates on your personal knowledge vault), Build is designed to work with external codebases - helping you code, refactor, and understand projects.

**Key Characteristics:**
- Requires Base server connection (`http://localhost:3333` by default)
- Working directory selector for choosing which codebase to work on
- Sessions stored in `~/Parachute/Build/sessions/`
- Similar architecture to Chat but specialized for development workflows

---

## Vision

Build is for developers who want Claude's help with code:
- Work on multiple codebases (switch between projects)
- Generate and save code artifacts
- Access vault memory (past solutions, patterns) via MCP
- Eventually: integrated terminal, file browser, diff viewer

Think of it as a local alternative to Claude Code or Cursor, but:
- **Local-first**: Your code stays on your machine
- **Vault-connected**: AI remembers your coding patterns and past solutions
- **Open**: Standard formats, works with any editor

---

## Data Structure

```
~/Parachute/Build/
├── sessions/              # Development chat sessions
│   └── {session-id}.md   # Session with working directory metadata
├── artifacts/            # Generated code, configs, scripts
│   └── {artifact-id}/   # Each artifact can be a file or directory
└── index.db             # SQLite RAG index (future)
```

### Session Metadata

Sessions track which codebase they're working on:

```yaml
---
session_id: build-123
working_directory: /Users/me/projects/my-app
title: "Refactoring auth module"
created_at: 2025-12-30T10:00:00Z
---
```

---

## Architecture (Future)

```
┌─────────────────────────────────────────────────────────────────┐
│                        PARACHUTE BUILD                           │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    UI Layer                               │   │
│  │  SessionList, CodeChat, ArtifactViewer, DirectoryPicker  │   │
│  └────────────────────────┬─────────────────────────────────┘   │
│                           │                                      │
│  ┌────────────────────────▼─────────────────────────────────┐   │
│  │                 State Layer (Riverpod)                    │   │
│  │  sessionProvider, artifactsProvider, directoryProvider   │   │
│  └────────────────────────┬─────────────────────────────────┘   │
│                           │                                      │
│  ┌────────────────────────▼─────────────────────────────────┐   │
│  │                  Service Layer                            │   │
│  │  ChatService (reuse from Chat), FileService              │   │
│  └────────────────────────┬─────────────────────────────────┘   │
│                           │                                      │
└───────────────────────────┼──────────────────────────────────────┘
                            │
                            ▼ HTTP/SSE (port 3333)
                   ┌─────────────────┐
                   │  BASE SERVER    │
                   │  (with cwd)     │
                   └─────────────────┘
```

---

## Key Differences from Chat

| Aspect | Chat | Build |
|--------|------|-------|
| **Primary Use** | Personal knowledge, conversations | Software development |
| **Working Directory** | Always vault | Selectable external codebase |
| **Sessions Stored** | `Chat/sessions/` | `Build/sessions/` |
| **Artifacts** | Generated images/audio | Generated code/configs |
| **Tools** | vault-search, para-generate | vault-search, file ops |

---

## Backend Support (Already Available)

The Base server already supports Build's needs:

- `workingDirectory` parameter in `/api/chat/stream`
- `/api/directories` endpoint lists available codebases
- Sessions track and restore working directory context
- Claude Agent SDK operates in the specified cwd

---

## Implementation Roadmap

### Phase 1: MVP (Copy from Chat)
- [ ] Create Flutter project
- [ ] Copy core services from Chat
- [ ] Add DirectoryPicker widget
- [ ] Store sessions in Build/sessions/

### Phase 2: Developer Features
- [ ] Artifact management (save generated code)
- [ ] Recent directories quick-switch
- [ ] File tree viewer for current codebase

### Phase 3: Advanced
- [ ] Integrated terminal
- [ ] Diff viewer for proposed changes
- [ ] Multi-file artifact generation

---

## Commands (Future)

```bash
cd build
flutter pub get                 # Install dependencies
flutter run -d macos            # Run on macOS
flutter analyze                 # Check for issues
```

---

## Related Documentation

| Path | Description |
|------|-------------|
| `../CLAUDE.md` | Monorepo overview |
| `../chat/CLAUDE.md` | Chat app (similar architecture) |
| `../base/claude.md` | Server API documentation |

---

**Status:** Planning phase - folder structure created
**Last Updated:** December 30, 2025
