# Parachute Development Roadmap

**Last Updated**: November 24, 2025

---

## Vision

**Parachute** is open & interoperable extended mind technology—a connected tool for connected thinking.

We build local-first, voice-first AI tooling that gives people agency over their digital minds.

**Go-to-Market Wedge:**
1. Free capture tool (current focus) - Best-in-class voice capture
2. Build trust - Become the tool people trust with their thoughts
3. Add integrations - Connect to more tools via MCP and open protocols
4. Personalized AI - Offer local LLM with deep personal context
5. Subscription conversion - $20/month for personalized AI

---

## Current Focus: Stability & Sphere Management

**Status**: Stability focus (Nov 24, 2025)
**Primary Platforms**: macOS and Android (iOS coming soon)

### Recent Reliability Work (Nov 20-24, 2025)

- Critical memory leak fixes and dead code removal
- Stylistic lint fixes
- Async bug fixes and race condition prevention
- GitSync initialization race condition fix
- Standardized FileSystemService usage

### Recent Major Achievement: Auto-Pause Voice Recording

**Completed**: November 10, 2025

Automatic silence detection with intelligent noise suppression:

- VAD (Voice Activity Detection) - RMS energy-based speech detection
- SmartChunker - Auto-segment on 1s silence
- OS-level noise suppression (echoCancel, autoGain, noiseSuppress)
- High-pass filter (80Hz cutoff) - Removes low-frequency rumble
- 116 comprehensive tests covering all components

**Audio Pipeline**: `Mic → OS Suppression → High-Pass Filter → VAD → SmartChunker → Whisper`

### Recent Major Achievement: Git-Based Sync

**Completed**: November 17, 2025

Multi-device synchronization using Git:

- Auto-sync after save/update/delete operations
- Manual sync with UI indicator
- Periodic background sync (every 5 minutes)
- Native Git on macOS and Android
- iOS support pending

---

## Development Phases

### Completed

#### Foundation Phase (Sep-Oct 2025)

- [x] Backend architecture (Go + Fiber + SQLite) - now optional
- [x] Frontend architecture (Flutter + Riverpod)
- [x] ACP integration with Claude
- [x] WebSocket streaming for conversations
- [x] Basic space and conversation management

#### Recorder Integration (Oct 2025)

- [x] Local Whisper transcription (on-device models)
- [x] Gemma 2B title generation
- [x] Omi device integration with firmware updates
- [x] Transcript display and editing

#### Vault System (Nov 2025)

- [x] Configurable vault location (platform-specific defaults)
- [x] Configurable subfolder names
- [x] Obsidian/Logseq compatibility
- [x] 4-step onboarding flow
- [x] Model download management

#### Local-First Recording (Nov 5, 2025)

- [x] Live transcription UI with journal-style interface
- [x] Auto-pause VAD-based chunking
- [x] Recordings load from local filesystem (no backend)
- [x] Markdown + audio files saved to `~/Parachute/captures/`

#### Git-Based Sync (Nov 6-17, 2025)

- [x] git2dart integration for native Git operations
- [x] GitHub OAuth with repository-scoped access
- [x] Auto-commit after recording save
- [x] Periodic background sync
- [x] Android SSL support with OpenSSL certificates

#### Recording UI Polish (Nov 6-13, 2025)

- [x] Context field with voice input
- [x] Background transcription service
- [x] Immediate recording persistence
- [x] Google Keep-inspired notes grid/list view
- [x] Custom app icon (yellow parachute design)

#### Reliability Improvements (Nov 20-24, 2025)

- [x] Memory leak fixes
- [x] Race condition prevention
- [x] Code cleanup and standardization
- [x] FileSystemService usage standardization

---

## Active Development

### Current Status (Nov 24, 2025)

**Focus**: Stability and reliability before new features.

**Next**: Sphere management with JSONL metadata (not SQLite).

---

## Near-Term Roadmap (Q4 2025 - Q1 2026)

### Sphere Management

**Priority**: P1
**Status**: Next up
**Timeline**: December 2025

Organize captures into themed spheres with JSONL metadata:

- Create/edit/delete spheres
- Link captures to spheres with context
- Sphere-specific CLAUDE.md system prompts
- sphere.jsonl for git-friendly metadata storage

**Why JSONL over SQLite:**
- Human-readable and git-friendly
- No binary merge conflicts
- Simple append-only operations
- Easy to parse and debug

### Export Integrations

**Priority**: P1
**Status**: Backlog
**Timeline**: January 2026

Export captures to external AI tools:

- Copy transcript for ChatGPT/Claude
- Export with context for AI conversations
- Markdown export for Obsidian/Logseq

**Why**: Free capture tool that exports to wherever you work.

### iOS Git Support

**Priority**: P1
**Status**: Pending (waiting for team capacity)
**Timeline**: Q1 2026

- Enable native Git sync on iOS
- Build ios-compatible git2dart binaries

### Smart Capture Organization

**Priority**: P2
**Status**: Backlog

- Auto-suggest spheres when saving recordings
- Tag suggestions based on content
- "Similar captures" recommendations

---

## Medium-Term Roadmap (Q1-Q2 2026)

### MCP Integrations

**Priority**: P2
**Status**: Concept

Connect Parachute to other tools via Model Context Protocol:

- Read captures in Claude Desktop
- Surface relevant context automatically
- Integration with other MCP-compatible tools

**Why**: Open protocols for interoperability.

### Local LLM with Personal Context

**Priority**: P2
**Status**: Vision

- On-device LLM (Llama, Gemma) with your actual context
- Privacy-preserving AI assistance
- No cloud dependency for AI features

**Key insight**: "Once Parachute knows your context, why use a generic ChatGPT?"

### Knowledge Graph Visualization

**Priority**: P2
**Status**: Concept

- Visual map of captures, spheres, and relationships
- Timeline view of knowledge evolution
- Pattern recognition across spheres

---

## Long-Term Vision (2026+)

### Plugin Ecosystem (Obsidian Model)

- Rich community contribution ecosystem
- Space plugins for custom functionality
- Small core team, massive extensibility

### Collaborative Spheres

- Share spheres with team members
- Permissions per sphere
- Sync while maintaining privacy for personal content

### AI-Powered Insights

- Weekly summaries of captures
- Pattern detection across spheres
- Proactive suggestions for organization

---

## Feature Request Queue

### Small Enhancements

- [ ] Export conversation as markdown
- [ ] Bulk operations (move, delete, tag)
- [ ] Dark mode refinements
- [ ] Note version history

### Recorder Improvements

- [ ] Audio bookmarks during recording
- [ ] Speaker diarization (multiple speakers)
- [ ] Variable playback speed

### Integration Requests

- [ ] Import from Apple Voice Memos
- [ ] Export to Obsidian format
- [ ] Calendar integration

---

## Technical Debt & Infrastructure

### High Priority

- [ ] Improve error handling and user feedback
- [ ] Performance optimization (large capture lists)
- [ ] Memory usage profiling

### Medium Priority

- [ ] Increase test coverage (target: 80%)
- [ ] E2E testing framework
- [ ] CI/CD pipeline

---

## Non-Goals

Things we've explicitly decided **not** to pursue:

- Social features (likes, followers, feeds)
- Ads or attention-harvesting mechanics
- Required cloud sync (always local-first)
- Lock-in formats (use markdown, JSONL)
- AI training on user data without explicit consent
- Always-on recording (prosocial, not surveillance)

---

## Decision Log

### November 2025

**Spaces renamed to Spheres (Nov 24)**

- "Sphere" speaks to holistic, interconnected nature of knowledge
- Ideas don't live in flat boxes but in overlapping domains of thought
- A capture can exist in multiple spheres simultaneously

**JSONL over SQLite for Sphere Metadata (Nov 24)**

- Git-friendly (no binary merge conflicts)
- Human-readable (can edit with any text editor)
- Simple append-only operations
- SQLite may return for specific use cases, but JSONL is the default

**Reliability Focus (Nov 20-24)**

- Memory leak fixes prioritized over new features
- Race condition prevention in GitSync
- Code cleanup and standardization

**Git Sync Complete (Nov 17)**

- Native Git on macOS and Android
- iOS pending (waiting for team capacity)
- Auto-commit on save, periodic background sync

**Auto-Pause Recording Complete (Nov 10)**

- VAD-based silence detection
- OS-level noise suppression sufficient (RNNoise deferred)
- 116 unit tests for audio pipeline

### October 2025

- Vault-based architecture (Obsidian/Logseq compatible)
- Local-first over cloud-first
- Notes canonical in captures/ (not duplicated)

### September 2025

- Go + Fiber for backend (optional now)
- Flutter + Riverpod for frontend
- SQLite for backend metadata

---

## Roadmap Principles

1. **Local-First**: User owns their data, always
2. **Voice-First**: Natural capture where thinking actually happens
3. **Open & Interoperable**: Standard formats, no lock-in
4. **Privacy by Default**: No tracking, no ads, prosocial
5. **Trust Through Openness**: Open source deserves trust
6. **Sustainable Pace**: Quality over speed

---

## Key Milestones

- **December 5, 2025**: Pitch event (investor meeting)
- **January 2026**: Target first close ($50-75K)
- **April 2026**: CU New Venture Challenge
- **Spring 2026**: Possible Techstars Boulder application

---

## Related Documents

- [ARCHITECTURE.md](ARCHITECTURE.md) - System design and technical decisions
- [CLAUDE.md](CLAUDE.md) - Developer guidance
- [docs/implementation/](docs/implementation/) - Implementation details

---

**Next Update**: After Sphere management implementation

**Feedback**: Open an issue or discussion on GitHub
