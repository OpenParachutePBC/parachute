# Sphere Management

**Status:** Next Up
**Priority:** P1
**Last Updated:** November 24, 2025

---

## Overview

Spheres are themed knowledge containers that organize captures. Each sphere has:

- A `CLAUDE.md` system prompt for AI conversations
- A `sphere.jsonl` file for linked captures and metadata
- A `files/` directory for sphere-specific files

## Why "Spheres"?

The term speaks to the holistic, interconnected nature of knowledge—ideas don't live in flat boxes but in overlapping domains of thought. A capture can exist in multiple spheres simultaneously with different context in each.

**Previous terminology:** "Spaces" - renamed to better reflect the philosophy.

---

## Data Format

### sphere.jsonl

Metadata stored as JSON Lines (one JSON object per line):

```jsonl
{"type":"link","capture":"2025-11-24_10-30-00","linkedAt":"2025-11-24T10:35:00Z","context":"Meeting notes from standup"}
{"type":"tag","name":"project-alpha","addedAt":"2025-11-24T10:36:00Z"}
{"type":"note","content":"Key insight about architecture","createdAt":"2025-11-24T10:40:00Z"}
```

**Entry Types:**

- `link` - Links a capture to this sphere with optional context
- `tag` - Adds a tag for organization
- `note` - Sphere-specific notes (not in captures/)

### Why JSONL over SQLite?

- **Git-friendly** - No binary merge conflicts
- **Human-readable** - Can edit with any text editor
- **Simple** - Append-only operations
- **Debuggable** - Easy to inspect and fix
- **Standard** - Works with grep, jq, etc.

**Note:** SQLite was previously considered (see `docs/archive/2025-11/space-sqlite-knowledge-system.md`) but JSONL better fits our local-first, git-based architecture.

---

## File Structure

```
{vault}/{spheres}/
├── work/
│   ├── CLAUDE.md           # System prompt for AI conversations
│   ├── sphere.jsonl        # Linked captures and metadata
│   └── files/              # Sphere-specific files
│
└── personal/
    ├── CLAUDE.md
    ├── sphere.jsonl
    └── files/
```

---

## CLAUDE.md System Prompt

Each sphere's CLAUDE.md defines context for AI interactions:

```markdown
# Work Sphere

You are assisting with professional projects and work-related thinking.

## Context

This sphere contains work discussions, project planning, and professional development.

## Guidelines

- Keep responses focused and actionable
- Reference past discussions when relevant
- Suggest connections between related projects
```

---

## Implementation Plan

### Phase 1: Basic Sphere Management

- [ ] Create sphere (name, icon, color)
- [ ] Edit sphere metadata
- [ ] Delete sphere
- [ ] List spheres in UI

### Phase 2: Capture Linking

- [ ] Link capture to sphere with context
- [ ] Unlink capture from sphere
- [ ] View captures linked to sphere
- [ ] View spheres a capture belongs to

### Phase 3: JSONL Service

- [ ] Parse sphere.jsonl
- [ ] Append entries
- [ ] Query links/tags/notes
- [ ] Handle file creation/migration

### Phase 4: UI Polish

- [ ] Sphere browser screen
- [ ] Link management UI
- [ ] Tag suggestions
- [ ] Cross-sphere search

---

## Technical Notes

### Service Architecture

```dart
// SphereService - manages sphere CRUD
class SphereService {
  Future<List<Sphere>> listSpheres();
  Future<Sphere> createSphere(String name, {String? icon, String? color});
  Future<void> deleteSphere(String name);
}

// SphereLinkService - manages sphere.jsonl
class SphereLinkService {
  Future<void> linkCapture(String sphereName, String captureId, {String? context});
  Future<void> unlinkCapture(String sphereName, String captureId);
  Future<List<SphereLink>> getLinks(String sphereName);
  Future<List<String>> getSpheresForCapture(String captureId);
}
```

### Migration from Spaces

The codebase currently uses "spaces" in code. Migration:

1. Rename UI labels first (user-facing)
2. Update docs (done)
3. Gradually rename code (providers, services)
4. Keep file paths backward-compatible (`spheres/` folder)

---

## Related Documents

- [ARCHITECTURE.md](../../ARCHITECTURE.md) - sphere.jsonl format specification
- [CLAUDE.md](../../CLAUDE.md) - Sphere System section
- [docs/archive/2025-11/space-sqlite-knowledge-system.md](../archive/2025-11/space-sqlite-knowledge-system.md) - Previous SQLite approach (archived)

---

**Next Steps:** Implement Phase 1 (Basic Sphere Management)
