# Polish Tasks - November 2025

**Status**: 🚧 Active Sprint
**Updated**: November 6, 2025

This document tracks polish and completion tasks for the two current priorities:
1. Recording UI refinements
2. GitHub sync integration completion

---

## Priority 1: Recording UI Polish

### Context Field Integration

**Status**: ✅ Implemented, needs refinement

**What's Done**:
- Context field added to Recording model
- Inline editing in RecordingDetailScreen
- Saves to recording JSON metadata

**Polish Needed**:
- [ ] **UX**: Should context be optional or encouraged?
- [ ] **Placeholder text**: Add helpful hints for what context means
- [ ] **Integration**: How does context relate to space linking?
- [ ] **Display**: Show context prominently in recording list/cards?
- [ ] **Validation**: Character limits, markdown support?

**Questions**:
- Is context meant to be space-specific (different per space) or recording-level?
- Should we auto-populate context when linking to a space?

---

### Inline Editing Experience

**Status**: ✅ Implemented, needs UX review

**What's Done**:
- Title, transcript, and context all editable inline
- Save button persists changes to filesystem
- Controllers maintain state

**Polish Needed**:
- [ ] **Visual feedback**: Clearer "edit mode" vs "view mode" states
- [ ] **Save indicator**: Show when changes are saved successfully
- [ ] **Unsaved changes**: Warn user if navigating away with unsaved edits
- [ ] **Keyboard shortcuts**: Enter to save, Esc to cancel
- [ ] **Error handling**: What if save fails? (disk full, permissions)
- [ ] **Auto-save**: Consider auto-save after X seconds of inactivity?

---

### Transcription Status & Progress

**Status**: ⚠️ Partially implemented

**What's Done**:
- ProcessingStatus enum tracks states
- Periodic refresh updates status
- Shows status in UI

**Polish Needed**:
- [ ] **Progress indicators**: Better visual progress for transcription
- [ ] **Error states**: Clear messaging when transcription fails
- [ ] **Retry logic**: Allow user to retry failed transcription
- [ ] **Status persistence**: Track failed state across app restarts
- [ ] **Loading skeletons**: Show placeholders while loading
- [ ] **Background processing**: Indicate when processing happens in background

---

### Title Generation

**Status**: ✅ Implemented, needs polish

**What's Done**:
- Gemma 2B title generation works
- Can be disabled in settings
- Background processing

**Polish Needed**:
- [ ] **Manual override**: Easy way to regenerate title
- [ ] **Edit before accepting**: Preview generated title before saving
- [ ] **Fallback**: Better default titles when generation disabled/fails
- [ ] **Status indicator**: Show when title is being generated
- [ ] **Model selection**: Allow choosing different models? (future)

---

### Performance & Responsiveness

**Status**: 🆕 Needs investigation

**Polish Needed**:
- [ ] **Large recordings**: Test with 1+ hour recordings
- [ ] **Memory usage**: Profile memory with many recordings
- [ ] **Startup time**: Optimize initial recording list load
- [ ] **Scroll performance**: Ensure smooth scrolling with 100+ recordings
- [ ] **Audio playback**: Test playback of large WAV files

---

### Error Handling

**Status**: ⚠️ Basic implementation

**Polish Needed**:
- [ ] **File system errors**: Handle disk full, permissions issues
- [ ] **Transcription failures**: Clear error messages with retry
- [ ] **Model download failures**: Better recovery from failed downloads
- [ ] **Network errors**: Handle offline gracefully (especially for Gemma)
- [ ] **Corrupt files**: Detect and handle corrupt audio/metadata
- [ ] **Recovery**: Provide clear recovery steps for errors

---

## Priority 2: GitHub Sync Completion

### Core Git Operations (Remote)

**Status**: ⚠️ Local only, needs remote ops

**What's Done**:
- GitService with init, add, commit, status ✅
- git2dart POC validated ✅

**Polish Needed**:
- [ ] **Clone**: Implement `GitService.clone(url, path, token)`
- [ ] **Push**: Implement `GitService.push(repo, token)`
- [ ] **Pull**: Implement `GitService.pull(repo, token)`
- [ ] **Remote setup**: Add remote if initializing locally first
- [ ] **Auth**: PAT authentication for GitHub
- [ ] **Credentials**: Secure credential storage and injection

**Code Location**: `app/lib/core/services/git/git_service.dart`

---

### Settings Screen for GitHub

**Status**: ❌ Not started

**Needed**:
- [ ] **GitHub PAT input**: Text field with password visibility toggle
- [ ] **Token validation**: Test connection to GitHub API
- [ ] **Repository selection**: UI for choosing/creating repo
  - [ ] List user's repos
  - [ ] Create new private repo
  - [ ] Enter custom repo URL
- [ ] **Sync settings**:
  - [ ] Auto-sync on/off toggle
  - [ ] Sync frequency (immediate, hourly, manual)
- [ ] **Status display**: Show last sync time, sync errors
- [ ] **Manual sync button**: Force sync now

**Design Notes**:
- Should be accessible from main Settings screen
- Use flutter_secure_storage for PAT persistence
- Clear instructions for creating GitHub PAT with correct scopes

---

### Auto-Commit on Recording Save

**Status**: ❌ Not started

**Needed**:
- [ ] **Hook into save flow**: After recording saved to disk
- [ ] **Git operations**:
  1. Add new/modified files (markdown + WAV + JSON)
  2. Commit with message: "Add recording: YYYY-MM-DD_HH-MM-SS"
  3. Push to remote (if configured)
- [ ] **Error handling**: Handle git failures gracefully
- [ ] **Offline queue**: Queue commits if offline, sync when online
- [ ] **User control**: Setting to disable auto-commit?

**Code Location**:
- Hook: `app/lib/features/recorder/services/storage_service.dart`
- Git ops: `app/lib/core/services/git/git_service.dart`

---

### Sync Status Indicators

**Status**: ❌ Not started

**Needed**:
- [ ] **Global sync status**: Icon in app bar showing sync state
  - ✅ Synced (green checkmark)
  - 🔄 Syncing (spinning icon)
  - ⚠️ Sync error (warning icon)
  - ☁️ Not configured (cloud icon)
- [ ] **Per-recording status**: Badge showing if recording is synced
- [ ] **Pull to refresh**: Manual refresh gesture to trigger sync
- [ ] **Sync history**: Log of recent sync operations
- [ ] **Conflict indicator**: Show when conflicts need resolution

**Design Reference**: Look at VS Code, Tower, GitHub Desktop for inspiration

---

### Conflict Detection & Resolution

**Status**: ⚠️ Basic strategy defined, not implemented

**Current Strategy** (MVP):
- Detect merge conflicts after pull
- Alert user to conflicts
- "Last write wins" for different files (most recordings are new files)

**Polish Needed**:
- [ ] **Conflict detection**: Use git2dart to detect merge conflicts
- [ ] **User notification**: Clear dialog explaining conflict
- [ ] **Basic resolution**: Implement "keep local" or "keep remote"
- [ ] **Manual resolution**: Link to files for manual editing (future)
- [ ] **Prevention**: Encourage frequent pulls/pushes

**Future Enhancement** (Phase 4):
- LLM-assisted conflict resolution
- Visual diff UI
- Per-file resolution choices

---

### Error Handling & Retry Logic

**Status**: ❌ Not started

**Needed**:
- [ ] **Network errors**: Retry push/pull with exponential backoff
- [ ] **Auth errors**: Clear message, link to settings
- [ ] **Merge errors**: Guide user through resolution
- [ ] **Disk errors**: Handle out of space, permissions
- [ ] **Rate limiting**: Handle GitHub API rate limits
- [ ] **Offline detection**: Don't spam errors when offline
- [ ] **User feedback**: Toast notifications, error dialogs

---

### Testing

**Status**: ⚠️ POC tests only

**Needed**:
- [ ] **Unit tests**: GitService methods (clone, push, pull)
- [ ] **Integration tests**: Full sync flow end-to-end
- [ ] **Mock GitHub**: Test without real GitHub API
- [ ] **Conflict scenarios**: Test merge conflict handling
- [ ] **Network failure**: Test retry logic
- [ ] **Large files**: Test with realistic audio file sizes
- [ ] **Performance**: Benchmark sync with 100+ recordings

---

## Additional Polish Tasks

### Documentation

- [ ] Update ARCHITECTURE.md with Git sync architecture
- [ ] Update user docs with GitHub setup instructions
- [ ] Add troubleshooting guide for common sync issues
- [ ] Document PAT scope requirements

### Security

- [ ] Audit: Never log PAT tokens
- [ ] Ensure flutter_secure_storage used correctly
- [ ] Test: PAT not exposed in error messages
- [ ] Consider: Optional PAT encryption at rest

### Performance

- [ ] Profile: Git operations impact on UI thread
- [ ] Optimize: Large file handling (Git LFS consideration)
- [ ] Background: Run sync operations in isolate if needed

---

## Definition of Done

### Recording UI Polish
- ✅ All inline editing feels smooth and intuitive
- ✅ Error states are clear and actionable
- ✅ Loading states provide good feedback
- ✅ Performance is acceptable with 100+ recordings
- ✅ No data loss scenarios (all saves succeed or error clearly)

### GitHub Sync
- ✅ User can authenticate with GitHub PAT
- ✅ User can select/create repository
- ✅ Recordings auto-commit and push after save
- ✅ App pulls latest changes on startup
- ✅ Sync status always visible and accurate
- ✅ Conflicts detected and user notified
- ✅ Works reliably offline (queues operations)
- ✅ All critical paths have error handling

---

## Known Issues & Decisions Needed

### Questions for User

1. **Context field purpose**: Is this space-specific or recording-level metadata?
2. **Auto-commit timing**: Immediately after save, or batch commits?
3. **Conflict resolution**: How aggressive should "last write wins" be?
4. **Git LFS**: Do we need it for audio files, or is standard Git acceptable?
5. **Branch strategy**: Single `main` branch or per-device branches?

### Technical Decisions

1. **Isolate for Git ops**: Run in background or on main thread?
2. **Sync frequency**: Default to immediate or periodic?
3. **Token refresh**: Handle GitHub PAT expiration?
4. **Multi-repo**: Support multiple Git repos (different vaults)?

---

## Timeline

**Target**: End of Week (Nov 10, 2025)
- [ ] Recording UI polish complete
- [ ] GitHub clone, push, pull implemented
- [ ] Settings screen for GitHub PAT
- [ ] Auto-commit on save working
- [ ] Basic error handling in place

**Stretch Goal** (Nov 13, 2025):
- [ ] Sync status indicators polished
- [ ] Conflict detection working
- [ ] Full test coverage for Git operations

---

**Next Steps**: Prioritize and tackle one section at a time. Update checkboxes as work progresses.
