# Parachute Development Roadmap

**Last Updated**: November 5, 2025

---

## Current Focus: Git-Based Sync Foundation

**Status**: 🚧 In Active Development
**Priority**: P0
**Timeline**: November 2025

Enable multi-device synchronization using Git as the backend. All data in `~/Parachute/` syncs via GitHub/GitLab, eliminating the need for custom backend sync infrastructure.

**See**: [docs/architecture/git-sync-strategy.md](docs/architecture/git-sync-strategy.md)

### Why This Pivot?

The **strategic reorientation to local-first architecture** means:

- Git handles sync (not custom backend)
- Backend only for agentic AI tasks
- Standard Git workflows (familiar to developers)
- E2E encrypted repos for privacy
- Works with any Git hosting (GitHub, GitLab, self-hosted)

**Previous Focus** (Space SQLite) is **deferred** until Git sync is stable.

---

## Development Phases

### ✅ Completed

#### Foundation Phase (Sep-Oct 2025)

- [x] Backend architecture (Go + Fiber + SQLite)
- [x] Frontend architecture (Flutter + Riverpod)
- [x] ACP integration with Claude
- [x] WebSocket streaming for conversations
- [x] Basic space and conversation management

#### Recorder Integration (Oct 2025)

- [x] **Phase 1**: Basic merge of recorder into main app
- [x] **Phase 2**: Visual unification
- [x] **Phase 3a**: Local file system foundation (`~/Parachute/`)
- [x] **Phase 3b**: File browser with markdown preview
- [x] Omi device integration with firmware updates
- [x] Local Whisper transcription (on-device models)
- [x] Gemma 2B title generation with HuggingFace integration
- [x] Transcript display and editing

#### Vault System (Nov 2025)

- [x] Configurable vault location (platform-specific defaults)
- [x] Configurable subfolder names (captures/, spaces/)
- [x] Obsidian/Logseq compatibility
- [x] FileSystemService architecture for path management
- [x] 4-step onboarding flow
- [x] Model download management (Whisper + Gemma)
- [x] HuggingFace token integration
- [x] Background downloads with progress persistence
- [x] Storage calculation and display

#### Local-First Recording (Nov 5, 2025)

- [x] Live transcription UI with journal-style interface
- [x] Manual pause-based chunking for intentional thought capture
- [x] Instant screen navigation (non-blocking initialization)
- [x] Complete final segment transcription before save
- [x] Recordings load from local filesystem (no backend)
- [x] Markdown + WAV files saved to `~/Parachute/captures/`
- [x] Immediate discard without unnecessary processing
- [x] Eliminated backend dependency for recording flow

---

## Active Development

### 🚧 Git-Based Sync Foundation (Current Sprint)

**Goal**: Enable multi-device synchronization using Git repositories

#### Phase 1: Library Selection & POC (In Progress)

- [x] Research Flutter Git libraries
- [x] Evaluate git2dart, dart_git, git CLI wrapper
- [x] Document recommendation and trade-offs
- [ ] Create proof-of-concept with git2dart
- [ ] Test basic Git operations (init, commit, push/pull)
- [ ] Validate with audio files (realistic scenario)

**Target**: Week of Nov 5, 2025

#### Phase 2: GitHub Integration

- [ ] Settings screen for GitHub Personal Access Token
- [ ] Secure token storage via flutter_secure_storage
- [ ] Test authentication against GitHub API
- [ ] UI for repository selection/creation
- [ ] Handle auth errors gracefully

**Target**: Week of Nov 11, 2025

#### Phase 3: Core Sync Operations

- [ ] Initialize Git repo in `~/Parachute/` if not exists
- [ ] Auto-commit after saving recording
- [ ] Pull on app startup
- [ ] Push after commit (with retry logic)
- [ ] Sync status indicator in UI
- [ ] Offline queue for commits

**Target**: Week of Nov 18, 2025

#### Phase 4: Conflict Handling & Polish

- [ ] Detect merge conflicts
- [ ] Basic "last write wins" strategy for different files
- [ ] Alert user to conflicts
- [ ] Manual conflict resolution UI (future)
- [ ] Error handling for network issues
- [ ] Sync history/log viewer

**Target**: Week of Nov 25, 2025

**Overall Target**: Git sync MVP by end of November 2025

---

## Near-Term Roadmap (Q4 2025 - Q1 2026)

### 🔜 Backend Git Integration

**Priority**: P1
**Status**: Deferred until frontend Git sync is stable
**Timeline**: December 2025

- Backend uses `go-git` library for Go
- Pull before running agentic AI tasks
- Commit AI-generated content
- Push results back to repo
- Verify frontend/backend on compatible commits

**Why**: Enable backend to work on same Git-synced data

### 🔜 Space SQLite Knowledge System

**Priority**: P1
**Status**: Deferred until Git sync is complete
**Timeline**: January 2026

Link captures to spaces with space-specific context while keeping notes canonical.

- Backend database service for note linking
- Frontend UI for linking recordings to spaces
- Space note browser
- Chat integration (reference notes in conversations)
- CLAUDE.md template variables

**See**: [docs/features/space-sqlite-knowledge-system.md](docs/features/space-sqlite-knowledge-system.md)

**Why**: Make recordings more useful by connecting them to AI conversation contexts

### 🔜 Smart Note Management

**Priority**: P1
**Status**: Backlog

- Auto-suggest spaces when saving recordings
- Tag suggestions based on content
- Automatic context generation using Claude
- "Similar notes" recommendations

**Why**: Reduce manual work, improve knowledge organization

---

## Medium-Term Roadmap (Q1 2026)

### Knowledge Graph Visualization

**Priority**: P2
**Status**: Concept

- Visual map of notes, spaces, and relationships
- "What connects these two spaces?"
- Timeline view of knowledge evolution
- Cluster detection (similar notes)

**Why**: Enable visual discovery and pattern recognition

### Custom Space Templates

**Priority**: P2
**Status**: Concept

Create templates for common space types:

- Project spaces (tasks, milestones, issues)
- Research spaces (papers, citations, hypotheses)
- Personal spaces (habits, reflections, goals)
- Creative spaces (ideas, drafts, inspirations)

**Why**: Jumpstart space setup, encourage best practices

### Advanced Search & Query

**Priority**: P2
**Status**: Concept

- Natural language queries ("farming notes from last month")
- Semantic search using embeddings
- Cross-space queries
- Export query results

**Why**: Find information faster, discover connections

---

## Long-Term Vision (2026+)

### Collaborative Spaces

**Priority**: P3
**Status**: Vision

- Share spaces with team members
- Permissions per space
- Sync while maintaining privacy for personal notes
- Comments and discussions

**Why**: Enable team knowledge management

### Mobile-First Recorder

**Priority**: P2
**Status**: Vision

- Native mobile app with better recording
- Background recording with Omi
- Offline-first sync
- Widget for quick capture

**Why**: Most voice notes are captured on mobile

### Plugin System

**Priority**: P3
**Status**: Vision

- Space plugins for custom functionality
- Custom visualizations
- Integration with external tools (Obsidian, Notion, etc.)
- API for third-party apps

**Why**: Extensibility without bloat

### AI-Powered Insights

**Priority**: P3
**Status**: Vision

- Weekly/monthly summaries of notes
- Pattern detection across spaces
- Proactive suggestions ("You haven't reviewed farming notes in 2 weeks")
- Automated tagging and categorization

**Why**: Surface insights user might miss

---

## Feature Request Queue

### Small Enhancements

- [ ] Export conversation as markdown
- [ ] Duplicate space (with or without content)
- [ ] Archive old conversations
- [ ] Bulk operations (move, delete, tag)
- [ ] Keyboard shortcuts
- [ ] Dark mode refinements
- [ ] Custom color schemes per space
- [ ] Note version history

### Recorder Improvements

- [ ] Audio bookmarks during recording
- [ ] Real-time transcription preview
- [ ] Speaker diarization (multiple speakers)
- [ ] Export formats (MP3, FLAC)
- [ ] Noise reduction preprocessing
- [ ] Variable playback speed

### Integration Requests

- [ ] Import from Apple Notes
- [ ] Import from Voice Memos
- [ ] Export to Obsidian
- [ ] Zapier/IFTTT webhooks
- [ ] Calendar integration
- [ ] Email-to-Parachute

---

## Technical Debt & Infrastructure

### High Priority

- [ ] Improve error handling and user feedback
- [ ] Add comprehensive logging
- [ ] Performance optimization (large conversations)
- [ ] Memory usage profiling
- [ ] Implement rate limiting
- [ ] Add request validation middleware

### Medium Priority

- [ ] Increase test coverage (target: 80%)
- [ ] E2E testing framework
- [ ] CI/CD pipeline
- [ ] Automated backup system
- [ ] Database migration tooling
- [ ] API versioning strategy

### Low Priority

- [ ] Code documentation (GoDoc)
- [ ] API documentation (OpenAPI/Swagger)
- [ ] Contributing guidelines
- [ ] Architectural decision records (ADRs)

---

## Research & Exploration

### Active Research

- [ ] Optimal embedding models for semantic search
- [ ] Local LLM integration (Llama, Mistral)
- [ ] Graph database alternatives (SQLite vs Neo4j)
- [ ] Differential sync algorithms

### Future Exploration

- [ ] Real-time collaboration (CRDT)
- [ ] Homomorphic encryption for cloud sync
- [ ] Federated learning for privacy-preserving insights
- [ ] Progressive web app (PWA) version

---

## Non-Goals

Things we've explicitly decided **not** to pursue:

- ❌ Social features (likes, followers, feeds)
- ❌ Ads or attention-harvesting mechanics
- ❌ Required cloud sync (always local-first)
- ❌ Lock-in formats (use markdown, standard SQLite)
- ❌ Cryptocurrency/blockchain integration
- ❌ AI training on user data without explicit consent

---

## Decision Log

### November 2025

**Strategic Pivot to Git-Based Sync (Nov 5)**

- ✅ **Major architectural decision**: Use Git for multi-device sync instead of custom backend sync
- ✅ Git replaces backend sync infrastructure (backend now only for agentic AI)
- ✅ Chose `git2dart` over pure Dart implementation for performance
- ✅ GitHub Personal Access Tokens for initial auth (SSH keys later)
- ✅ Auto-commit strategy: one commit per recording
- ✅ Frontend and backend sync to same Git repository

**Local-First Recording (Nov 5)**

- ✅ Live transcription UI with manual pause-based chunking
- ✅ Eliminated backend dependency for recording/storage
- ✅ All recordings save to `~/Parachute/captures/` (markdown + audio)
- ✅ Non-blocking UI initialization for instant screen navigation
- ✅ Complete final segment transcription before save

**Vault System (Nov 1)**

- ✅ Vault-based architecture with configurable location (supports Obsidian/Logseq)
- ✅ Configurable subfolder names for flexibility
- ✅ Platform-specific storage defaults (macOS, Android, iOS)
- ✅ HuggingFace token integration for gated models
- ✅ Background download support with progress persistence

### October 2025

- ✅ Decided on space.sqlite approach over centralized knowledge graph
- ✅ Chose to keep notes canonical in captures/ (not duplicate)
- ✅ Adopted vault folder as single root for all data
- ✅ Prioritized local-first over cloud-first architecture

### September 2025

- ✅ Selected Go + Fiber for backend (over Node.js/Python)
- ✅ Selected Flutter for frontend (over React Native/Swift)
- ✅ Chose ACP protocol for Claude integration
- ✅ Decided on SQLite for MVP (PostgreSQL for later)

---

## How to Contribute Ideas

Have an idea for Parachute? Here's how to propose it:

1. **Check existing docs** - Review this roadmap and feature docs
2. **Open an issue** - Describe the problem and proposed solution
3. **Discuss trade-offs** - What's gained? What's the cost?
4. **Prototype if possible** - Code speaks louder than words
5. **Iterate** - Feedback shapes the best features

---

## Roadmap Principles

1. **Local-First**: User owns their data, always
2. **Privacy by Default**: No tracking, no ads, no surveillance
3. **Open & Interoperable**: Use standard formats, enable export
4. **Thoughtful AI**: Enhance thinking, don't replace it
5. **Sustainable Pace**: Quality over speed, avoid burnout
6. **User-Driven**: Build what users need, not what's trendy

---

## Related Documents

- [docs/features/space-sqlite-knowledge-system.md](docs/features/space-sqlite-knowledge-system.md) - Current feature in development
- [ARCHITECTURE.md](ARCHITECTURE.md) - System design and technical decisions
- [CLAUDE.md](CLAUDE.md) - Developer guidance for working with this codebase
- [docs/merger-plan.md](docs/merger-plan.md) - Historical: How we merged recorder into main app

---

**Next Update**: After completing Space SQLite Knowledge System Phase 1

**Feedback**: Open an issue or discussion on GitHub
