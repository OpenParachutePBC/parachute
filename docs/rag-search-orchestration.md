# RAG Search Implementation - Orchestration Guide

**For: Orchestrator Agent**
**Created:** December 4, 2025
**Feature Branch:** `rag-search`

---

## Executive Summary

This document provides complete context for orchestrating the implementation of RAG (Retrieval-Augmented Generation) search in Parachute. The work is split into 9 GitHub issues that can be partially parallelized across subagents using git worktrees.

**Goal:** Add hybrid semantic + keyword search to Parachute, enabling users to find recordings by meaning (vector search) and exact terms (BM25).

---

## Important: Concurrent Refactor & Sequencing Strategy

The `refactor-prep-for-rag` branch (PR #21) is simplifying the app architecture:

**Being Removed:**
- Spheres/Spaces feature
- Git sync (GitHub integration)
- Files browser tab
- Chat/Conversations
- Multi-tab navigation → Single HomeScreen

**Kept Intact:**
- Voice recording + VAD
- Whisper transcription
- Gemma title generation
- Recording list/detail views
- StorageService + markdown files

### Sequencing Strategy

**The Plan:** Build backend services on current `main`, then rebase onto refactored app for UI work.

```
Phase 1: Backend (Waves 1-4)
──────────────────────────────
main ─────────────────────────────────────────────────►
      \
       └── rag-search (#19-#27 backend work)
                                            \
Phase 2: Rebase & UI (Wave 5)                \
──────────────────────────────────────────────────────
refactor-prep-for-rag merges to main ────────►
                                              \
                                    rag-search rebased here
                                               \
                                                └── #28 UI work
```

**Why this works:**
- Backend services (#19-#27) are **additive** — new files in `services/embedding/` and `services/search/`
- Refactor is **subtractive** — removing Spheres, Git sync, Tabs
- Minimal overlap = clean rebase (expect minor conflicts in `main.dart` and providers)

**Impact on RAG:**
- Backend services (#19-#27) are **unaffected** by the refactor
- #26 is simplified (no git sync hooks needed — already accounted for in issue)
- #28 (UI) will be built on the refactored single-screen architecture

---

## Table of Contents

1. [Git Workflow](#git-workflow)
2. [Issue Overview](#issue-overview)
3. [Dependency Graph](#dependency-graph)
4. [Execution Waves](#execution-waves)
5. [Subagent Instructions](#subagent-instructions)
6. [Technical Context](#technical-context)
7. [Key Decisions Made](#key-decisions-made)
8. [Open Questions](#open-questions)
9. [Commands Reference](#commands-reference)

---

## Git Workflow

### Branch Strategy

```
main
 └── rag-search (feature branch - all RAG work merges here first)
      ├── rag-search/19-embedding-interface
      ├── rag-search/20-mobile-embedding
      ├── rag-search/22-desktop-embedding
      ├── rag-search/23-chunking-service
      ├── rag-search/24-vector-store
      ├── rag-search/25-bm25-search
      ├── rag-search/26-search-index-service
      ├── rag-search/27-hybrid-search
      └── rag-search/28-search-ui
```

**Important:** PRs should target `rag-search`, NOT `main`. The feature branch will be merged to main once the full feature is complete and tested.

### Setting Up the Feature Branch

```bash
# Create and push the feature branch (do this ONCE at start)
git checkout main
git pull origin main
git checkout -b rag-search
git push -u origin rag-search
```

### Worktree Setup for Parallel Work

Each subagent works in its own worktree to avoid conflicts:

```bash
# Create worktree for an issue (example: issue #19)
git worktree add ../parachute-19-embedding-interface rag-search
cd ../parachute-19-embedding-interface
git checkout -b rag-search/19-embedding-interface

# When done, create PR targeting rag-search branch
gh pr create --base rag-search --title "..." --body "..."
```

### Cleanup After PR Merge

```bash
# Remove worktree after PR is merged
git worktree remove ../parachute-19-embedding-interface
```

### Rebase Onto Refactor (Between Wave 4 and Wave 5)

After all backend services (#19-#27) are merged, rebase onto the refactored app:

```bash
# Ensure refactor PR #21 has been merged to main
gh pr view 21 --json state  # Should show "MERGED"

# Update main and rebase rag-search
git checkout main
git pull origin main
git checkout rag-search
git rebase main

# Resolve any conflicts (expect minor ones in main.dart, providers)
# Then force-push the rebased branch
git push --force-with-lease origin rag-search
```

**Expected conflicts:**
- `app/lib/main.dart` — reconcile app initialization
- Provider files — remove references to deleted features
- Minor import cleanup

**This should take 1-2 hours max** since backend services are in isolated new files.

---

## Issue Overview

| Issue | Title | Effort | Status |
|-------|-------|--------|--------|
| [#19](https://github.com/OpenParachutePBC/parachute/issues/19) | Embedding Interface & Model Manager | 1-2 days | Ready |
| [#20](https://github.com/OpenParachutePBC/parachute/issues/20) | Mobile Embedding (EmbeddingGemma) | 2-3 days | Blocked by #19 |
| [#22](https://github.com/OpenParachutePBC/parachute/issues/22) | Desktop Embedding (Ollama) | 1-2 days | Blocked by #19 |
| [#23](https://github.com/OpenParachutePBC/parachute/issues/23) | Chunking Service | 2-3 days | Blocked by #19 |
| [#24](https://github.com/OpenParachutePBC/parachute/issues/24) | Vector Store (Pure Dart) | 2-3 days | Ready |
| [#25](https://github.com/OpenParachutePBC/parachute/issues/25) | BM25 Keyword Search | 1-2 days | Ready |
| [#26](https://github.com/OpenParachutePBC/parachute/issues/26) | Search Index Service | 2-3 days | Blocked by #23,#24,#25 |
| [#27](https://github.com/OpenParachutePBC/parachute/issues/27) | Hybrid Search Service | 2-3 days | Blocked by #26 |
| [#28](https://github.com/OpenParachutePBC/parachute/issues/28) | Search UI | TBD | **HOLD - Open Design Question** |

### Reading Issue Details

```bash
# View full issue details
gh issue view 19

# List all RAG search issues
gh issue list --search "RAG Search" --state open
```

---

## Dependency Graph

```
                    ┌─────────────────────┐
                    │  #19 Embedding      │
                    │  Interface & Model  │
                    │  Manager            │
                    └──────────┬──────────┘
                               │
           ┌───────────────────┼───────────────────┐
           │                   │                   │
           ▼                   ▼                   ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│ #20 Mobile       │ │ #22 Desktop      │ │ #23 Chunking     │
│ Embedding        │ │ Embedding        │ │ Service          │
│ (EmbeddingGemma) │ │ (Ollama)         │ │                  │
└──────────────────┘ └──────────────────┘ └────────┬─────────┘
                                                   │
┌──────────────────┐ ┌──────────────────┐          │
│ #24 Vector Store │ │ #25 BM25         │          │
│ (Pure Dart)      │ │ Keyword Search   │          │
│ [NO DEPS]        │ │ [NO DEPS]        │          │
└────────┬─────────┘ └────────┬─────────┘          │
         │                    │                    │
         └────────────────────┴────────────────────┘
                              │
                              ▼
                    ┌─────────────────────┐
                    │ #26 Search Index    │
                    │ Service             │
                    │ (Orchestrator)      │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │ #27 Hybrid Search   │
                    │ Service             │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │ #28 Search UI       │
                    │ [WIP - HOLD]        │
                    └─────────────────────┘
```

---

## Execution Waves

### Wave 1: Foundation (Start Immediately - 3 parallel agents)

These have no dependencies and can start right away:

| Issue | Agent Task | Worktree |
|-------|-----------|----------|
| #19 | Embedding Interface & Model Manager | `parachute-19-embedding-interface` |
| #24 | Vector Store (Pure Dart SQLite) | `parachute-24-vector-store` |
| #25 | BM25 Keyword Search | `parachute-25-bm25-search` |

**Orchestrator Action:**
```bash
# Spawn 3 subagents in parallel for Wave 1
# Each agent gets its own worktree and works independently
```

### Wave 2: Embeddings & Chunking (After #19 merges - 3 parallel agents)

| Issue | Agent Task | Worktree |
|-------|-----------|----------|
| #20 | Mobile Embedding (EmbeddingGemma) | `parachute-20-mobile-embedding` |
| #22 | Desktop Embedding (Ollama) | `parachute-22-desktop-embedding` |
| #23 | Chunking Service | `parachute-23-chunking-service` |

**Orchestrator Action:**
```bash
# Wait for #19 PR to merge into rag-search
# Then spawn 3 subagents in parallel for Wave 2
```

**⚠️ Note on #23 (Chunking):** While the interface dependency is only #19, **integration testing** requires a working embedding service (#20 or #22). The #23 agent can:
- Implement and unit test with mock embeddings
- Create PR when code-complete
- Full integration testing happens after #20 or #22 merges

### Wave 3: Index Orchestration (After #23, #24, #25 merge - 1 agent)

| Issue | Agent Task | Worktree |
|-------|-----------|----------|
| #26 | Search Index Service | `parachute-26-search-index` |

**Orchestrator Action:**
```bash
# Wait for #23, #24, #25 PRs to merge into rag-search
# Spawn 1 subagent for Wave 3
```

### Wave 4: Hybrid Search (After #26 merges - 1 agent)

| Issue | Agent Task | Worktree |
|-------|-----------|----------|
| #27 | Hybrid Search Service | `parachute-27-hybrid-search` |

### Wave 4.5: Rebase Checkpoint (After #27, Before #28)

**⚠️ CRITICAL STEP — Do not skip!**

After Wave 4 completes (#27 merged), perform the rebase onto the refactored app:

1. **Verify PR #21 (`refactor-prep-for-rag`) is merged to main**
   ```bash
   gh pr view 21 --json state
   ```
   - If not merged yet, wait or coordinate with user

2. **Rebase `rag-search` onto updated main**
   ```bash
   git checkout main && git pull origin main
   git checkout rag-search && git rebase main
   # Resolve conflicts, then:
   git push --force-with-lease origin rag-search
   ```

3. **Verify backend services still work**
   ```bash
   cd app && flutter test
   cd app && flutter analyze
   ```

4. **Proceed to Wave 5**

---

### Wave 5: UI (After Rebase + Collaborative Design - HOLD)

| Issue | Agent Task | Notes |
|-------|-----------|-------|
| #28 | Search UI | **DO NOT START** - Open design question |

**⚠️ IMPORTANT:** Issue #28 is intentionally underspecified. The search UI design is an **open question** that will be figured out through collaborative discussion after backend services are complete.

**Before starting #28:**
1. All backend services (#19-#27) must be merged to `rag-search`
2. **Wave 4.5 rebase completed** — `rag-search` rebased onto refactored main
3. The `refactor-prep-for-rag` branch (PR #21) must be merged to main
4. Conduct a collaborative design session to riff on UI approaches
5. Update issue #28 with agreed-upon requirements
6. Only then spawn a subagent

---

## Subagent Instructions

### Standard Subagent Prompt Template

When spawning a subagent for an issue, provide this context:

```markdown
## Task
Implement GitHub issue #XX for the Parachute RAG search feature.

## Setup
1. Read the full issue: `gh issue view XX`
2. Create worktree:
   ```bash
   cd /workspace/project
   git fetch origin rag-search
   git worktree add ../parachute-XX-[name] origin/rag-search
   cd ../parachute-XX-[name]
   git checkout -b rag-search/XX-[name]
   ```

## Implementation Guidelines
- Read existing code patterns before writing new code
- Follow patterns in CLAUDE.md and app/CLAUDE.md
- Use Riverpod for state management
- Add unit tests for new functionality
- Use `debugPrint('[ServiceName] message')` for logging

## Key Files to Reference
- `app/lib/core/services/gemma_model_manager.dart` - Model download pattern
- `app/lib/core/services/title_generation_service.dart` - Service pattern
- `app/lib/features/recorder/services/storage_service.dart` - Storage pattern
- `app/lib/core/providers/` - Provider patterns

## PR Guidelines
- Target branch: `rag-search` (NOT main)
- Title format: "feat(search): [description] - closes #XX"
- Include test plan in PR body
- Run `flutter test` before submitting

## Create PR
```bash
gh pr create --base rag-search --title "feat(search): [title] - closes #XX" --body "$(cat <<'EOF'
## Summary
[What this PR does]

## Changes
- [List of changes]

## Test Plan
- [ ] Unit tests pass
- [ ] Manual testing done
- [ ] Works on macOS
- [ ] Works on Android (if applicable)

Closes #XX
EOF
)"
```

## When Done
Report back with:
1. PR URL
2. Summary of what was implemented
3. Any issues or open questions
4. Suggestions for dependent issues
```

### Subagent Success Criteria

Before marking a subagent task complete:
- [ ] All acceptance criteria from the issue are met
- [ ] Unit tests added and passing
- [ ] No linter errors (`flutter analyze`)
- [ ] PR created targeting `rag-search` branch
- [ ] PR description includes test plan

---

## Technical Context

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        RAG Search System                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Markdown Files (Source of Truth - Local)                       │
│  └── ~/Parachute/captures/*.md                                  │
│                                                                  │
│  ┌─────────────────┐        ┌─────────────────┐                 │
│  │ EmbeddingService│        │  Vector Store   │                 │
│  ├─────────────────┤        ├─────────────────┤                 │
│  │ Mobile:         │        │ SQLite + Dart   │                 │
│  │  EmbeddingGemma │        │ cosine similarity│                │
│  │ Desktop:        │        │ (Pure Dart v1)  │                 │
│  │  Ollama         │        │                 │                 │
│  └─────────────────┘        └─────────────────┘                 │
│                                                                  │
│  ┌─────────────────┐        ┌─────────────────┐                 │
│  │ Chunking Service│        │  BM25 Index     │                 │
│  ├─────────────────┤        ├─────────────────┤                 │
│  │ Sentence split  │        │ In-memory       │                 │
│  │ Semantic breaks │        │ Keyword search  │                 │
│  │ Mean-pool embed │        │ bm25 package    │                 │
│  └─────────────────┘        └─────────────────┘                 │
│                                                                  │
│  ┌─────────────────────────────────────────────┐                │
│  │           Search Index Service               │                │
│  │  - Watches for file changes                  │                │
│  │  - Hash-based change detection               │                │
│  │  - Coordinates vector + BM25 indexing        │                │
│  └─────────────────────────────────────────────┘                │
│                                                                  │
│  ┌─────────────────────────────────────────────┐                │
│  │           Hybrid Search Service              │                │
│  │  - Combines vector + BM25 results            │                │
│  │  - Reciprocal Rank Fusion (RRF)             │                │
│  │  - Returns top 20 results                    │                │
│  └─────────────────────────────────────────────┘                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
Recording Saved
      │
      ▼
Search Index Service (detects change via hash)
      │
      ├──► Chunker ──► Sentences ──► Embed ──► Vector Store
      │
      └──► BM25 Index (rebuild from recordings)

User Search Query
      │
      ▼
Hybrid Search Service
      │
      ├──► Embed Query ──► Vector Store ──► Top K chunks
      │
      └──► BM25 Search ──► Top K recordings
      │
      ▼
Merge with RRF ──► Deduplicate ──► Top 20 Results
```

### File Structure (Expected After Implementation)

```
app/lib/core/
├── services/
│   ├── embedding/
│   │   ├── embedding_service.dart           # Abstract interface (#19)
│   │   ├── embedding_model_manager.dart     # Lifecycle (#19)
│   │   ├── mobile_embedding_service.dart    # EmbeddingGemma (#20)
│   │   └── desktop_embedding_service.dart   # Ollama (#22)
│   │
│   └── search/
│       ├── chunking/
│       │   ├── sentence_splitter.dart       # (#23)
│       │   ├── semantic_chunker.dart        # (#23)
│       │   └── recording_chunker.dart       # (#23)
│       │
│       ├── vector_store.dart                # Interface (#24)
│       ├── sqlite_vector_store.dart         # Implementation (#24)
│       ├── bm25_search_service.dart         # (#25)
│       ├── bm25_index_manager.dart          # (#25)
│       ├── search_index_service.dart        # (#26)
│       ├── hybrid_search_service.dart       # (#27)
│       │
│       └── models/
│           ├── chunk.dart
│           ├── indexed_chunk.dart
│           ├── vector_search_result.dart
│           ├── bm25_search_result.dart
│           └── search_result.dart
│
├── providers/
│   ├── embedding_provider.dart              # (#19)
│   ├── search_provider.dart                 # (#27)
│   └── search_index_provider.dart           # (#26)
│
└── models/
    └── embedding_models.dart                # Model types (#19)
```

---

## Key Decisions Made

These decisions were made during planning. Subagents should follow them:

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Embedding dims** | 256 (truncated from 768) | 3x faster search, ~97% quality |
| **Vector store** | Pure Dart + SQLite | No native deps, works everywhere |
| **BM25** | `bm25` Dart package | Pure Dart, isolate-based |
| **Chunking** | Semantic (embedding similarity) | Better than fixed-size for transcripts |
| **Merge strategy** | Reciprocal Rank Fusion (RRF) | Simple, effective, no normalization needed |
| **Result limit** | Top 20 | Reasonable for UI |
| **Model download** | On app start (background) | Proactive, non-blocking |
| **Index storage** | App support dir (gitignored) | Rebuilt per device from source |
| **Change detection** | Content hash (SHA256) | Robust for external edits (Obsidian, etc.) |

---

## Open Questions

These may need orchestrator decisions or user input:

### For #19 (Embedding Interface)
- Should we support API fallback if local model fails?

### For #20 (Mobile Embedding)
- ~~Does `flutter_gemma` support embedding models?~~ **Confirmed** - same package as title generation, just different model
- Model hosting: Need to add EmbeddingGemma to Parachute CDN

### For #22 (Desktop Embedding)
- Auto-pull Ollama model, or require user to run `ollama pull`?
- Which model: `nomic-embed-text` (fast) or `mxbai-embed-large` (quality)?

### For #23 (Chunking)
- Optimal similarity threshold for chunk boundaries? (default: 0.5)
- Should we use VAD segments as chunking hints?

### For #24 (Vector Store)
- Pre-normalize embeddings for faster cosine similarity?

### For #25 (BM25)
- Weight fields differently? (title 2x, transcript 1x)
- Custom stopwords for voice transcripts?

### For #28 (UI) - **OPEN DESIGN QUESTION**

**This is intentionally underspecified.** The search UI will be designed collaboratively after backend services are complete.

Key considerations:
- App is moving to single-screen architecture (no tabs)
- Search location and UX are completely open questions
- Will be figured out through collaborative riffing session
- **Do NOT start this issue without explicit design direction**

---

## Commands Reference

### Git Commands

```bash
# Create feature branch (once)
git checkout main && git pull
git checkout -b rag-search
git push -u origin rag-search

# Create worktree for an issue
git worktree add ../parachute-XX-name origin/rag-search
cd ../parachute-XX-name
git checkout -b rag-search/XX-name

# Remove worktree after PR merge
git worktree remove ../parachute-XX-name

# Sync feature branch with latest
git checkout rag-search
git pull origin rag-search
```

### GitHub CLI Commands

```bash
# View issue
gh issue view 19

# List RAG issues
gh issue list --search "RAG Search" --state open

# Create PR targeting feature branch
gh pr create --base rag-search --title "..." --body "..."

# Check PR status
gh pr status

# Merge PR (after review)
gh pr merge XX --squash

# View PR checks
gh pr checks XX
```

### Flutter Commands

```bash
# Run tests
cd app && flutter test

# Analyze code
cd app && flutter analyze

# Run on macOS
cd app && flutter run -d macos

# Run on Android
cd app && flutter run -d android
```

---

## Orchestration Checklist

### Pre-Flight
- [ ] Feature branch `rag-search` created and pushed
- [ ] All 9 issues exist and are open
- [ ] This document is accessible to subagents

### Wave 1 Execution
- [ ] Spawn subagent for #19 (Embedding Interface)
- [ ] Spawn subagent for #24 (Vector Store)
- [ ] Spawn subagent for #25 (BM25 Search)
- [ ] All 3 PRs created targeting `rag-search`
- [ ] All 3 PRs reviewed and merged

### Wave 2 Execution
- [ ] Confirm #19 is merged
- [ ] Spawn subagent for #20 (Mobile Embedding)
- [ ] Spawn subagent for #22 (Desktop Embedding)
- [ ] Spawn subagent for #23 (Chunking Service)
- [ ] All 3 PRs created targeting `rag-search`
- [ ] All 3 PRs reviewed and merged

### Wave 3 Execution
- [ ] Confirm #23, #24, #25 are merged
- [ ] Spawn subagent for #26 (Search Index Service)
- [ ] PR created targeting `rag-search`
- [ ] PR reviewed and merged

### Wave 4 Execution
- [ ] Confirm #26 is merged
- [ ] Spawn subagent for #27 (Hybrid Search Service)
- [ ] PR created targeting `rag-search`
- [ ] PR reviewed and merged

### Wave 4.5 (Rebase Checkpoint)
- [ ] Confirm #27 is merged (all backend services complete)
- [ ] Verify PR #21 (`refactor-prep-for-rag`) is merged to main
- [ ] Rebase `rag-search` onto updated main
- [ ] Resolve any merge conflicts
- [ ] Run `flutter test` and `flutter analyze` to verify
- [ ] Force-push rebased branch

### Wave 5 (UI - HOLD)
- [ ] Confirm Wave 4.5 rebase is complete
- [ ] **CHECK WITH USER** before starting #28
- [ ] Conduct UI planning session
- [ ] Update issue #28 with requirements
- [ ] Spawn subagent for #28

### Final Integration
- [ ] All issues closed
- [ ] Feature branch `rag-search` fully tested
- [ ] Integration tests pass
- [ ] Create PR: `rag-search` → `main`
- [ ] Final review and merge to main

---

## Contact

For questions about:
- **Technical decisions**: Review this document and issue details
- **UI/UX decisions**: Check with user before proceeding
- **Blockers**: Report to orchestrator for resolution

---

**Document Version:** 1.1
**Last Updated:** December 4, 2025

### Changelog
- **v1.1** (Dec 4, 2025): Added Wave 4.5 rebase checkpoint, clarified sequencing strategy for concurrent refactor
