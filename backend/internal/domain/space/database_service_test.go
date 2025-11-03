package space_test

import (
	"database/sql"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/unforced/parachute-backend/internal/domain/space"
	sqliteStorage "github.com/unforced/parachute-backend/internal/storage/sqlite"
)

// setupTestEnvironment creates a temporary directory structure for testing
func setupTestEnvironment(t *testing.T) (parachuteRoot string, cleanup func()) {
	tmpDir, err := os.MkdirTemp("", "parachute-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}

	// Create captures and spaces directories
	capturesDir := filepath.Join(tmpDir, "captures")
	spacesDir := filepath.Join(tmpDir, "spaces")

	if err := os.MkdirAll(capturesDir, 0755); err != nil {
		t.Fatalf("Failed to create captures dir: %v", err)
	}
	if err := os.MkdirAll(spacesDir, 0755); err != nil {
		t.Fatalf("Failed to create spaces dir: %v", err)
	}

	cleanup = func() {
		os.RemoveAll(tmpDir)
	}

	return tmpDir, cleanup
}

// setupTestSpace creates a test space with space.sqlite initialized
func setupTestSpace(t *testing.T, parachuteRoot string) (spaceID, spacePath string) {
	spaceID = uuid.New().String()
	spacePath = filepath.Join(parachuteRoot, "spaces", "test-space-"+spaceID[:8])

	if err := os.MkdirAll(spacePath, 0755); err != nil {
		t.Fatalf("Failed to create space directory: %v", err)
	}

	// Initialize space.sqlite
	service := space.NewSpaceDatabaseService(parachuteRoot)
	if err := service.InitializeSpaceDatabase(spaceID, spacePath); err != nil {
		t.Fatalf("Failed to initialize space database: %v", err)
	}

	return spaceID, spacePath
}

// createMockCapture creates a mock capture file in captures/
func createMockCapture(t *testing.T, parachuteRoot string, content string) (captureID, notePath string) {
	captureID = uuid.New().String()
	timestamp := time.Now().Format("2006-01-02_15-04-05")
	filename := timestamp + ".md"
	notePath = filepath.Join("captures", filename)
	fullPath := filepath.Join(parachuteRoot, notePath)

	if err := os.WriteFile(fullPath, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create mock capture: %v", err)
	}

	return captureID, notePath
}

func TestInitializeSpaceDatabase(t *testing.T) {
	parachuteRoot, cleanup := setupTestEnvironment(t)
	defer cleanup()

	service := space.NewSpaceDatabaseService(parachuteRoot)
	spaceID := uuid.New().String()
	spacePath := filepath.Join(parachuteRoot, "spaces", "test-init")

	t.Run("CreateNewDatabase", func(t *testing.T) {
		err := service.InitializeSpaceDatabase(spaceID, spacePath)
		if err != nil {
			t.Fatalf("Failed to initialize database: %v", err)
		}

		// Verify database file exists
		dbPath := filepath.Join(spacePath, "space.sqlite")
		if _, err := os.Stat(dbPath); os.IsNotExist(err) {
			t.Error("space.sqlite was not created")
		}

		// Verify schema
		db, err := sql.Open("sqlite", dbPath)
		if err != nil {
			t.Fatalf("Failed to open database: %v", err)
		}
		defer db.Close()

		// Check tables exist
		tables := []string{"space_metadata", "relevant_notes"}
		for _, table := range tables {
			var count int
			err = db.QueryRow("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?", table).Scan(&count)
			if err != nil || count == 0 {
				t.Errorf("Table %s does not exist", table)
			}
		}

		// Verify metadata
		var storedSpaceID string
		err = db.QueryRow("SELECT value FROM space_metadata WHERE key='space_id'").Scan(&storedSpaceID)
		if err != nil {
			t.Errorf("Failed to get space_id from metadata: %v", err)
		}
		if storedSpaceID != spaceID {
			t.Errorf("Expected space_id %s, got %s", spaceID, storedSpaceID)
		}

		// Verify indexes
		indexes := []string{
			"idx_relevant_notes_tags",
			"idx_relevant_notes_last_ref",
			"idx_relevant_notes_linked_at",
		}
		for _, index := range indexes {
			var count int
			err = db.QueryRow("SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name=?", index).Scan(&count)
			if err != nil || count == 0 {
				t.Errorf("Index %s does not exist", index)
			}
		}
	})

	t.Run("ReinitializeExistingDatabase", func(t *testing.T) {
		// Initialize again - should not fail and should preserve existing space_id
		err := service.InitializeSpaceDatabase(spaceID, spacePath)
		if err != nil {
			t.Fatalf("Failed to reinitialize database: %v", err)
		}

		// Verify space_id is preserved
		dbPath := filepath.Join(spacePath, "space.sqlite")
		db, err := sql.Open("sqlite", dbPath)
		if err != nil {
			t.Fatalf("Failed to open database: %v", err)
		}
		defer db.Close()

		var storedSpaceID string
		err = db.QueryRow("SELECT value FROM space_metadata WHERE key='space_id'").Scan(&storedSpaceID)
		if err != nil {
			t.Errorf("Failed to get space_id: %v", err)
		}
		if storedSpaceID != spaceID {
			t.Errorf("space_id was changed on reinitialize: expected %s, got %s", spaceID, storedSpaceID)
		}
	})
}

func TestLinkNote(t *testing.T) {
	parachuteRoot, cleanup := setupTestEnvironment(t)
	defer cleanup()

	service := space.NewSpaceDatabaseService(parachuteRoot)
	spaceID, spacePath := setupTestSpace(t, parachuteRoot)
	captureID, notePath := createMockCapture(t, parachuteRoot, "Test capture content")

	t.Run("LinkNewNote", func(t *testing.T) {
		context := "This is a test note about space exploration"
		tags := []string{"test", "space", "exploration"}

		err := service.LinkNote(spaceID, spacePath, captureID, notePath, context, tags)
		if err != nil {
			t.Fatalf("Failed to link note: %v", err)
		}

		// Verify note was linked
		notes, err := service.GetRelevantNotes(spacePath, space.NoteFilters{})
		if err != nil {
			t.Fatalf("Failed to get notes: %v", err)
		}

		if len(notes) != 1 {
			t.Fatalf("Expected 1 note, got %d", len(notes))
		}

		note := notes[0]
		if note.CaptureID != captureID {
			t.Errorf("Expected capture_id %s, got %s", captureID, note.CaptureID)
		}
		if note.NotePath != notePath {
			t.Errorf("Expected note_path %s, got %s", notePath, note.NotePath)
		}
		if note.Context != context {
			t.Errorf("Expected context %s, got %s", context, note.Context)
		}
		if len(note.Tags) != len(tags) {
			t.Errorf("Expected %d tags, got %d", len(tags), len(note.Tags))
		}
	})

	t.Run("UpdateExistingNote", func(t *testing.T) {
		// Link same capture again with different context and tags
		newContext := "Updated context about something else"
		newTags := []string{"updated", "different"}

		err := service.LinkNote(spaceID, spacePath, captureID, notePath, newContext, newTags)
		if err != nil {
			t.Fatalf("Failed to update note: %v", err)
		}

		// Verify only one note exists (upsert behavior)
		notes, err := service.GetRelevantNotes(spacePath, space.NoteFilters{})
		if err != nil {
			t.Fatalf("Failed to get notes: %v", err)
		}

		if len(notes) != 1 {
			t.Fatalf("Expected 1 note after update, got %d", len(notes))
		}

		// Verify context and tags were updated
		note := notes[0]
		if note.Context != newContext {
			t.Errorf("Expected updated context %s, got %s", newContext, note.Context)
		}
		if len(note.Tags) != len(newTags) {
			t.Errorf("Expected %d tags, got %d", len(newTags), len(note.Tags))
		}
	})

	t.Run("LinkNoteWithEmptyTags", func(t *testing.T) {
		captureID2, notePath2 := createMockCapture(t, parachuteRoot, "Another capture")

		err := service.LinkNote(spaceID, spacePath, captureID2, notePath2, "Context without tags", []string{})
		if err != nil {
			t.Fatalf("Failed to link note with empty tags: %v", err)
		}

		note, err := service.GetNoteByID(spacePath, captureID2)
		if err != nil {
			t.Fatalf("Failed to get note: %v", err)
		}

		if len(note.Tags) != 0 {
			t.Errorf("Expected 0 tags, got %d", len(note.Tags))
		}
	})
}

func TestGetRelevantNotes(t *testing.T) {
	parachuteRoot, cleanup := setupTestEnvironment(t)
	defer cleanup()

	service := space.NewSpaceDatabaseService(parachuteRoot)
	spaceID, spacePath := setupTestSpace(t, parachuteRoot)

	// Create multiple notes with different attributes
	testNotes := []struct {
		captureID string
		notePath  string
		context   string
		tags      []string
		delay     time.Duration
	}{
		{uuid.New().String(), "captures/note1.md", "Context 1", []string{"tag1", "tag2"}, 0},
		{uuid.New().String(), "captures/note2.md", "Context 2", []string{"tag2", "tag3"}, time.Second},
		{uuid.New().String(), "captures/note3.md", "Context 3", []string{"tag3", "tag4"}, 2 * time.Second},
	}

	// Link all test notes
	for _, tn := range testNotes {
		createMockCapture(t, parachuteRoot, "Content for "+tn.notePath)
		time.Sleep(tn.delay) // Ensure different linked_at timestamps
		err := service.LinkNote(spaceID, spacePath, tn.captureID, tn.notePath, tn.context, tn.tags)
		if err != nil {
			t.Fatalf("Failed to link note: %v", err)
		}
	}

	t.Run("GetAllNotes", func(t *testing.T) {
		notes, err := service.GetRelevantNotes(spacePath, space.NoteFilters{})
		if err != nil {
			t.Fatalf("Failed to get notes: %v", err)
		}

		if len(notes) != 3 {
			t.Errorf("Expected 3 notes, got %d", len(notes))
		}

		// Verify ordering (most recent first)
		if notes[0].NotePath != "captures/note3.md" {
			t.Errorf("Expected most recent note first, got %s", notes[0].NotePath)
		}
	})

	t.Run("EmptyDatabase", func(t *testing.T) {
		emptySpaceID, emptySpacePath := setupTestSpace(t, parachuteRoot)
		_ = emptySpaceID // unused

		notes, err := service.GetRelevantNotes(emptySpacePath, space.NoteFilters{})
		if err != nil {
			t.Fatalf("Failed to get notes from empty database: %v", err)
		}

		if len(notes) != 0 {
			t.Errorf("Expected 0 notes from empty database, got %d", len(notes))
		}
	})

	t.Run("NonExistentDatabase", func(t *testing.T) {
		nonExistentPath := filepath.Join(parachuteRoot, "spaces", "non-existent")
		notes, err := service.GetRelevantNotes(nonExistentPath, space.NoteFilters{})
		if err != nil {
			t.Fatalf("Should return empty list for non-existent database, got error: %v", err)
		}

		if len(notes) != 0 {
			t.Errorf("Expected empty list for non-existent database, got %d notes", len(notes))
		}
	})

	t.Run("FilterByTags", func(t *testing.T) {
		// Filter for notes with tag2
		notes, err := service.GetRelevantNotes(spacePath, space.NoteFilters{
			Tags: []string{"tag2"},
		})
		if err != nil {
			t.Fatalf("Failed to filter by tags: %v", err)
		}

		if len(notes) != 2 {
			t.Errorf("Expected 2 notes with tag2, got %d", len(notes))
		}

		// Filter for notes with tag4
		notes, err = service.GetRelevantNotes(spacePath, space.NoteFilters{
			Tags: []string{"tag4"},
		})
		if err != nil {
			t.Fatalf("Failed to filter by tags: %v", err)
		}

		if len(notes) != 1 {
			t.Errorf("Expected 1 note with tag4, got %d", len(notes))
		}
	})

	t.Run("Pagination", func(t *testing.T) {
		// First page
		notes, err := service.GetRelevantNotes(spacePath, space.NoteFilters{
			Limit:  2,
			Offset: 0,
		})
		if err != nil {
			t.Fatalf("Failed to paginate: %v", err)
		}

		if len(notes) != 2 {
			t.Errorf("Expected 2 notes on first page, got %d", len(notes))
		}

		// Second page
		notes, err = service.GetRelevantNotes(spacePath, space.NoteFilters{
			Limit:  2,
			Offset: 2,
		})
		if err != nil {
			t.Fatalf("Failed to paginate: %v", err)
		}

		if len(notes) != 1 {
			t.Errorf("Expected 1 note on second page, got %d", len(notes))
		}
	})

	t.Run("DateRangeFilter", func(t *testing.T) {
		// Filter for recent notes (last 5 seconds)
		fiveSecondsAgo := time.Now().Add(-5 * time.Second)
		notes, err := service.GetRelevantNotes(spacePath, space.NoteFilters{
			StartDate: &fiveSecondsAgo,
		})
		if err != nil {
			t.Fatalf("Failed to filter by date: %v", err)
		}

		if len(notes) != 3 {
			t.Errorf("Expected 3 notes in date range, got %d", len(notes))
		}

		// Filter for very old notes (should be empty)
		veryOld := time.Now().Add(-24 * time.Hour)
		tenHoursAgo := time.Now().Add(-10 * time.Hour)
		notes, err = service.GetRelevantNotes(spacePath, space.NoteFilters{
			StartDate: &veryOld,
			EndDate:   &tenHoursAgo,
		})
		if err != nil {
			t.Fatalf("Failed to filter by date range: %v", err)
		}

		if len(notes) != 0 {
			t.Errorf("Expected 0 notes in old date range, got %d", len(notes))
		}
	})
}

func TestUpdateNoteContext(t *testing.T) {
	parachuteRoot, cleanup := setupTestEnvironment(t)
	defer cleanup()

	service := space.NewSpaceDatabaseService(parachuteRoot)
	spaceID, spacePath := setupTestSpace(t, parachuteRoot)
	captureID, notePath := createMockCapture(t, parachuteRoot, "Test capture")

	// Link initial note
	err := service.LinkNote(spaceID, spacePath, captureID, notePath, "Original context", []string{"original", "tags"})
	if err != nil {
		t.Fatalf("Failed to link note: %v", err)
	}

	t.Run("UpdateContextOnly", func(t *testing.T) {
		newContext := "Updated context only"
		err := service.UpdateNoteContext(spacePath, captureID, &newContext, nil)
		if err != nil {
			t.Fatalf("Failed to update context: %v", err)
		}

		note, err := service.GetNoteByID(spacePath, captureID)
		if err != nil {
			t.Fatalf("Failed to get note: %v", err)
		}

		if note.Context != newContext {
			t.Errorf("Expected context %s, got %s", newContext, note.Context)
		}

		// Tags should remain unchanged
		if len(note.Tags) != 2 {
			t.Errorf("Tags should not change, expected 2, got %d", len(note.Tags))
		}
	})

	t.Run("UpdateTagsOnly", func(t *testing.T) {
		newTags := []string{"new", "tag", "set"}
		err := service.UpdateNoteContext(spacePath, captureID, nil, &newTags)
		if err != nil {
			t.Fatalf("Failed to update tags: %v", err)
		}

		note, err := service.GetNoteByID(spacePath, captureID)
		if err != nil {
			t.Fatalf("Failed to get note: %v", err)
		}

		if len(note.Tags) != 3 {
			t.Errorf("Expected 3 tags, got %d", len(note.Tags))
		}

		// Context should remain from previous update
		if note.Context != "Updated context only" {
			t.Errorf("Context should not change, got %s", note.Context)
		}
	})

	t.Run("UpdateBoth", func(t *testing.T) {
		finalContext := "Final context"
		finalTags := []string{"final"}

		err := service.UpdateNoteContext(spacePath, captureID, &finalContext, &finalTags)
		if err != nil {
			t.Fatalf("Failed to update both: %v", err)
		}

		note, err := service.GetNoteByID(spacePath, captureID)
		if err != nil {
			t.Fatalf("Failed to get note: %v", err)
		}

		if note.Context != finalContext {
			t.Errorf("Expected context %s, got %s", finalContext, note.Context)
		}
		if len(note.Tags) != 1 {
			t.Errorf("Expected 1 tag, got %d", len(note.Tags))
		}
	})

	t.Run("UpdateNonExistentNote", func(t *testing.T) {
		nonExistentID := uuid.New().String()
		newContext := "This should fail"

		err := service.UpdateNoteContext(spacePath, nonExistentID, &newContext, nil)
		if err == nil {
			t.Error("Expected error when updating non-existent note")
		}
		if err != nil && err.Error() != "note not found in space" {
			t.Errorf("Expected 'note not found in space' error, got: %v", err)
		}
	})

	t.Run("UpdateWithNilValues", func(t *testing.T) {
		// This should be a no-op
		err := service.UpdateNoteContext(spacePath, captureID, nil, nil)
		if err != nil {
			t.Errorf("Update with nil values should not error, got: %v", err)
		}
	})
}

func TestUnlinkNote(t *testing.T) {
	parachuteRoot, cleanup := setupTestEnvironment(t)
	defer cleanup()

	service := space.NewSpaceDatabaseService(parachuteRoot)
	spaceID, spacePath := setupTestSpace(t, parachuteRoot)
	captureID, notePath := createMockCapture(t, parachuteRoot, "Test capture")

	// Link note
	err := service.LinkNote(spaceID, spacePath, captureID, notePath, "Context", []string{"tag"})
	if err != nil {
		t.Fatalf("Failed to link note: %v", err)
	}

	t.Run("UnlinkExistingNote", func(t *testing.T) {
		err := service.UnlinkNote(spacePath, captureID)
		if err != nil {
			t.Fatalf("Failed to unlink note: %v", err)
		}

		// Verify note is gone
		notes, err := service.GetRelevantNotes(spacePath, space.NoteFilters{})
		if err != nil {
			t.Fatalf("Failed to get notes: %v", err)
		}

		if len(notes) != 0 {
			t.Errorf("Expected 0 notes after unlink, got %d", len(notes))
		}
	})

	t.Run("UnlinkNonExistentNote", func(t *testing.T) {
		nonExistentID := uuid.New().String()
		err := service.UnlinkNote(spacePath, nonExistentID)
		if err == nil {
			t.Error("Expected error when unlinking non-existent note")
		}
		if err != nil && err.Error() != "note not found in space" {
			t.Errorf("Expected 'note not found in space' error, got: %v", err)
		}
	})
}

func TestTrackNoteReference(t *testing.T) {
	parachuteRoot, cleanup := setupTestEnvironment(t)
	defer cleanup()

	service := space.NewSpaceDatabaseService(parachuteRoot)
	spaceID, spacePath := setupTestSpace(t, parachuteRoot)
	captureID, notePath := createMockCapture(t, parachuteRoot, "Test capture")

	// Link note
	err := service.LinkNote(spaceID, spacePath, captureID, notePath, "Context", []string{"tag"})
	if err != nil {
		t.Fatalf("Failed to link note: %v", err)
	}

	// Get initial note (last_referenced should be nil)
	note, err := service.GetNoteByID(spacePath, captureID)
	if err != nil {
		t.Fatalf("Failed to get note: %v", err)
	}
	if note.LastReferenced != nil {
		t.Error("Expected last_referenced to be nil initially")
	}

	t.Run("TrackReference", func(t *testing.T) {
		err := service.TrackNoteReference(spacePath, captureID)
		if err != nil {
			t.Fatalf("Failed to track reference: %v", err)
		}

		// Get note again
		note, err := service.GetNoteByID(spacePath, captureID)
		if err != nil {
			t.Fatalf("Failed to get note: %v", err)
		}

		if note.LastReferenced == nil {
			t.Error("Expected last_referenced to be set")
		}
		// Just verify it's set - don't compare exact timestamps due to precision issues
	})

	t.Run("TrackMultipleTimes", func(t *testing.T) {
		// Track once
		err := service.TrackNoteReference(spacePath, captureID)
		if err != nil {
			t.Fatalf("Failed to track reference: %v", err)
		}

		note1, err := service.GetNoteByID(spacePath, captureID)
		if err != nil {
			t.Fatalf("Failed to get note: %v", err)
		}
		if note1.LastReferenced == nil {
			t.Fatal("Expected last_referenced to be set after first track")
		}
		firstTime := note1.LastReferenced.Unix()

		// Wait and track again
		time.Sleep(2 * time.Second)
		err = service.TrackNoteReference(spacePath, captureID)
		if err != nil {
			t.Fatalf("Failed to track reference again: %v", err)
		}

		note2, err := service.GetNoteByID(spacePath, captureID)
		if err != nil {
			t.Fatalf("Failed to get note: %v", err)
		}

		// Should have been updated to a later time (check unix timestamps)
		if note2.LastReferenced.Unix() <= firstTime {
			t.Errorf("last_referenced should be updated: first=%d, second=%d",
				firstTime, note2.LastReferenced.Unix())
		}
	})
}

func TestGetNoteByID(t *testing.T) {
	parachuteRoot, cleanup := setupTestEnvironment(t)
	defer cleanup()

	service := space.NewSpaceDatabaseService(parachuteRoot)
	spaceID, spacePath := setupTestSpace(t, parachuteRoot)
	captureID, notePath := createMockCapture(t, parachuteRoot, "Test capture content")

	context := "Test context"
	tags := []string{"tag1", "tag2"}
	err := service.LinkNote(spaceID, spacePath, captureID, notePath, context, tags)
	if err != nil {
		t.Fatalf("Failed to link note: %v", err)
	}

	t.Run("GetExistingNote", func(t *testing.T) {
		note, err := service.GetNoteByID(spacePath, captureID)
		if err != nil {
			t.Fatalf("Failed to get note by ID: %v", err)
		}

		if note.CaptureID != captureID {
			t.Errorf("Expected capture_id %s, got %s", captureID, note.CaptureID)
		}
		if note.Context != context {
			t.Errorf("Expected context %s, got %s", context, note.Context)
		}
		if len(note.Tags) != 2 {
			t.Errorf("Expected 2 tags, got %d", len(note.Tags))
		}
	})

	t.Run("GetNonExistentNote", func(t *testing.T) {
		nonExistentID := uuid.New().String()
		_, err := service.GetNoteByID(spacePath, nonExistentID)
		if err == nil {
			t.Error("Expected error when getting non-existent note")
		}
	})

	t.Run("GetFromNonExistentDatabase", func(t *testing.T) {
		nonExistentPath := filepath.Join(parachuteRoot, "spaces", "non-existent")
		_, err := service.GetNoteByID(nonExistentPath, captureID)
		if err == nil {
			t.Error("Expected error when database doesn't exist")
		}
	})
}

func TestGetDatabaseStats(t *testing.T) {
	parachuteRoot, cleanup := setupTestEnvironment(t)
	defer cleanup()

	service := space.NewSpaceDatabaseService(parachuteRoot)
	spaceID, spacePath := setupTestSpace(t, parachuteRoot)

	// Link a few notes with various tags
	for i := 0; i < 5; i++ {
		captureID, notePath := createMockCapture(t, parachuteRoot, "Capture "+string(rune(i)))
		tags := []string{"common", "tag" + string(rune('A'+i))}
		err := service.LinkNote(spaceID, spacePath, captureID, notePath, "Context "+string(rune(i)), tags)
		if err != nil {
			t.Fatalf("Failed to link note: %v", err)
		}
	}

	t.Run("GetStats", func(t *testing.T) {
		stats, err := service.GetDatabaseStats(spacePath)
		if err != nil {
			t.Fatalf("Failed to get stats: %v", err)
		}

		if stats.TotalNotes != 5 {
			t.Errorf("Expected 5 total notes, got %d", stats.TotalNotes)
		}

		if stats.SpaceID != spaceID {
			t.Errorf("Expected space_id %s, got %s", spaceID, stats.SpaceID)
		}

		if stats.SchemaVersion != "1" {
			t.Errorf("Expected schema_version 1, got %s", stats.SchemaVersion)
		}

		// Should have at least "common" tag
		if len(stats.AllTags) < 1 {
			t.Error("Expected at least 1 tag in stats")
		}

		// Should have table names
		expectedTables := []string{"space_metadata", "relevant_notes"}
		for _, table := range expectedTables {
			found := false
			for _, t := range stats.Tables {
				if t == table {
					found = true
					break
				}
			}
			if !found {
				t.Errorf("Expected table %s in stats.Tables", table)
			}
		}

		// Recent notes should be populated (up to 10)
		if len(stats.RecentNotes) != 5 {
			t.Errorf("Expected 5 recent notes, got %d", len(stats.RecentNotes))
		}
	})

	t.Run("GetStatsFromNonExistentDatabase", func(t *testing.T) {
		nonExistentPath := filepath.Join(parachuteRoot, "spaces", "non-existent")
		_, err := service.GetDatabaseStats(nonExistentPath)
		if err == nil {
			t.Error("Expected error when database doesn't exist")
		}
	})
}

func TestQueryTable(t *testing.T) {
	parachuteRoot, cleanup := setupTestEnvironment(t)
	defer cleanup()

	service := space.NewSpaceDatabaseService(parachuteRoot)
	spaceID, spacePath := setupTestSpace(t, parachuteRoot)

	// Link a note to populate relevant_notes table
	captureID, notePath := createMockCapture(t, parachuteRoot, "Test capture")
	err := service.LinkNote(spaceID, spacePath, captureID, notePath, "Context", []string{"tag1", "tag2"})
	if err != nil {
		t.Fatalf("Failed to link note: %v", err)
	}

	t.Run("QueryRelevantNotesTable", func(t *testing.T) {
		result, err := service.QueryTable(spacePath, "relevant_notes")
		if err != nil {
			t.Fatalf("Failed to query table: %v", err)
		}

		if result.TableName != "relevant_notes" {
			t.Errorf("Expected table_name 'relevant_notes', got %s", result.TableName)
		}

		if result.RowCount != 1 {
			t.Errorf("Expected 1 row, got %d", result.RowCount)
		}

		// Check columns
		expectedColumns := []string{"id", "capture_id", "note_path", "linked_at", "context", "tags", "last_referenced", "metadata"}
		if len(result.Columns) != len(expectedColumns) {
			t.Errorf("Expected %d columns, got %d", len(expectedColumns), len(result.Columns))
		}

		// Verify row data
		if len(result.Rows) != 1 {
			t.Fatalf("Expected 1 row in result, got %d", len(result.Rows))
		}

		row := result.Rows[0]
		if row["capture_id"] != captureID {
			t.Errorf("Expected capture_id %s in row, got %v", captureID, row["capture_id"])
		}

		// Tags should be parsed as JSON array
		if tags, ok := row["tags"].([]interface{}); ok {
			if len(tags) != 2 {
				t.Errorf("Expected 2 tags in parsed JSON, got %d", len(tags))
			}
		} else {
			t.Error("Expected tags to be parsed as JSON array")
		}
	})

	t.Run("QueryMetadataTable", func(t *testing.T) {
		result, err := service.QueryTable(spacePath, "space_metadata")
		if err != nil {
			t.Fatalf("Failed to query metadata table: %v", err)
		}

		if result.RowCount < 1 {
			t.Error("Expected at least 1 metadata row")
		}
	})

	t.Run("QueryInvalidTableName", func(t *testing.T) {
		_, err := service.QueryTable(spacePath, "'; DROP TABLE relevant_notes; --")
		if err == nil {
			t.Error("Expected error for SQL injection attempt")
		}
	})

	t.Run("QueryNonExistentTable", func(t *testing.T) {
		_, err := service.QueryTable(spacePath, "non_existent_table")
		if err == nil {
			t.Error("Expected error for non-existent table")
		}
	})
}

func TestMigrateAllSpaces(t *testing.T) {
	parachuteRoot, cleanup := setupTestEnvironment(t)
	defer cleanup()

	service := space.NewSpaceDatabaseService(parachuteRoot)

	// Create database and repository for space management
	dbPath := filepath.Join(parachuteRoot, "parachute.db")
	db, err := sqliteStorage.NewDatabase(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}
	defer db.Close()

	spaceRepo := sqliteStorage.NewSpaceRepository(db.DB)

	// Create a couple of spaces without space.sqlite
	spacesDir := filepath.Join(parachuteRoot, "spaces")
	space1Path := filepath.Join(spacesDir, "space1")
	space2Path := filepath.Join(spacesDir, "space2")

	for _, path := range []string{space1Path, space2Path} {
		if err := os.MkdirAll(path, 0755); err != nil {
			t.Fatalf("Failed to create space directory: %v", err)
		}
	}

	t.Run("MigrateExistingSpaces", func(t *testing.T) {
		err := service.MigrateAllSpaces(spaceRepo)
		if err != nil {
			t.Fatalf("Failed to migrate spaces: %v", err)
		}

		// Verify space.sqlite was created in both spaces
		for _, path := range []string{space1Path, space2Path} {
			dbPath := filepath.Join(path, "space.sqlite")
			if _, err := os.Stat(dbPath); os.IsNotExist(err) {
				t.Errorf("space.sqlite was not created in %s", path)
			}
		}
	})

	t.Run("MigrateAlreadyMigratedSpaces", func(t *testing.T) {
		// Run migration again - should be idempotent
		err := service.MigrateAllSpaces(spaceRepo)
		if err != nil {
			t.Fatalf("Failed to re-migrate spaces: %v", err)
		}

		// Verify databases still exist and are intact
		for _, path := range []string{space1Path, space2Path} {
			dbPath := filepath.Join(path, "space.sqlite")
			db, err := sql.Open("sqlite", dbPath)
			if err != nil {
				t.Errorf("Failed to open migrated database: %v", err)
				continue
			}
			defer db.Close()

			var count int
			err = db.QueryRow("SELECT COUNT(*) FROM space_metadata").Scan(&count)
			if err != nil {
				t.Errorf("Migrated database is corrupted: %v", err)
			}
		}
	})

	t.Run("MigrateWithNoSpacesDirectory", func(t *testing.T) {
		emptyRoot, cleanup := setupTestEnvironment(t)
		defer cleanup()

		// Remove spaces directory
		os.RemoveAll(filepath.Join(emptyRoot, "spaces"))

		emptyService := space.NewSpaceDatabaseService(emptyRoot)
		err := emptyService.MigrateAllSpaces(spaceRepo)
		if err != nil {
			t.Error("Migration should handle missing spaces directory gracefully")
		}
	})
}

func TestUnicodeAndSpecialCharacters(t *testing.T) {
	parachuteRoot, cleanup := setupTestEnvironment(t)
	defer cleanup()

	service := space.NewSpaceDatabaseService(parachuteRoot)
	spaceID, spacePath := setupTestSpace(t, parachuteRoot)
	captureID, notePath := createMockCapture(t, parachuteRoot, "Unicode test 你好 мир")

	t.Run("UnicodeInContextAndTags", func(t *testing.T) {
		context := "Context with emoji 🚀 and Chinese 你好 and Cyrillic мир"
		tags := []string{"emoji-🎉", "中文", "русский"}

		err := service.LinkNote(spaceID, spacePath, captureID, notePath, context, tags)
		if err != nil {
			t.Fatalf("Failed to link note with unicode: %v", err)
		}

		note, err := service.GetNoteByID(spacePath, captureID)
		if err != nil {
			t.Fatalf("Failed to get note: %v", err)
		}

		if note.Context != context {
			t.Errorf("Unicode context not preserved: expected %s, got %s", context, note.Context)
		}

		if len(note.Tags) != 3 {
			t.Errorf("Expected 3 unicode tags, got %d", len(note.Tags))
		}
	})
}

func TestLargeData(t *testing.T) {
	parachuteRoot, cleanup := setupTestEnvironment(t)
	defer cleanup()

	service := space.NewSpaceDatabaseService(parachuteRoot)
	spaceID, spacePath := setupTestSpace(t, parachuteRoot)
	captureID, notePath := createMockCapture(t, parachuteRoot, "Large data test")

	t.Run("LargeContext", func(t *testing.T) {
		// Create a 10KB context string
		largeContext := ""
		for i := 0; i < 10*1024; i++ {
			largeContext += "a"
		}

		err := service.LinkNote(spaceID, spacePath, captureID, notePath, largeContext, []string{"large"})
		if err != nil {
			t.Fatalf("Failed to link note with large context: %v", err)
		}

		note, err := service.GetNoteByID(spacePath, captureID)
		if err != nil {
			t.Fatalf("Failed to get note: %v", err)
		}

		if len(note.Context) != len(largeContext) {
			t.Errorf("Large context not preserved: expected length %d, got %d", len(largeContext), len(note.Context))
		}
	})

	t.Run("ManyTags", func(t *testing.T) {
		// Create 50 tags
		manyTags := make([]string, 50)
		for i := 0; i < 50; i++ {
			manyTags[i] = "tag" + string(rune('0'+i%10))
		}

		err := service.LinkNote(spaceID, spacePath, captureID, notePath, "Context", manyTags)
		if err != nil {
			t.Fatalf("Failed to link note with many tags: %v", err)
		}

		note, err := service.GetNoteByID(spacePath, captureID)
		if err != nil {
			t.Fatalf("Failed to get note: %v", err)
		}

		if len(note.Tags) != 50 {
			t.Errorf("Expected 50 tags, got %d", len(note.Tags))
		}
	})
}

func TestMetadataField(t *testing.T) {
	parachuteRoot, cleanup := setupTestEnvironment(t)
	defer cleanup()

	service := space.NewSpaceDatabaseService(parachuteRoot)
	spaceID, spacePath := setupTestSpace(t, parachuteRoot)
	captureID, notePath := createMockCapture(t, parachuteRoot, "Metadata test")

	// Link note
	err := service.LinkNote(spaceID, spacePath, captureID, notePath, "Context", []string{"tag"})
	if err != nil {
		t.Fatalf("Failed to link note: %v", err)
	}

	t.Run("CustomMetadata", func(t *testing.T) {
		// Manually add custom metadata to test extensibility
		dbPath := filepath.Join(spacePath, "space.sqlite")
		db, err := sql.Open("sqlite", dbPath)
		if err != nil {
			t.Fatalf("Failed to open database: %v", err)
		}
		defer db.Close()

		customMetadata := map[string]interface{}{
			"custom_field": "custom_value",
			"rating":       5,
			"is_important": true,
		}

		metadataJSON, _ := json.Marshal(customMetadata)
		_, err = db.Exec("UPDATE relevant_notes SET metadata = ? WHERE capture_id = ?", string(metadataJSON), captureID)
		if err != nil {
			t.Fatalf("Failed to update metadata: %v", err)
		}

		// Retrieve and verify
		note, err := service.GetNoteByID(spacePath, captureID)
		if err != nil {
			t.Fatalf("Failed to get note: %v", err)
		}

		if note.Metadata == nil {
			t.Fatal("Expected metadata to be populated")
		}

		if customField, ok := note.Metadata["custom_field"].(string); !ok || customField != "custom_value" {
			t.Error("Custom metadata not preserved correctly")
		}
	})
}
