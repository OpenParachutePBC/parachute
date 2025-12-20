# Daily Journal Architecture Analysis

**Exploring how Parachute should handle daily capture and journaling**

*December 14, 2025*

---

## Decision: Finalized Format

After discussion, we've landed on an **Obsidian-style flexible approach** with lightweight structure:

### Journal Format

```markdown
---
date: 2025-12-14
assets:
  abc123: assets/2025-12-14_09-15.opus
  def456: assets/2025-12-14_10-30.opus
---

# para:abc123 09:15

Lindsay is looking for a place to rent starting in January.

# para:def456 10:30 Team Meeting

See [[captures/2025-12-14-team-sync]]

# para:ghi789 14:20

Quick thought about API design. Maybe SSE instead of WebSockets.

## Technical considerations

- Latency requirements
- Connection management

# para:jkl012 15:45

Another quick note, this one typed not spoken.
```

### Key Decisions

| Aspect | Decision |
|--------|----------|
| **Section marker** | H1 (`#`) with `para:UUID` prefix |
| **UUID format** | 6 alphanumeric characters |
| **UUID display** | Hidden/shrunk in UI, not user-editable |
| **Default H1 title** | Timestamp (e.g., `09:15`) |
| **Assets** | Mapped in YAML frontmatter by UUID |
| **Short captures** | Transcript inline under H1 |
| **Long captures** | Separate file, journal has link only |
| **Text entries** | Same format, no asset mapping |
| **File location** | `captures/` by default, user can move |

### UUID Registry

Simple file to track existing UUIDs and prevent duplicates:

**Option A: Newline-separated text file** (simplest)
```
# .parachute/uuids.txt
abc123
def456
ghi789
jkl012
```

**Option B: JSON file** (slightly more structured)
```json
{
  "uuids": ["abc123", "def456", "ghi789", "jkl012"]
}
```

**Implementation notes:**
- Load into `Set<String>` on app start for O(1) lookups
- Append-only writes (fast, no rewrite needed)
- Generate UUID, check existence, retry if collision (rare with 2B+ possibilities)
- File location: `.parachute/uuids.txt` in vault root

### UI Behavior

1. **Display**: `para:abc123` is visually hidden or minimized (small, gray, non-editable)
2. **User sees**: Just the title portion (`09:15` or `10:30 Team Meeting`)
3. **Editing**: User can edit title freely, UUID stays intact
4. **Parsing**: App finds sections by regex `^# para:[a-z0-9]{6} (.*)$`

---

## Background Context

The following sections document the exploration that led to this decision.

---

## The Core Vision

Parachute should be a **lightweight capture system** with a daily journal at its heart. Captures can be:
- Voice (transcribed, audio optionally retained)
- Text (typed directly)
- Quick thoughts (single line)
- Substantial content (deserves its own file)

The daily journal should be:
- The natural home for most captures
- Simple to view and navigate
- Processable by AI (individually or in batch)
- Compatible with external tools (Obsidian, Logseq, etc.)

---

## Three Approaches Compared

### Approach A: Obsidian-Style (Flexible Markdown)

**Structure:**
```
Parachute/
├── journals/
│   └── 2025-12-14.md
├── captures/                    # Only promoted/substantial content
│   └── 2025-12-14_10-30-22.md
└── assets/
    └── 2025-12-14_10-30-22.opus
```

**Journal Format:**
```markdown
# 2025-12-14

## 09:15
Lindsay is looking for a place to rent starting in January.

## 09:45
Had a thought about the API design. Maybe we should use SSE instead of WebSockets. Need to check latency requirements.

## 10:30 - Team Meeting
![[2025-12-14_10-30-22]]

Key takeaways:
- Decided on Q1 priorities
- John will own the backend refactor

## 14:20
Quick idea: what if spheres could have sub-spheres?

<!--
{ "id": "abc123", "audio": "assets/2025-12-14_10-30-22.opus", "duration": 847 }
-->
```

**Pros:**
- Maximum flexibility in formatting
- Works great in Obsidian
- HTML comments hide metadata cleanly
- Headers create natural sections
- `![[wikilink]]` embeds full content from other files
- Easy to read as plain markdown

**Cons:**
- No block-level references (can't link to a specific thought)
- Timestamps as headers is a convention, not enforced
- Metadata in HTML comments feels hacky
- Less structured for programmatic processing

**Best For:** Users who primarily read/write in Obsidian, want maximum formatting flexibility, don't need granular block references.

---

### Approach B: Logseq-Style (Block Outliner)

**Structure:**
```
Parachute/
├── journals/
│   └── 2025-12-14.md
├── pages/                       # Promoted content lives here
│   └── Team Meeting 2025-12-14.md
└── assets/
    └── audio-2025-12-14-10-30.opus
```

**Journal Format:**
```markdown
- Lindsay is looking for a place to rent starting in January.
  id:: 550e8400-e29b-41d4-a716-446655440001
  created-at:: 1702548900000
- Had a thought about the API design.
  id:: 550e8400-e29b-41d4-a716-446655440002
	- Maybe we should use SSE instead of WebSockets.
	- Need to check latency requirements.
- [[Team Meeting 2025-12-14]]
  id:: 550e8400-e29b-41d4-a716-446655440003
  audio:: ![audio](../assets/audio-2025-12-14-10-30.opus)
  duration:: 847
	- Key takeaways:
		- Decided on Q1 priorities
		- John will own the backend refactor
- Quick idea: what if spheres could have sub-spheres?
  id:: 550e8400-e29b-41d4-a716-446655440004
```

**Pros:**
- Every thought has a unique ID (can reference from anywhere)
- Block references: `((550e8400-e29b-41d4-a716-446655440001))`
- Native Logseq compatibility
- Properties hidden by default in Logseq UI
- Hierarchical nesting is natural
- Highly structured for programmatic processing

**Cons:**
- UUIDs are verbose and ugly in raw markdown
- Strict bullet-point format (everything is a `-` list item)
- Properties syntax is Logseq-specific
- Less readable in plain text editors
- More complex to implement correctly
- Indentation must be precise (tabs vs spaces matters)

**Best For:** Users who want granular linking, use Logseq, value structure over flexibility.

---

### Approach C: Hybrid (Parachute-Native)

**Structure:**
```
Parachute/
├── journals/
│   └── 2025-12-14.md
├── captures/                    # Substantial recordings only
│   └── 2025-12-14_10-30-22.md
└── assets/
    └── 2025-12-14_10-30-22.opus
```

**Journal Format:**
```markdown
---
date: 2025-12-14
entries: 4
processed: false
---

# December 14, 2025

- 09:15 | Lindsay is looking for a place to rent starting in January.

- 09:45 | Had a thought about the API design. Maybe we should use SSE instead of WebSockets. Need to check latency requirements.

- 10:30 | [[2025-12-14_10-30-22|Team Meeting]] | 14m | has-audio
  > Discussed Q1 priorities. John will own the backend refactor.
  > Decision: Moving forward with SSE approach.

- 14:20 | Quick idea: what if spheres could have sub-spheres?

<!-- metadata
[{"id":"001","ts":1702548900,"type":"text"}]
[{"id":"002","ts":1702550700,"type":"text"}]
[{"id":"003","ts":1702553400,"type":"voice","audio":"assets/2025-12-14_10-30-22.opus","duration":847,"linked":"captures/2025-12-14_10-30-22.md"}]
[{"id":"004","ts":1702567200,"type":"text"}]
-->
```

**Pros:**
- Clean reading experience (timestamps are subtle)
- YAML frontmatter for page-level metadata
- Supports both quick captures and linked substantial content
- Metadata in structured JSON (easy to parse)
- Works in any markdown editor
- `|` delimiter creates visual rhythm
- Blockquotes for summaries/excerpts
- Can evolve format without breaking compatibility

**Cons:**
- Custom format (not native to any existing tool)
- No block references without custom tooling
- JSON metadata block is our own convention
- Would need Parachute-specific processing

**Best For:** Users who want clean daily capture, process through Parachute/agent, don't need Logseq-specific features.

---

## Detailed Comparison Matrix

| Feature | Obsidian-Style | Logseq-Style | Hybrid |
|---------|---------------|--------------|--------|
| **Readability (raw)** | Excellent | Poor (UUIDs) | Very Good |
| **Readability (in app)** | Excellent | Excellent | Excellent |
| **Block references** | No | Yes | No (could add) |
| **Metadata handling** | HTML comments | Properties | JSON block |
| **Nesting** | Flexible | Required (outliner) | Optional |
| **Structure** | Low | High | Medium |
| **Obsidian compat** | Native | Good | Good |
| **Logseq compat** | Partial | Native | Partial |
| **Plain text compat** | Excellent | Poor | Good |
| **Programmatic parsing** | Medium | Easy | Easy |
| **Learning curve** | Low | Medium | Low |
| **Implementation complexity** | Low | High | Medium |

---

## AI Processing Considerations

The agent needs to process journal entries. Each approach has implications:

### Obsidian-Style
```
Agent sees: Freeform markdown, sections by headers
Challenge: Identifying individual entries requires heuristics
Advantage: Natural language, easy to summarize
```

### Logseq-Style
```
Agent sees: Structured blocks with explicit IDs
Challenge: Must understand property syntax
Advantage: Can reference/modify specific blocks precisely
```

### Hybrid
```
Agent sees: Timestamped entries with JSON metadata
Challenge: Custom format to learn
Advantage: Clear structure + clean content separation
```

**Recommendation:** For AI processing, structure helps. Both Logseq-style and Hybrid give the agent clear entry boundaries. Obsidian-style requires more inference.

---

## The Audio Question

Three strategies for audio retention:

### Strategy 1: Always Keep
- Every voice capture saves audio file
- Pro: Never lose original
- Con: Storage grows fast (1 min opus ≈ 100KB, 1 hour/day = 6MB/day = 2GB/year)

### Strategy 2: Configurable Retention
- Default: Keep audio for X days, then delete
- Option: "Star" to keep forever
- Pro: Balanced approach
- Con: Complexity in implementation

### Strategy 3: Transcribe and Discard
- Default: Audio deleted after successful transcription
- Option: Explicit "save audio" toggle per-capture
- Pro: Minimal storage
- Con: Can't re-listen, can't re-transcribe with better model

**Recommendation:** Strategy 2 with smart defaults:
- Quick captures (<1 min): Transcribe, delete audio after 7 days
- Longer recordings: Keep audio for 30 days
- Explicitly saved: Keep forever
- User can adjust all thresholds

---

## The "Substantial Content" Question

When does a capture deserve its own file vs. staying in the journal?

### Option A: Duration-Based
- < 2 minutes → journal entry only
- ≥ 2 minutes → separate file + journal link

### Option B: User-Initiated
- Everything goes to journal by default
- User explicitly "promotes" to standalone file
- Or: User chooses "full recording" mode before capture

### Option C: Content-Based (AI-Assisted)
- Agent analyzes transcript
- If it's a coherent topic with substance → suggest promotion
- If it's quick thoughts/reminders → keep in journal

### Option D: Hybrid Threshold
- < 30 seconds: Journal only, no audio saved
- 30s - 3 min: Journal entry, audio saved temporarily
- > 3 min: Separate file + journal link + audio saved

**Recommendation:** Option D as default, with Option B override (user can always promote/demote).

---

## Proposed Architecture

Based on this analysis, here's a concrete proposal:

### File Structure
```
Parachute/
├── journals/
│   ├── 2025-12-14.md          # Today's journal
│   ├── 2025-12-13.md
│   └── ...
│
├── captures/                   # Substantial content only
│   ├── 2025-12-14_10-30-22.md # Full transcript
│   └── ...
│
├── assets/
│   ├── 2025-12-14_10-30-22.opus  # Retained audio
│   └── ...
│
└── spheres/
    └── work/
        ├── CLAUDE.md
        └── sphere.jsonl
```

### Journal Entry Format (Hybrid approach)
```markdown
---
date: 2025-12-14
---

# Saturday, December 14, 2025

- 09:15 | Lindsay is looking for a place to rent starting in January.

- 09:45 | Had a thought about the API design.
  > Maybe we should use SSE instead of WebSockets.
  > Need to check latency requirements.

- 10:30 | [[2025-12-14_10-30-22|Team Meeting]] | 14:07 | audio
  > Discussed Q1 priorities and backend ownership.

- 14:20 | Quick idea: what if spheres could have sub-spheres?

- 15:00 | Typed note about the project timeline. Need to sync with Sarah on Monday about the deliverables. She mentioned concerns about the deadline.

---
<!-- entries:
{"001":{"ts":1702548900,"type":"text"}}
{"002":{"ts":1702550700,"type":"text"}}
{"003":{"ts":1702553400,"type":"voice","duration":847,"audio":"assets/2025-12-14_10-30-22.opus","file":"captures/2025-12-14_10-30-22.md"}}
{"004":{"ts":1702567200,"type":"text"}}
{"005":{"ts":1702569600,"type":"text"}}
-->
```

### Entry Anatomy
```
- {timestamp} | {content} | {duration}? | {flags}?
  > {summary or additional lines}
```

- **Timestamp**: `HH:MM` format, subtle but parseable
- **Pipe delimiters**: Visual rhythm, easy to parse
- **Duration**: Only for voice captures with audio
- **Flags**: `audio` (has audio file), could add others
- **Blockquote**: Summary, key points, or continuation
- **Wikilink**: `[[file|display text]]` for linked content

### App Behavior

**Quick Capture (< 30s voice or any text):**
1. Transcribe/accept text
2. Append to today's journal
3. No separate file
4. No audio retention (or 7-day temp)

**Standard Capture (30s - 3min voice):**
1. Transcribe
2. Append to journal with summary
3. No separate file
4. Audio retained 30 days

**Full Recording (> 3min or explicit):**
1. Transcribe
2. Create `captures/` file with full transcript
3. Append to journal with link + summary
4. Audio retained (configurable)

**Text Entry:**
1. User types in app
2. Append to journal
3. No audio, no separate file

---

## UI Implications

### Home Screen = Today's Journal
- Shows today's journal entries
- New capture button (mic + keyboard toggle)
- Each entry is tappable to expand/edit
- Long entries show summary, tap to see full

### Capture Flow
```
[Tap mic] → Recording → [Stop] → Transcribing → Entry appears in journal
[Tap keyboard] → Text input → [Done] → Entry appears in journal
```

### Entry Actions
- **Edit**: Modify the text
- **Promote**: Move to standalone file (creates link)
- **Delete**: Remove entry
- **Add to Sphere**: Link to a sphere
- **Keep Audio**: Mark for permanent retention

### Past Days
- Swipe or calendar to navigate
- Each day is a scrollable journal
- Search works across all days

---

## Migration Path

For existing Parachute users (captures in `captures/` folder):

1. **Keep existing captures** - They remain as standalone files
2. **Start journaling** - New quick captures go to journal
3. **Optional consolidation** - Agent can offer to create journal summaries for past days based on existing captures

---

## Open Questions

1. **Sphere integration**: Should journal entries be linkable to spheres? Or only promoted captures?

2. **Tags**: Support `#tags` inline? Or only in metadata?

3. **Time zones**: Store UTC internally, display local? What about travel?

4. **Sync conflicts**: If journal edited on two devices, how to merge?

5. **Search**: Full-text across journals + captures? How to rank results?

6. **Templates**: Should days have customizable templates? (e.g., morning routine prompts)

---

## Recommendation

**Start with the Hybrid approach** because:

1. Clean reading experience prioritized
2. Structured enough for AI processing
3. Flexible enough to evolve
4. Works in Obsidian/any markdown editor
5. Doesn't require complex block ID management
6. Can add Logseq compatibility later if needed

**First implementation:**
1. Journal as home screen
2. Quick text + voice capture to journal
3. Duration-based promotion to files
4. Simple metadata in HTML comment block
5. Audio retention with configurable policy

This gives you the "simple daily journaling experience that can be intelligently processed" without over-engineering the block architecture.

---

## Next Steps

If this direction feels right:

1. **Design the journal UI** - Home screen showing today's entries
2. **Implement journal storage** - Reading/writing the format above
3. **Add text capture** - Keyboard input alongside voice
4. **Build promotion flow** - When/how entries become files
5. **Agent processing** - Daily summaries, entry-by-entry or batch

---

*This is a living document. Update as decisions are made.*
