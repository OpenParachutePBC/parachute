# Markdown Metadata Architecture Research

**Date:** November 6, 2025
**Context:** Deciding between pure markdown (Option A) vs JSON+Markdown (Option B) for recording storage
**Goal:** Maximize Obsidian/Logseq compatibility while maintaining data integrity

---

## Research Findings

### 1. Obsidian's Frontmatter Standards

**Format:** YAML frontmatter (triple-dash delimited)

```markdown
---
title: My Recording
created: 2025-11-06T12:30:00Z
tags: [work, meeting]
duration: 120
source: phone
---

# My Recording

Transcript content here...
```

**Key Learnings:**
- ✅ **YAML frontmatter is THE standard** for Obsidian metadata
- ✅ Must be at the **very top** of the file to work
- ✅ Supports **5 native fields**: `tag`, `tags`, `alias`, `aliases`, `cssclass`
- ✅ **Custom properties** fully supported (duration, source, context, etc.)
- ✅ **Dataview plugin** can query frontmatter for dynamic tables/lists
- ✅ **Templater plugin** uses frontmatter for templates
- ⚠️ **Best practice:** Keep frontmatter **clean and minimal** - only metadata, not content

**Common Patterns:**
```yaml
---
title: string
created: ISO 8601 date
modified: ISO 8601 date
tags: [array, of, strings]
aliases: [alternative, names]
# Custom fields
duration: number (seconds)
source: string (phone|omiDevice)
status: string (processing|completed)
---
```

### 2. Logseq's Format

**Format:** Inline properties with `property:: value` syntax

```markdown
title:: My Recording
created:: 2025-11-06T12:30:00Z
tags:: work, meeting

# My Recording

Transcript content here...
```

**Key Learnings:**
- ❌ **Does NOT use YAML frontmatter** by default
- ✅ Uses `property:: value` syntax (double colon)
- ⚠️ **Interoperability issue:** Logseq files aren't directly compatible with Obsidian frontmatter
- ⚠️ Community requests for standard YAML support exist but not implemented
- ✅ Can be converted but requires tooling

**Compatibility Note:** If we prioritize Obsidian compatibility (which we should based on CLAUDE.md), Logseq is less important since it uses a fundamentally different metadata approach.

### 3. Audio/Voice Note Tools in PKM Ecosystem

**Real-world examples:**

#### v2md (Voice to Markdown)
- Records → Transcribes (OpenAI) → Exports to markdown
- **Obsidian-first design**
- Stores locally in Files app
- Uses simple markdown format

#### Obsidian Audio Notes Plugin
- Uses **callout-style code blocks** for audio metadata:
  ```markdown
  ```audio-note
  audio: recording.wav
  transcript: transcript.srt
  liveUpdate: true
  ```
  ```
- **Not frontmatter-based** - different approach entirely

#### Magic Mic Plugin (Obsidian)
- Records, transcribes, summarizes directly in Obsidian
- Likely uses frontmatter for metadata (standard Obsidian pattern)

#### Talknotes
- Exports in Markdown, PDF, Text formats
- Markdown likely includes frontmatter for timestamps/metadata

**Pattern:** Most voice-to-markdown tools targeting Obsidian **use YAML frontmatter** for metadata.

### 4. CommonMark & Standards

**Critical Finding:**
- ❌ **Frontmatter is NOT part of CommonMark specification**
- ❌ **No universal frontmatter standard exists**
- ✅ **But YAML frontmatter is the de facto standard** across:
  - Jekyll/GitHub Pages
  - Hugo static site generators
  - Obsidian
  - Zola
  - Pandoc
  - Python-Markdown
  - Many others

**Implication:** YAML frontmatter is a **widely-adopted extension**, not a specification. But it's so common that it's effectively the standard.

---

## Option A vs Option B: Deep Comparison

### Option A: Pure Markdown with YAML Frontmatter

```markdown
---
id: 2025-11-06_12-30-00
title: Architecture Discussion
created: 2025-11-06T12:30:00Z
duration: 120
fileSizeKB: 450
source: phone
context: Working on Parachute app
tags: []
transcriptionStatus: completed
titleGenerationStatus: completed
---

# Architecture Discussion

## Context

Working on Parachute app

## Transcription

Today I discussed the architecture decisions...
```

**Files:** `2025-11-06_12-30-00.md` + `2025-11-06_12-30-00.wav`

#### Pros
✅ **Single source of truth** - all data in one file
✅ **Obsidian native** - works perfectly with Dataview, search, templates
✅ **Human-readable** - users can manually edit everything
✅ **Git-friendly** - clean diffs, easy to version
✅ **Portable** - works with any markdown tool
✅ **No sync issues** - can't have markdown/JSON mismatch
✅ **Simpler codebase** - one file format to handle
✅ **Interoperable** - works with Obsidian, Notion, etc.

#### Cons
❌ **Parsing complexity** - need to parse YAML + markdown sections
❌ **Slower queries** - must read full file to get metadata
❌ **Schema validation harder** - YAML is flexible, harder to type-check
❌ **Frontmatter bugs** - we just experienced this with headers bleeding into content
❌ **Size overhead** - frontmatter adds bytes to every file
❌ **Limited structure** - hard to nest complex data

#### Technical Challenges
1. **Parsing:** Need robust YAML parser + markdown section parser
2. **Writing:** Must preserve frontmatter when updating (solved in our current fix)
3. **Querying:** For recordings list, must parse every .md file's frontmatter
4. **Validation:** Can't enforce types in YAML easily

---

### Option B: JSON Metadata + Markdown Content

**Metadata:** `2025-11-06_12-30-00.json`
```json
{
  "id": "2025-11-06_12-30-00",
  "title": "Architecture Discussion",
  "created": "2025-11-06T12:30:00Z",
  "duration": 120,
  "fileSizeKB": 450,
  "source": "phone",
  "context": "Working on Parachute app",
  "tags": [],
  "transcriptionStatus": "completed",
  "titleGenerationStatus": "completed"
}
```

**Content:** `2025-11-06_12-30-00.md`
```markdown
# Architecture Discussion

Today I discussed the architecture decisions...
```

**Files:** `.json` + `.md` + `.wav` (3 files per recording)

#### Pros
✅ **Type-safe metadata** - JSON schema validation
✅ **Fast queries** - parse tiny JSON files, not full markdown
✅ **Clean separation** - metadata vs content concerns separated
✅ **No parsing ambiguity** - JSON is unambiguous
✅ **Better for programmatic access** - JSON easier than YAML
✅ **Scalable** - can query 1000s of recordings quickly
✅ **Already generating JSON** - we create `.json` files now (unused)

#### Cons
❌ **NOT Obsidian-compatible** - Obsidian won't read .json metadata
❌ **Two files to sync** - must keep JSON + MD in sync
❌ **Sync conflicts harder** - JSON and MD can diverge
❌ **Not human-editable** - users can't easily edit metadata
❌ **Less portable** - requires both files to make sense
❌ **Git noise** - changes to title updates both JSON + MD
❌ **Violates "single source of truth"** - duplication risk

#### Technical Challenges
1. **Sync:** Must update JSON when MD changes (and vice versa)
2. **Integrity:** Can JSON and MD get out of sync? (Yes - big risk!)
3. **Obsidian compatibility:** Users opening folder in Obsidian won't see metadata
4. **Portability:** Export/import requires both files

---

## Real-World Scenarios

### Scenario 1: User opens `~/Parachute/captures/` in Obsidian

**Option A (YAML Frontmatter):**
- ✅ **Works perfectly** - Obsidian reads frontmatter, shows in properties panel
- ✅ User can search by tags, dates, duration
- ✅ Dataview queries work: `TABLE duration WHERE source = "omiDevice"`
- ✅ Templates can use frontmatter variables
- ✅ Links between recordings and spaces work

**Option B (JSON + Markdown):**
- ❌ **Partial compatibility** - Obsidian only sees markdown content
- ❌ No frontmatter properties panel
- ❌ Can't query duration, source, tags (metadata in separate .json)
- ❌ User has to manually edit .json files (poor UX)
- ❌ Dataview can't access metadata

**Winner:** Option A by far

---

### Scenario 2: Parachute app queries 500 recordings for list view

**Option A (YAML Frontmatter):**
- ❌ Must read 500 `.md` files
- ❌ Parse YAML frontmatter from each (slow regex/parsing)
- ❌ Extract metadata (title, timestamp, duration, etc.)
- ⚠️ Could be slow on low-end devices
- ✅ But: Can cache, use file watchers, etc.

**Option B (JSON + Markdown):**
- ✅ Read 500 tiny `.json` files (fast!)
- ✅ Parse JSON (native, very fast)
- ✅ Don't need to touch `.md` files at all
- ✅ Much better performance

**Winner:** Option B for performance

---

### Scenario 3: User edits recording in Obsidian directly

**Option A (YAML Frontmatter):**
- ✅ User edits frontmatter in Obsidian UI (properties panel)
- ✅ User edits transcript in markdown editor
- ✅ Changes saved to single file
- ✅ Parachute re-reads file and sees changes
- ✅ Git commit shows clean diff

**Option B (JSON + Markdown):**
- ❌ User edits markdown in Obsidian
- ❌ But metadata is in separate .json file
- ❌ Parachute might not detect markdown changes
- ❌ JSON and MD can become inconsistent
- ❌ Which is source of truth for title? JSON or MD first line?

**Winner:** Option A for user editability

---

### Scenario 4: Git sync with merge conflicts

**Option A (YAML Frontmatter):**
- Single file conflict: `2025-11-06_12-30-00.md`
- User resolves conflict in one place
- Frontmatter + content merged together
- ✅ Simpler conflict resolution

**Option B (JSON + Markdown):**
- Potential for **two separate conflicts**:
  - `2025-11-06_12-30-00.json`
  - `2025-11-06_12-30-00.md`
- Must resolve both and ensure consistency
- Higher chance of ending up in bad state
- ❌ More complex conflict resolution

**Winner:** Option A for Git workflows

---

### Scenario 5: Future Space SQLite integration

**Option A (YAML Frontmatter):**
- Parse frontmatter to extract metadata
- Store reference in space.sqlite: `{note_path, title, timestamp}`
- Query markdown for full content when needed
- ⚠️ Must parse YAML every time we index

**Option B (JSON + Markdown):**
- Read `.json` directly into SQLite
- Much faster indexing
- Can query JSON for metadata without parsing
- ✅ Better for database workflows

**Winner:** Option B for database integration

---

## Hybrid Option C: YAML Frontmatter + Optional JSON Cache

What if we got the best of both worlds?

**Primary:** `2025-11-06_12-30-00.md` (YAML frontmatter + content)
**Cache:** `.parachute/cache/2025-11-06_12-30-00.json` (auto-generated, gitignored)

**How it works:**
1. **Single source of truth:** Markdown file with YAML frontmatter
2. **Performance cache:** Auto-generate JSON cache files on-demand
3. **Fast queries:** Read cache if exists and is fresh (check mtime)
4. **Obsidian compatible:** Users only see `.md` files
5. **No sync issues:** Cache is local-only, never synced

**Implementation:**
```dart
Future<List<Recording>> getRecordings() async {
  final mdFiles = await _findMarkdownFiles();

  for (final mdFile in mdFiles) {
    final cacheFile = _getCacheFile(mdFile);

    // Use cache if fresh
    if (await _isCacheFresh(cacheFile, mdFile)) {
      recordings.add(await _loadFromCache(cacheFile));
    } else {
      // Parse markdown, rebuild cache
      final recording = await _loadFromMarkdown(mdFile);
      await _writeCache(cacheFile, recording);
      recordings.add(recording);
    }
  }
}
```

#### Pros
✅ All the Obsidian compatibility of Option A
✅ All the query performance of Option B
✅ Single source of truth (markdown)
✅ Cache is transparent to users
✅ Works offline
✅ Git-friendly (cache is gitignored)

#### Cons
❌ More complex implementation
❌ Cache invalidation logic needed
❌ Disk space for cache (negligible)
⚠️ Need to handle cache corruption gracefully

---

## Recommendation

### Primary Recommendation: **Option A (Pure YAML Frontmatter)** with future cache optimization

**Rationale:**

1. **Obsidian compatibility is paramount** - This is in CLAUDE.md as a core principle
2. **User empowerment** - Users can edit files directly in any tool
3. **Git-first architecture** - Single file = cleaner version control
4. **Simplicity** - One format, one source of truth, fewer bugs
5. **Industry standard** - YAML frontmatter is widely adopted
6. **Performance is acceptable** - Modern devices can parse hundreds of YAML files quickly
7. **Future-proof** - Can add Option C cache later if needed

### What We Need to Fix

Our current bug shows we need **better YAML/Markdown parsing**. Here's the fix strategy:

1. ✅ **Use a proper YAML parser** (instead of manual parsing)
2. ✅ **Separate content from metadata** (don't mix headers into transcript)
3. ✅ **Schema validation** (validate frontmatter structure on load)
4. ✅ **Consistent write format** (always write the same structure)

**Proposed Structure:**
```markdown
---
id: 2025-11-06_12-30-00
title: Architecture Discussion
created: 2025-11-06T12:30:00Z
duration: 120
source: phone
context: Working on Parachute app
tags: []
---

# Architecture Discussion

Today I discussed the architecture decisions...
```

**Rules:**
- Frontmatter contains ALL metadata (title, context, duration, source)
- Body contains ONLY content (transcript)
- Title MAY appear as H1 in body for readability (optional, not required)
- Context is in frontmatter, NOT in body sections
- Parse frontmatter as authoritative source for all metadata

### Secondary Option: **Option C (YAML + Cache)** if performance becomes an issue

If we hit performance problems with 1000+ recordings:
- Keep Option A as-is
- Add `.parachute/cache/` folder (gitignored)
- Auto-generate JSON cache on first read
- Invalidate cache when file mtime changes
- Transparent to users

---

## Action Items

1. ✅ **Fix current parsing bug** (in progress)
2. [ ] **Add YAML library** - Use proper parser instead of manual string manipulation
3. [ ] **Document frontmatter schema** - What fields are required/optional
4. [ ] **Add validation** - Warn on malformed frontmatter
5. [ ] **Write tests** - Ensure parsing is robust
6. [ ] **Update docs** - Show users the proper format for manual editing

---

## Conclusion

**Go with Option A: Pure Markdown with YAML Frontmatter**

This aligns with:
- ✅ Local-first principles (single file)
- ✅ Obsidian/PKM compatibility (industry standard)
- ✅ User ownership (human-editable)
- ✅ Git-friendly architecture (clean diffs)
- ✅ Simplicity (one source of truth)

The current bug is a parsing issue, not a fundamental architecture problem. Fix the parser, and we'll have a robust, compatible, user-friendly system.

If performance becomes an issue later, we can add a transparent cache layer (Option C) without changing the user-facing format.

---

**Last Updated:** November 6, 2025
**Decision:** Option A (YAML Frontmatter) ✅
**Status:** Proceeding with parser fix
