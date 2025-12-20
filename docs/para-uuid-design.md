# Para UUID System Design

**Status**: Design discussion
**Date**: December 20, 2025

---

## Current State

### Journal Entries
```markdown
# para:abc123 Morning thoughts

Content here...
```
- 6-character alphanumeric IDs (36^6 = ~2.1 billion)
- Tracked in `.parachute/uuids.txt`
- Each entry has unique ID

### Chat Messages
```markdown
### User | 2025-12-20T10:30:00Z

Message content...

### Assistant | 2025-12-20T10:31:00Z

Response...
```
- **No unique IDs** for messages
- Only session has an ID

### Assets
```
assets/2025-12/2025-12-20_143022_audio.wav
```
- Timestamp-based naming
- **No para:uuid**

---

## Proposed Design

### 1. Longer IDs

**Current**: 6 characters (2.1 billion combinations)
**Proposed**: 12 characters (4.7 quintillion combinations)

```
Old: para:abc123
New: para:abc123def456
```

**Rationale**:
- More headroom for growth
- Less collision risk as system scales
- Still human-readable/typeable
- Backwards compatible (can coexist with 6-char IDs)

**Migration**: Keep supporting 6-char, generate 12-char going forward.

---

### 2. Chat Message IDs

**Current format**:
```markdown
### User | 2025-12-20T10:30:00Z
```

**Proposed format**:
```markdown
### para:abc123def456 User | 2025-12-20T10:30:00Z
```

This mirrors the journal entry format (`# para:ID Title`).

**Benefits**:
- Every message is addressable
- Can link to specific messages: `[[session-name#para:abc123def456]]`
- Enables message-level operations (edit, delete, branch)
- Import/export preserves identity

**In session markdown**:
```markdown
---
session_id: "sess_xyz789"
...
---

# Project Discussion

## Conversation

### para:abc123def456 User | 2025-12-20T10:30:00Z

What's the best way to structure this?

### para:ghi789jkl012 Assistant | 2025-12-20T10:31:00Z

I'd recommend starting with...
```

---

### 3. Asset IDs

**Current**:
```
assets/2025-12/2025-12-20_143022_audio.wav
```

**Proposed**:
```
assets/2025-12/para_abc123def456_audio.wav
```

Or with frontmatter in a sidecar file:
```
assets/2025-12/abc123def456.wav
assets/2025-12/abc123def456.json  # metadata
```

**Metadata sidecar** (optional):
```json
{
  "para_id": "abc123def456",
  "created_at": "2025-12-20T14:30:22Z",
  "type": "audio",
  "format": "wav",
  "duration_seconds": 45,
  "source": "journal_voice_entry",
  "linked_from": ["daily/2025-12-20.md"]
}
```

**Benefits**:
- Assets are addressable
- Can query "all assets linked to this entry"
- Enables orphan detection
- Supports future features (thumbnails, transcripts, etc.)

---

### 4. Session IDs

Currently sessions have IDs like `sess_1734567890123`.

**Proposed**: Also use para:uuid format:
```markdown
---
session_id: "para:mno345pqr678"
...
---
```

This unifies all IDs under one system.

---

## ID Registry

### Current: `.parachute/uuids.txt`
```
abc123
def456
ghi789
```

### Proposed: `.parachute/ids.jsonl`
```jsonl
{"id":"abc123def456","type":"entry","created":"2025-12-20T10:00:00Z","path":"Daily/2025-12-20.md"}
{"id":"ghi789jkl012","type":"message","created":"2025-12-20T10:30:00Z","path":"agent-sessions/project-chat.md"}
{"id":"mno345pqr678","type":"asset","created":"2025-12-20T14:30:00Z","path":"assets/2025-12/para_mno345pqr678_audio.wav"}
```

**Benefits**:
- Type information for each ID
- Path for reverse lookup
- Created timestamp for ordering
- JSONL format is append-only, sync-friendly
- Can rebuild from scanning files if lost

---

## Implementation Plan

### Phase 1: Extend ParaIdService ✅ COMPLETE
- [x] Support 12-character IDs (keep 6-char for backwards compat)
- [x] Add `type` parameter to `generate()`: entry, message, asset, session
- [x] Migrate storage to `.parachute/ids.jsonl`
- [x] Keep reading old `uuids.txt` for backwards compat

### Phase 2: Chat Message IDs ✅ COMPLETE
- [x] Update agent's `sessionToMarkdown()` to include message IDs
- [x] Update agent's message parsing to read IDs
- [x] Update app's `LocalSessionReader` to parse message IDs
- [x] Update app's `ChatMessage` model with `paraId` field

### Phase 3: Asset IDs
- [ ] Update `FileSystemService.generateAssetFilename()` to use para:uuid
- [ ] Create optional metadata sidecar generation
- [ ] Update migration service for existing assets

### Phase 4: Session IDs
- [ ] Migrate session IDs to para:uuid format
- [ ] Update session manager
- [ ] Backwards compat for existing sessions

---

## Linking Syntax

With para:uuid on everything, we can link precisely:

```markdown
See my thoughts in [[Daily/2025-12-20#para:abc123def456]]

This relates to our discussion in [[agent-sessions/project-chat#para:ghi789jkl012]]

Audio recording: ![[assets/2025-12/para_mno345pqr678_audio.wav]]
```

---

## Open Questions

1. **ID length**: 12 chars feels right. 8 too short? 16 too long?

2. **Separator**: Currently using `para:`. Alternatives:
   - `p:abc123` (shorter)
   - `#abc123` (conflicts with markdown headers)
   - `@abc123` (conflicts with mentions)
   - Keep `para:` for clarity

3. **Asset naming**:
   - Include para:uuid in filename? `para_abc123_audio.wav`
   - Or just uuid? `abc123def456.wav`
   - Or keep timestamp + add uuid? `2025-12-20_143022_abc123def456.wav`

4. **Registry sync**: JSONL syncs via Syncthing. Conflicts?
   - Append-only, so just concatenate on conflict
   - Dedupe by ID when reading

---

## Backwards Compatibility

- 6-char IDs continue to work
- Old format parsing still supported
- New files use 12-char IDs
- Gradual migration, no flag day
