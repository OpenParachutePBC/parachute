# CLAUDE.md → SPACE.md Migration Plan

**Date**: November 3, 2025  
**Reason**: Better compatibility with non-Claude AI agents, clearer naming

---

## What's Changing

### File Naming
- **Old**: `~/Parachute/spaces/{space-name}/CLAUDE.md`
- **New**: `~/Parachute/spaces/{space-name}/SPACE.md`

### Code References
- **Function names**: `ReadClaudeMD()` → `ReadSpaceMD()`
- **Variables**: `claudeMD` → `spaceMD`
- **Comments**: Update all references

### What's NOT Changing
- **Developer docs**: Keep `CLAUDE.md` for project documentation (root, backend/, app/, etc.)
- **PARACHUTE.md**: New global system prompt file at vault root
- **Functionality**: All features stay the same, just renaming

---

## Files to Update

### Backend Code (9 files)

1. **`backend/internal/domain/space/service.go`**
   - `ReadClaudeMD()` → `ReadSpaceMD()`
   - Update function comments

2. **`backend/internal/domain/space/context_service.go`**
   - Update any CLAUDE.md references in variable resolution
   - Comment updates

3. **`backend/internal/api/handlers/message_handler.go`**
   - `claudeMD` variables → `spaceMD`
   - `ReadClaudeMD()` calls → `ReadSpaceMD()`
   - Update comments: "CLAUDE.md" → "SPACE.md"

4. **`backend/internal/domain/space/space.go`**
   - Any struct field comments

5. **`backend/internal/domain/registry/service.go`**
   - Template creation logic if it exists

6. **`backend/cmd/server/main.go`**
   - Any initialization comments

7. **`backend/README.md`**
   - Documentation references

### Frontend Code

8. **Flutter app** (need to search):
   - Any CLAUDE.md references in space creation/editing
   - UI text that mentions "CLAUDE.md"

### Test Files

9. **All test files**:
   - Update test fixtures
   - Update test comments and expectations

---

## Migration Strategy

### Phase 1: Code Changes (Backward Compatible)

**Goal**: Support both CLAUDE.md and SPACE.md temporarily

```go
// ReadSpaceMD tries SPACE.md first, falls back to CLAUDE.md for backward compat
func (s *Service) ReadSpaceMD(space *Space) (string, error) {
    // Try new name first
    spaceMDPath := filepath.Join(space.Path, "SPACE.md")
    if content, err := os.ReadFile(spaceMDPath); err == nil {
        return string(content), nil
    }
    
    // Fall back to old name for backward compatibility
    claudeMDPath := filepath.Join(space.Path, "CLAUDE.md")
    if content, err := os.ReadFile(claudeMDPath); err == nil {
        return string(content), nil
    }
    
    return "", fmt.Errorf("no SPACE.md or CLAUDE.md found")
}
```

### Phase 2: Migration Utility (Optional)

**Auto-migrate existing spaces**:

```go
// MigrateClaudeMDToSpaceMD renames CLAUDE.md → SPACE.md in all spaces
func MigrateClaudeMDToSpaceMD(vaultRoot string) error {
    spacesDir := filepath.Join(vaultRoot, "spaces")
    entries, err := os.ReadDir(spacesDir)
    if err != nil {
        return err
    }
    
    for _, entry := range entries {
        if !entry.IsDir() {
            continue
        }
        
        oldPath := filepath.Join(spacesDir, entry.Name(), "CLAUDE.md")
        newPath := filepath.Join(spacesDir, entry.Name(), "SPACE.md")
        
        // Skip if already migrated
        if _, err := os.Stat(newPath); err == nil {
            continue
        }
        
        // Rename if old file exists
        if _, err := os.Stat(oldPath); err == nil {
            if err := os.Rename(oldPath, newPath); err != nil {
                log.Printf("Failed to migrate %s: %v", oldPath, err)
            } else {
                log.Printf("Migrated: %s → %s", oldPath, newPath)
            }
        }
    }
    
    return nil
}
```

**When to run**:
- Backend startup (check version, run once)
- Settings UI: "Migrate to SPACE.md" button
- Automatic on first app launch after update

### Phase 3: Documentation Updates

- Update all user-facing docs
- Update ARCHITECTURE.md
- Update feature docs
- Update onboarding flow
- Add migration note to CHANGELOG.md

### Phase 4: Remove Backward Compatibility (Future)

**After ~6 months**:
- Remove CLAUDE.md fallback
- Only read SPACE.md
- Clean up migration code

---

## Implementation Order

### Step 1: Backend Core (Now)
- [ ] Rename `ReadClaudeMD()` → `ReadSpaceMD()` with fallback
- [ ] Update all backend code to use new function
- [ ] Update variable names: `claudeMD` → `spaceMD`
- [ ] Add migration utility

### Step 2: Frontend (Now)
- [ ] Search for CLAUDE.md references in Flutter
- [ ] Update UI text
- [ ] Update space creation templates

### Step 3: Documentation (Now)
- [ ] Update ARCHITECTURE.md
- [ ] Update ROADMAP.md
- [ ] Update feature docs
- [ ] Update this file's status

### Step 4: Migration (First Run)
- [ ] Run migration utility on app startup (once)
- [ ] Log migration results
- [ ] Handle errors gracefully

### Step 5: New Spaces (Going Forward)
- [ ] Create new spaces with SPACE.md
- [ ] Update default templates
- [ ] Update onboarding

---

## Testing Plan

### Unit Tests
- [ ] Test `ReadSpaceMD()` with SPACE.md
- [ ] Test `ReadSpaceMD()` with CLAUDE.md (fallback)
- [ ] Test with both files present (SPACE.md wins)
- [ ] Test with neither file (error)

### Integration Tests
- [ ] Create new space → has SPACE.md
- [ ] Old space with CLAUDE.md → still works
- [ ] Migration utility → renames correctly
- [ ] Variable resolution in SPACE.md → works

### Manual Tests
- [ ] Existing space loads correctly
- [ ] New space creates SPACE.md
- [ ] Edit SPACE.md → changes apply
- [ ] Check file browser shows SPACE.md

---

## User Communication

### Changelog Entry
```markdown
### Changed
- **BREAKING**: Space context files renamed from `CLAUDE.md` to `SPACE.md`
  - Better compatibility with non-Claude AI agents
  - Clearer, more descriptive naming
  - Automatic migration on first launch
  - Old CLAUDE.md files will continue to work temporarily

### Added
- New global customization file: `PARACHUTE.md` at vault root
  - Define your personal AI assistant preferences
  - Applies across all spaces
  - See documentation for examples
```

### In-App Notice (First Launch)
```
🎯 Space Context Files Updated

We've renamed CLAUDE.md → SPACE.md in all your spaces for better 
compatibility with different AI assistants.

Your existing spaces have been automatically migrated.

New feature: Create PARACHUTE.md at ~/Parachute/ to customize 
how Parachute behaves globally!

[Learn More] [Got it]
```

---

## Risks & Mitigation

### Risk 1: Breaking Existing Workflows
**Mitigation**: 
- Keep fallback to CLAUDE.md for 6+ months
- Clear communication in changelog
- Automatic migration

### Risk 2: User-Created Integrations
**Impact**: External tools that look for CLAUDE.md might break
**Mitigation**:
- Document the change clearly
- Keep fallback support
- Most users aren't using external integrations yet (early stage)

### Risk 3: Migration Failures
**Mitigation**:
- Dry-run mode in migration utility
- Detailed logging
- Don't delete old files, just rename
- User can manually rename if needed

---

## Status Tracking

- [ ] Design complete
- [ ] Backend changes
- [ ] Frontend changes  
- [ ] Tests updated
- [ ] Documentation updated
- [ ] Migration utility implemented
- [ ] Tested with real data
- [ ] Ready for release

---

**Next Action**: Start with backend core changes (Step 1)
