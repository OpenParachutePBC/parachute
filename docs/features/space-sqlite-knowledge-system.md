# Space SQLite Knowledge System

**Status**: 📅 Planned - Deferred until Git Sync complete
**Priority**: P1 - High Priority (Next after Git sync)
**Started**: October 27, 2025
**Updated**: November 6, 2025 - Reoriented for Flutter-first approach

---

## Vision

Enable spaces to have structured knowledge management while keeping notes canonical and cross-pollinating between contexts. Each space gets its own SQLite database to track relationships, context, and metadata without duplicating the source files.

### Core Principle

**"One folder, one file system that organizes your data to enable it to be open and interoperable"**

### Strategic Update (Nov 6, 2025)

This feature is being **reoriented for Flutter-first architecture**:

- **Primary implementation**: Flutter app with local SQLite (via `sqflite` package)
- **Backend role**: Optional - for agentic AI features only (deferred)
- **Git integration**: space.sqlite files sync via Git along with other vault data
- **Local-first**: All space knowledge operations work offline

---

## Problem Statement

Currently:

- Recordings are saved to `~/Parachute/captures/` as canonical files
- Spaces exist in `~/Parachute/spaces/` with their own directories
- No structured way to link captures to spaces
- No space-specific contextualization of notes
- Notes can't effectively "cross-pollinate" between spaces

**We need:**

- Link notes to multiple spaces with different context per space
- Query and filter notes within a space
- Track relationships without duplicating files
- Enable each space to have custom structure as needed

---

## Solution Architecture

### File Structure

```
~/Parachute/
├── captures/                           # SOURCE OF TRUTH
│   ├── 2025-10-26_00-00-17.md        # Canonical note content
│   ├── 2025-10-26_00-00-17.wav       # Audio recording
│   └── 2025-10-26_00-00-17.json      # Recording metadata
│
└── spaces/
    ├── regen-hub/
    │   ├── CLAUDE.md                  # System prompt for this space
    │   ├── space.sqlite               # 🆕 Space-specific database
    │   └── files/                     # Space-specific files
    │
    └── personal/
        ├── CLAUDE.md
        ├── space.sqlite               # 🆕 Different context for same notes
        └── files/
```

### Space SQLite Schema

Every space has a `space.sqlite` database with this base schema:

```sql
-- Metadata about the space database itself
CREATE TABLE space_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

INSERT INTO space_metadata VALUES
    ('schema_version', '1'),
    ('space_id', '<uuid-from-backend>'),
    ('created_at', '<unix-timestamp>');

-- Core table: Links captures with space-specific context
CREATE TABLE relevant_notes (
    id TEXT PRIMARY KEY,                      -- UUID for this link
    capture_id TEXT NOT NULL,                 -- Links to capture's JSON id
    note_path TEXT NOT NULL,                  -- Relative: captures/YYYY-MM-DD_HH-MM-SS.md
    linked_at INTEGER NOT NULL,               -- Unix timestamp
    context TEXT,                             -- Space-specific interpretation
    tags TEXT,                                -- JSON array: ["regeneration", "farming"]
    last_referenced INTEGER,                  -- Track when used in conversation
    metadata TEXT,                            -- JSON: extensible per-space
    UNIQUE(capture_id)                        -- One entry per capture per space
);

-- Indexes for performance
CREATE INDEX idx_relevant_notes_tags ON relevant_notes(tags);
CREATE INDEX idx_relevant_notes_last_ref ON relevant_notes(last_referenced);
CREATE INDEX idx_relevant_notes_linked_at ON relevant_notes(linked_at DESC);
```

---

## Data Flow

### 1. Recording a Voice Note

```
User records → Saves to ~/Parachute/captures/
                ├── .wav (audio)
                ├── .json (metadata)
                └── .md (transcript)
```

### 2. Linking Note to Space(s)

```
User: "Link this capture to Regen Hub and Personal spaces"

Flutter App:
  1. Shows LinkCaptureToSpaceScreen
  2. User selects spaces (multi-select)
  3. For each space:
     - Add context (text)
     - Add tags (chips)
  4. On save:
     - Open ~/Parachute/spaces/<space-name>/space.sqlite
     - INSERT INTO relevant_notes (...)
     - Close database
     - Commit to Git (if configured)
```

### 3. Browsing Space Notes

```
User opens Regen Hub space

Flutter App:
  1. Open ~/Parachute/spaces/regen-hub/space.sqlite
  2. SELECT * FROM relevant_notes ORDER BY linked_at DESC
  3. For each row:
     - Read note content from ~/Parachute/captures/
     - Combine with space-specific context
  4. Display in UI
```

### 4. Git Sync Integration

```
After linking notes:
  1. space.sqlite file is modified
  2. GitService detects changes
  3. Auto-commit: "Update space links"
  4. Push to GitHub

On other device:
  1. Pull from GitHub
  2. space.sqlite updated
  3. UI reflects new links
```

---

## Implementation Plan (Flutter-First)

### Phase 1: Flutter SQLite Foundation

**Goal**: Local space database management in Flutter

**Tasks**:

- [ ] Add `sqflite` package to Flutter dependencies
- [ ] Create `SpaceDatabaseService` (`lib/core/services/space_database_service.dart`)
  - [ ] `initializeSpaceDatabase(spacePath)` - Creates space.sqlite in space folder
  - [ ] `linkNote({spaceId, captureId, notePath, context, tags})` - Links capture
  - [ ] `getRelevantNotes(spaceId, {filters})` - Queries linked notes
  - [ ] `updateNoteContext(spaceId, captureId, newContext)` - Updates context
  - [ ] `unlinkNote(spaceId, captureId)` - Removes link
  - [ ] `trackNoteReference(spaceId, captureId)` - Updates last_referenced

- [ ] Space model updates
  - [ ] Add `databasePath` getter to Space model
  - [ ] Initialize space.sqlite when creating new space
  - [ ] Auto-create space.sqlite for existing spaces (migration)

- [ ] Riverpod providers
  - [ ] `spaceDatabaseServiceProvider` - Service instance
  - [ ] `relevantNotesProvider(spaceId)` - Fetch linked notes for a space
  - [ ] `noteLinksProvider(captureId)` - Get all spaces a note is linked to

**Code Locations**:

- Service: `app/lib/core/services/space_database_service.dart`
- Models: `app/lib/features/spaces/models/relevant_note.dart`
- Providers: `app/lib/features/spaces/providers/space_database_providers.dart`

---

### Phase 2: Note Linking UI

**Goal**: User can link recordings to spaces

**Tasks**:

- [ ] Create `LinkCaptureToSpaceScreen`
  - [ ] Multi-select space picker (checkboxes)
  - [ ] For each selected space:
    - Context text field (multiline)
    - Tag chips input (add/remove)
  - [ ] Visual indicator of already-linked spaces
  - [ ] Save button → calls `SpaceDatabaseService.linkNote()`

- [ ] Enhance `RecordingDetailScreen`
  - [ ] Add "Link to Space" button in app bar
  - [ ] Show which spaces note is linked to (badge chips)
  - [ ] Quick-link buttons for recent/favorite spaces
  - [ ] Tap badge to edit context for that space

- [ ] Create models
  - [ ] `RelevantNote` model (maps to relevant_notes table)
  - [ ] `NoteLinkRequest` model (for linking flow)

**Code Locations**:

- Screen: `app/lib/features/space_notes/screens/link_capture_to_space_screen.dart`
- Models: `app/lib/features/space_notes/models/relevant_note.dart`
- Enhanced: `app/lib/features/recorder/screens/recording_detail_screen.dart`

---

### Phase 3: Space Note Browser

**Goal**: Browse and manage linked notes within a space

**Tasks**:

- [ ] Create `SpaceNotesScreen` (or enhance existing SpaceFilesWidget)
  - [ ] "Linked Notes" tab/section
  - [ ] Query and display relevant_notes using provider
  - [ ] Show note cards with:
    - Title, preview
    - Space-specific context
    - Tags (chips)
    - Last referenced timestamp
  - [ ] Tap to open note with space context overlay

- [ ] Create `NoteWithSpaceContextScreen`
  - [ ] Display markdown note content
  - [ ] Overlay space context at top (card/banner)
  - [ ] Show tags for this space
  - [ ] "Edit Context" button → inline editing
  - [ ] "Unlink from Space" button → confirmation dialog

- [ ] Add filtering/sorting
  - [ ] Filter by tags (chip filter bar)
  - [ ] Sort by: linked date, last referenced, alphabetical
  - [ ] Search within space notes (full-text search)

**Code Locations**:

- Screen: `app/lib/features/space_notes/screens/space_notes_screen.dart`
- Screen: `app/lib/features/space_notes/screens/note_with_context_screen.dart`
- Widgets: `app/lib/features/space_notes/widgets/`

---

### Phase 4: Git Sync Integration

**Goal**: space.sqlite files sync via Git

**Tasks**:

- [ ] Hook into Git auto-commit flow
  - [ ] After linking/unlinking notes, mark space.sqlite as modified
  - [ ] Include in next Git commit
  - [ ] Commit message: "Update space: <space-name> links"

- [ ] Pull handling
  - [ ] After Git pull, invalidate `relevantNotesProvider` cache
  - [ ] Reload space notes from updated space.sqlite
  - [ ] Show notification if new links detected

- [ ] Conflict handling
  - [ ] Detect SQLite conflicts after Git merge
  - [ ] Strategy: "Last write wins" for different notes (MVP)
  - [ ] Alert user to manual resolution if same note changed

**Note**: This phase depends on Git sync completion (Priority 2)

---

### Phase 5 (Future): Backend Integration

**Goal**: Optional backend support for agentic AI

**Deferred until**:

- Flutter implementation complete
- Git sync stable
- Backend refocused on agentic AI tasks

**Potential Backend Features**:

- Claude references notes in conversations
- Auto-suggest spaces when saving recordings
- Semantic search across space notes
- CLAUDE.md template variable expansion

---

## Benefits

### 1. Notes Stay Canonical

- One `.md` file in `captures/`, never duplicated
- Audio and metadata stay with note
- Easy to backup, sync, version control

### 2. Polyvalent Context

- Same note has different meanings in different spaces
- `context` field allows space-specific interpretation
- Tags can differ per space

### 3. Cross-Pollination

- Notes aren't trapped in one space
- Ideas flow between projects/contexts
- Discover connections across domains

### 4. Structured Querying

- SQL enables powerful filtering
- "Show me farming notes from Q4 2025"
- "Which notes are linked to both Regen Hub and Personal?"

### 5. Extensible

- Spaces can add custom tables (future)
- Templates for common space types
- Future: plugins/extensions per space

### 6. Local-First + Git Sync

- All operations work offline
- Git syncs space.sqlite files automatically
- No custom backend sync infrastructure needed

---

## Migration Strategy

### For Existing Spaces

1. **Auto-Initialize** - Flutter creates `space.sqlite` when first accessed
2. **No Breaking Changes** - Spaces work exactly as before
3. **Opt-In Linking** - Notes don't auto-link, user chooses when
4. **Incremental Adoption** - Link notes as you go, no need to backfill

### For New Spaces

1. **Auto-Create** - `space.sqlite` created when space is created
2. **Optional Template** - User can select space type/template (future)
3. **Guided Setup** - Wizard suggests initial structure (future)

---

## Testing Strategy

### Unit Tests

- [ ] `SpaceDatabaseService` methods
- [ ] Schema creation and migration
- [ ] CRUD operations for relevant_notes
- [ ] Error handling (corrupt DB, disk full, etc.)

### Integration Tests

- [ ] End-to-end note linking flow
- [ ] Space note browser with real data
- [ ] Git sync with space.sqlite changes

### Performance Tests

- [ ] Query performance with 100+ notes per space
- [ ] Multiple spaces with overlapping notes
- [ ] Large space.sqlite files (10MB+)

---

## Success Metrics

- [ ] Spaces can link to multiple captures
- [ ] Same capture can exist in multiple spaces with different context
- [ ] Users can browse space-specific notes easily
- [ ] Git sync includes space.sqlite files
- [ ] Note usage tracked (last_referenced)
- [ ] No performance degradation with 100+ notes per space
- [ ] Works completely offline

---

## Dependencies

### Flutter Packages

- `sqflite` - Local SQLite database access
- `path` - File path manipulation (already in use)
- `flutter_riverpod` - State management (already in use)

### No Backend Changes Required

This feature can be fully implemented in Flutter without backend changes. Backend integration is optional and deferred.

---

## Open Questions

- [ ] Should spaces support custom table templates?
- [ ] How to handle bulk linking operations?
- [ ] Should spaces be able to auto-subscribe to notes by tag?
- [ ] What's the discovery UX for notes that should be linked?
- [ ] Should we support note hierarchies/collections within spaces?
- [ ] How to handle space.sqlite merge conflicts in Git?

---

## Related Documents

- [ARCHITECTURE.md](../../ARCHITECTURE.md) - Overall system design
- [ROADMAP.md](../../ROADMAP.md) - Future features queue
- [CLAUDE.md](../../CLAUDE.md) - Developer guidance
- [docs/recorder/](../recorder/) - Voice recording implementation
- [docs/architecture/git-sync-strategy.md](../architecture/git-sync-strategy.md) - Git sync architecture

---

**Last Updated**: November 6, 2025
**Next Review**: After Git sync completion (target: mid-November 2025)
