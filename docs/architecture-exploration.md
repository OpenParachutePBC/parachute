# App/Agent Architecture Exploration

**Status**: Discussion document
**Date**: December 20, 2025

---

## Current Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLIENT DEVICES                            │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │   iPhone     │  │   MacBook    │  │   Android    │           │
│  │  Flutter App │  │  Flutter App │  │  Flutter App │           │
│  │              │  │              │  │              │           │
│  │ • Recording  │  │ • Recording  │  │ • Recording  │           │
│  │ • Transcribe │  │ • Transcribe │  │ • Transcribe │           │
│  │ • Local UI   │  │ • Local UI   │  │ • Local UI   │           │
│  │ • Local vault│  │ • Local vault│  │ • Local vault│           │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘           │
│         │                 │                 │                    │
│         └─────────────────┼─────────────────┘                    │
│                           │ HTTP/SSE                             │
└───────────────────────────┼──────────────────────────────────────┘
                            │
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│                     AGENT SERVER (one instance)                    │
│                     (runs on one machine, e.g., mbp)               │
│                                                                    │
│  • AI orchestration (Claude SDK)                                   │
│  • Session management                                              │
│  • MCP servers (browser, etc.)                                     │
│  • Skills execution                                                │
│  • Writes to local vault                                           │
└───────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│                        VAULT (synced)                              │
│                        ~/Parachute/                                │
│                                                                    │
│  ├── Daily/              # Journal entries                         │
│  ├── assets/             # Media files                             │
│  ├── agent-sessions/     # Chat history                            │
│  ├── .agents/            # Agent definitions                       │
│  └── AGENTS.md           # Personal context                        │
│                                                                    │
│                    ◄──── Syncthing ────►                           │
│                    (bidirectional file sync)                       │
└───────────────────────────────────────────────────────────────────┘
```

### What Each Component Does Today

| Capability | App (Flutter) | Agent (Node.js) |
|------------|---------------|-----------------|
| Voice recording | ✅ | ❌ |
| On-device transcription | ✅ (Parakeet/Sherpa) | ❌ |
| AI chat (Claude) | ❌ (needs server) | ✅ |
| Session persistence | ❌ (reads only) | ✅ (writes markdown) |
| Read local files | ✅ | ✅ |
| Write local files | ✅ (limited) | ✅ (full) |
| RAG/search | ❌ | ❌ (Lucian working on it) |
| Offline mode | Partial (record/view) | N/A |

---

## Key Questions

### 1. Does the server need to run a client?

**Problem**: Some capabilities exist only in the app:
- On-device transcription (Parakeet on iOS/macOS, Sherpa-ONNX on Android)
- Future: syncing coordination
- Future: RAG indexing

**Options**:

**A. Keep them separate (current)**
- Server focuses on AI orchestration
- App handles recording/transcription
- Syncthing handles vault sync
- ✅ Simple, clear separation
- ❌ No way for server to trigger transcription

**B. Embed app capabilities in server**
- Add transcription to server (different library, e.g., whisper.cpp)
- Server becomes more self-sufficient
- ✅ Server can process audio files it finds
- ❌ Duplicated capability, different transcription engines

**C. Server calls back to a client**
- Server registers connected clients as "workers"
- When server needs transcription, it asks a client
- ✅ Reuses existing transcription
- ❌ Complex, requires client to be online

**Recommendation**: **Option A for now** - keep separation clean. Transcription happens at capture time in the app, so server doesn't need it. If we later want server-side processing of audio files, we can add whisper.cpp.

---

### 2. Where does RAG indexing happen?

**Constraints**:
- Agent needs to query RAG for chat context
- App needs to query RAG for offline search
- Multiple clients, one server

**Options**:

**A. Server-only RAG**
```
Client ──query──► Server ──► RAG Index
                              ▲
                        Server builds
```
- ✅ Simple, single source of truth
- ❌ Requires server connection for search
- ❌ Server must be running to index new content

**B. Client-only RAG (each device has index)**
```
Client ──► Local RAG Index
                ▲
           Client builds

Server ──► ??? (no index)
```
- ✅ Works offline
- ❌ Server can't query (big problem for AI context)
- ❌ Index sync is hard

**C. Synced RAG index (SQLite/JSONL)**
```
Client ──► Local RAG Index ◄──► Syncthing ◄──► Other Clients
                                    │
Server ──► Local RAG Index ◄────────┘
```
- ✅ Everyone has the index
- ✅ Works offline
- ✅ Server can query
- ⚠️ Concurrent write conflicts possible
- ⚠️ Index file can get large

**D. Hybrid: Server primary, clients cache**
```
Client ──cache──► Local RAG Cache
                       ▲
                  Fetched from server
                       │
Server ──► Primary RAG Index
               ▲
          Server builds + syncs
```
- ✅ Server is source of truth
- ✅ Clients can search offline (cached)
- ❌ Cache may be stale

**Recommendation**: **Option C** - sync the index file. Use SQLite or JSONL stored in the vault. Each device can read/write. Syncthing handles sync. We accept occasional conflicts (last-write-wins or merge).

---

### 3. Who coordinates what?

**Current model**: Syncthing syncs files, no central coordinator.

**Future needs**:
- RAG index updates when files change
- Conflict resolution for concurrent edits
- Background processing (e.g., auto-summarization)

**Options**:

**A. File-watching on each device**
- Each running instance watches for file changes
- Triggers re-indexing locally
- ✅ Simple, decentralized
- ❌ May duplicate work if multiple devices online

**B. Server coordinates, clients report**
- Clients notify server of changes
- Server coordinates what to index
- ✅ No duplicate work
- ❌ Requires server connection

**C. Leader election among running instances**
- Whichever instance is running becomes "leader"
- Leader handles indexing/processing
- ✅ Avoids duplicate work
- ❌ Complex to implement correctly

**Recommendation**: **Option A** for simplicity. File-watching + local indexing. If file is already indexed (check hash), skip. Duplicate work is acceptable for now.

---

### 4. Offline AI chat?

**Problem**: Currently no AI chat without server connection.

**Options**:

**A. Accept server dependency**
- Keep current model
- App shows "offline" state gracefully
- ✅ Simple
- ❌ No AI when traveling

**B. Local LLM in app**
- Run small model on device (gemma, phi, llama)
- Already have FlutterGemma for titles
- ✅ Works offline
- ❌ Limited capability vs Claude
- ❌ Battery/resource intensive

**C. Embedded agent server in app**
- App includes lightweight Node.js or Dart port
- Runs as background service
- ✅ Full capability offline
- ❌ Complex to package
- ❌ Still needs API key/auth

**Recommendation**: **Option A** for now, with good UX for offline state. Later, consider **Option B** for simple queries using local LLM we already have.

---

## Proposed Architecture (Near-term)

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLIENT DEVICES                            │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                     Flutter App                             │ │
│  │                                                             │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │ │
│  │  │  Recording  │  │ Transcribe  │  │  Local LLM  │        │ │
│  │  │   (audio)   │  │  (Parakeet) │  │  (titles)   │        │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘        │ │
│  │                                                             │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │ │
│  │  │  Vault R/W  │  │  RAG Index  │  │  File Watch │        │ │
│  │  │  (files)    │  │  (SQLite)   │  │  (re-index) │        │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘        │ │
│  │                                                             │ │
│  │  ┌─────────────────────────────────────────────────┐      │ │
│  │  │              Chat Service                        │      │ │
│  │  │  • Online: connect to Agent Server               │      │ │
│  │  │  • Offline: show local sessions, queue messages  │      │ │
│  │  └─────────────────────────────────────────────────┘      │ │
│  └────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────┘
                            │
                            │ When online
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│                     AGENT SERVER                                   │
│                                                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │
│  │  Claude SDK │  │  Session Mgr│  │  MCP/Skills │               │
│  │  (AI chat)  │  │  (markdown) │  │  (browser)  │               │
│  └─────────────┘  └─────────────┘  └─────────────┘               │
│                                                                    │
│  ┌─────────────┐  ┌─────────────┐                                │
│  │  RAG Index  │  │  File Watch │  ← Also indexes, for querying  │
│  │  (SQLite)   │  │  (re-index) │    during chat                 │
│  └─────────────┘  └─────────────┘                                │
└───────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│                        VAULT (synced via Syncthing)                │
│                                                                    │
│  ~/Parachute/                                                      │
│  ├── Daily/                    # Journal entries                   │
│  ├── assets/                   # Media files                       │
│  ├── agent-sessions/           # Chat history                      │
│  ├── .agents/                  # Agent definitions                 │
│  ├── .parachute/               # Parachute app data  ← NEW        │
│  │   ├── index.db              # RAG index (SQLite, synced)       │
│  │   └── index.jsonl           # Append-only log (merge-friendly) │
│  └── AGENTS.md                 # Personal context                  │
└───────────────────────────────────────────────────────────────────┘
```

### Key Changes from Current

1. **RAG index in vault** (`.index/parachute.db`)
   - SQLite database synced via Syncthing
   - Both app and agent can read/write
   - File-watching triggers re-indexing

2. **App can search offline**
   - Query local RAG index
   - Browse/search daily notes, sessions

3. **Agent uses same index**
   - Queries RAG for chat context
   - Indexes new files when it sees them

4. **Graceful offline mode**
   - App shows local content
   - Can queue messages for later send
   - Clear UX for connection state

---

## Implementation Phases

### Phase 1: RAG Foundation (Lucian's work)
- [ ] Create RAG indexer in agent
- [ ] SQLite schema for vault content
- [ ] Index daily notes, sessions, captures
- [ ] Query API for agent to use in chat

### Phase 2: Sync the Index
- [ ] Store index in vault (`.index/`)
- [ ] Handle concurrent access (WAL mode)
- [ ] Syncthing syncs the db file

### Phase 3: App RAG Integration
- [ ] Add SQLite to Flutter app
- [ ] Read the synced index
- [ ] Local search UI
- [ ] File-watching for updates

### Phase 4: Offline Improvements
- [ ] Queue messages when offline
- [ ] Show pending messages in UI
- [ ] Send when connection restored

### Phase 5: Local LLM for Simple Queries (Future)
- [ ] Use existing FlutterGemma
- [ ] Simple Q&A against local context
- [ ] Fallback when server unavailable

---

## Open Questions

1. **SQLite conflict handling** - What happens if two devices write simultaneously?

   **Proposed approach: JSONL + SQLite hybrid**
   - `index.jsonl` - Append-only log of indexed items (content hash, path, timestamp, embeddings)
   - `index.db` - SQLite built from JSONL, used for fast queries
   - On sync conflict: merge JSONL lines (dedupe by hash), rebuild SQLite
   - Each device can independently rebuild SQLite from the JSONL log

   This gives us:
   - ✅ Merge-friendly sync (JSONL is append-only)
   - ✅ Fast queries (SQLite)
   - ✅ Recoverable (can always rebuild from JSONL)

2. **Index size** - Large vaults could have large indexes. Need to test with real data.
   - JSONL grows forever (need periodic compaction)
   - SQLite stays reasonable if we only store references, not full content

3. **Embedding model** - Where do we run embeddings?
   - Server: has more compute, but requires connection
   - Client: works offline, but slower on mobile
   - **Proposed**: Server generates embeddings, syncs via JSONL. Clients can query but not generate.

4. **Agent server discovery** - Currently hardcoded URL. Could use mDNS/Bonjour for local network discovery.

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2025-12-20 | Keep app/agent separate for now | Simpler, clear responsibilities |
| 2025-12-20 | RAG index in vault, synced | Works offline, both can query |
| 2025-12-20 | File-watching for re-index | Decentralized, simple |
| 2025-12-20 | Accept server dependency for AI | Offline AI is complex, defer |
