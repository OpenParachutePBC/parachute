# Parachute Development Roadmap

**Last Updated**: November 13, 2025

---

## Current Focus: Space SQLite Knowledge System

**Status**: 🔜 Next Up
**Priority**: P0

All recorder features are complete! Next up: resuming the Space SQLite Knowledge System that was deferred when we pivoted to local-first recording.

**See**: [docs/features/space-sqlite-knowledge-system.md](docs/features/space-sqlite-knowledge-system.md)

### Recent Major Achievement: Auto-Pause Voice Recording ✅

**Completed**: November 10, 2025

Automatic silence detection with intelligent noise suppression is now **fully functional**:

- ✅ VAD (Voice Activity Detection) - RMS energy-based speech detection
- ✅ SmartChunker - Auto-segment on 1s silence
- ✅ OS-level noise suppression (echoCancel, autoGain, noiseSuppress)
- ✅ High-pass filter (80Hz cutoff) - Removes low-frequency rumble
- ✅ Visual debug overlay with real-time audio graphs
- ✅ Settings toggle for auto-pause and debug mode
- ✅ 116 comprehensive tests covering all components

**Audio Pipeline**: `Mic → OS Suppression → High-Pass Filter → VAD → SmartChunker → Whisper`

**Implementation Docs**:

- [docs/implementation/noise-filtering-phase1.md](docs/implementation/noise-filtering-phase1.md) - Current implementation
- [docs/implementation/auto-pause-branch-audit.md](docs/implementation/auto-pause-branch-audit.md) - Complete audit
- [docs/implementation/auto-pause-vad-implementation.md](docs/implementation/auto-pause-vad-implementation.md) - Research

**Result**: Hands-free journaling with natural pauses. No manual pause button needed!

### Recent Major Achievement: Git-Based Sync ✅

**Completed**: November 6, 2025

Multi-device synchronization using Git is now **fully functional**. All data in `~/Parachute/` syncs via GitHub with:

- ✅ Auto-sync after save/update/delete operations
- ✅ Manual sync with UI indicator showing file counts
- ✅ Periodic background sync (every 5 minutes)
- ✅ Settings persistence across app restarts
- ✅ Complete local-first architecture (no backend required for recordings)

**See**: [docs/implementation/github-sync-implementation.md](docs/implementation/github-sync-implementation.md)

### Strategic Architecture

The **local-first architecture** means:

- Git handles sync (not custom backend)
- Backend only for agentic AI tasks (future)
- Standard Git workflows (familiar to developers)
- E2E encrypted repos for privacy
- Works with any Git hosting (GitHub, GitLab, self-hosted)

**Next Feature** (Space SQLite) is **deferred** until UI polish is complete.

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

#### Recording UI Enhancements (Nov 6, 2025)

- [x] Added **context field** to recordings (space-specific interpretation)
- [x] Inline editing for title, transcript, and context
- [x] Unified RecordingDetailScreen with clean, focused design
- [x] Periodic refresh for processing status updates
- [x] Link captures to spaces UI integration

#### Auto-Pause Voice Recording ✅ (COMPLETED - Nov 7-10, 2025)

- [x] **Week 1**: VAD, Resampler, SmartChunker (ports from RichardTate)
- [x] AutoPauseTranscriptionService with VAD-based chunking
- [x] Settings toggle for auto-pause mode
- [x] UI integration with adaptive controls
- [x] OS-level noise suppression (echoCancel, autoGain, noiseSuppress)
- [x] High-pass filter (80Hz cutoff) for low-frequency noise removal
- [x] Visual debug overlay with real-time audio graphs
- [x] 116 comprehensive unit tests (all passing)
- [x] Complete documentation and implementation audit

**Audio Pipeline**: Mic → OS Suppression → High-Pass Filter → VAD → SmartChunker → Whisper

**Implementation Docs**:

- [docs/implementation/noise-filtering-phase1.md](docs/implementation/noise-filtering-phase1.md)
- [docs/implementation/auto-pause-branch-audit.md](docs/implementation/auto-pause-branch-audit.md)

**Note**: RNNoise FFI (Week 2 from original plan) deferred - OS suppression + high-pass filter proved sufficient for typical environments.

#### Git-Based Sync Foundation ✅ (COMPLETED - Nov 6, 2025)

- [x] **Phase 1**: Library selection and POC with git2dart
- [x] **Phase 2**: GitHub integration with PAT authentication
- [x] **Phase 3**: Core sync operations (init, commit, push, pull)
- [x] **Phase 4**: Auto-sync triggers after save/update/delete
- [x] GitService implementation with git2dart
- [x] Settings screen for GitHub configuration
- [x] Secure token storage via flutter_secure_storage
- [x] Manual sync with UI indicator showing file counts
- [x] Auto-commit after recording save
- [x] Periodic background sync (every 5 minutes)
- [x] Settings persistence across app restarts
- [x] Push and pull operations with GitHub PAT
- [x] Complete local-first architecture

**Status**: ✅ Git sync MVP complete and fully functional

**See**: [docs/implementation/github-sync-implementation.md](docs/implementation/github-sync-implementation.md)

#### Recording UI Polish ✅ (COMPLETED - Nov 6-13, 2025)

- [x] Context field with voice input (record → transcribe → insert)
- [x] Background transcription service (continues when app backgrounded)
- [x] Incomplete transcription detection and resume
- [x] Immediate recording persistence (no data loss on exit)
- [x] Android permissions and ProGuard fixes
- [x] App branding ("Parachute" on all platforms)
- [x] Custom app icon (yellow parachute design)
- [x] Google Keep-inspired notes grid/list view

**Status**: ✅ Recording UI polish complete

---

---

## Active Development

### 🎯 Current Status (Nov 13, 2025)

**All recorder features complete!** Ready to resume Space SQLite Knowledge System.

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
