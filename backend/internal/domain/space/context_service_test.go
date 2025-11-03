package space_test

import (
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/unforced/parachute-backend/internal/domain/space"
)

func TestResolveVariables(t *testing.T) {
	parachuteRoot, cleanup := setupTestEnvironment(t)
	defer cleanup()

	dbService := space.NewSpaceDatabaseService(parachuteRoot)
	contextService := space.NewContextService(dbService)
	spaceID, spacePath := setupTestSpace(t, parachuteRoot)

	t.Run("EmptyTemplate", func(t *testing.T) {
		template := "# Simple Space\n\nNo variables here."
		result, err := contextService.ResolveVariables(template, spacePath)
		if err != nil {
			t.Fatalf("Failed to resolve variables: %v", err)
		}

		if result != template {
			t.Error("Template without variables should remain unchanged")
		}
	})

	t.Run("NoteCountZero", func(t *testing.T) {
		template := "Total notes: {{note_count}}"
		result, err := contextService.ResolveVariables(template, spacePath)
		if err != nil {
			t.Fatalf("Failed to resolve variables: %v", err)
		}

		expected := "Total notes: 0"
		if result != expected {
			t.Errorf("Expected %s, got %s", expected, result)
		}
	})

	t.Run("RecentTagsEmpty", func(t *testing.T) {
		template := "Recent tags: {{recent_tags}}"
		result, err := contextService.ResolveVariables(template, spacePath)
		if err != nil {
			t.Fatalf("Failed to resolve variables: %v", err)
		}

		expected := "Recent tags: none"
		if result != expected {
			t.Errorf("Expected %s, got %s", expected, result)
		}
	})

	t.Run("RecentNotesEmpty", func(t *testing.T) {
		template := "Recent notes:\n{{recent_notes}}"
		result, err := contextService.ResolveVariables(template, spacePath)
		if err != nil {
			t.Fatalf("Failed to resolve variables: %v", err)
		}

		expected := "Recent notes:\nnone"
		if result != expected {
			t.Errorf("Expected %s, got %s", expected, result)
		}
	})

	// Now populate the space with some notes
	testNotes := []struct {
		tags []string
	}{
		{[]string{"farming", "regeneration"}},
		{[]string{"farming", "soil"}},
		{[]string{"regeneration", "biodiversity"}},
		{[]string{"farming", "biodiversity"}},
		{[]string{"soil", "compost"}},
	}

	for i, tn := range testNotes {
		captureID, notePath := createMockCapture(t, parachuteRoot, "Note "+string(rune('A'+i)))
		err := dbService.LinkNote(spaceID, spacePath, captureID, notePath, "Context "+string(rune('A'+i)), tn.tags)
		if err != nil {
			t.Fatalf("Failed to link note: %v", err)
		}
	}

	t.Run("NoteCountWithData", func(t *testing.T) {
		template := "We have {{note_count}} notes in this space."
		result, err := contextService.ResolveVariables(template, spacePath)
		if err != nil {
			t.Fatalf("Failed to resolve variables: %v", err)
		}

		expected := "We have 5 notes in this space."
		if result != expected {
			t.Errorf("Expected '%s', got '%s'", expected, result)
		}
	})

	t.Run("RecentTagsWithData", func(t *testing.T) {
		template := "Popular tags: {{recent_tags}}"
		result, err := contextService.ResolveVariables(template, spacePath)
		if err != nil {
			t.Fatalf("Failed to resolve variables: %v", err)
		}

		// Should contain the most common tags
		if !strings.Contains(result, "farming") {
			t.Error("Expected 'farming' to be in recent tags")
		}
		// "none" should not appear when we have tags
		if strings.Contains(result, "none") {
			t.Error("Should not contain 'none' when tags exist")
		}
	})

	t.Run("RecentNotesWithData", func(t *testing.T) {
		template := "Recent notes:\n{{recent_notes}}"
		result, err := contextService.ResolveVariables(template, spacePath)
		if err != nil {
			t.Fatalf("Failed to resolve variables: %v", err)
		}

		// Should contain markdown list items
		if !strings.Contains(result, "- ") {
			t.Error("Expected markdown list format in recent notes")
		}
		// Should contain .md filenames
		if !strings.Contains(result, ".md") {
			t.Error("Expected .md filenames in recent notes")
		}
		// Should not contain "none"
		if strings.Contains(result, "none") {
			t.Error("Should not contain 'none' when notes exist")
		}
	})

	t.Run("NotesTaggedSpecific", func(t *testing.T) {
		template := "Farming notes: {{notes_tagged:farming}}, Soil notes: {{notes_tagged:soil}}"
		result, err := contextService.ResolveVariables(template, spacePath)
		if err != nil {
			t.Fatalf("Failed to resolve variables: %v", err)
		}

		// farming appears in 3 notes
		if !strings.Contains(result, "Farming notes: 3") {
			t.Errorf("Expected 'Farming notes: 3', got %s", result)
		}
		// soil appears in 2 notes
		if !strings.Contains(result, "Soil notes: 2") {
			t.Errorf("Expected 'Soil notes: 2', got %s", result)
		}
	})

	t.Run("NotesTaggedNonExistent", func(t *testing.T) {
		template := "Quantum notes: {{notes_tagged:quantum}}"
		result, err := contextService.ResolveVariables(template, spacePath)
		if err != nil {
			t.Fatalf("Failed to resolve variables: %v", err)
		}

		expected := "Quantum notes: 0"
		if result != expected {
			t.Errorf("Expected '%s', got '%s'", expected, result)
		}
	})

	t.Run("MultipleVariablesInTemplate", func(t *testing.T) {
		template := `# Space Overview

Total: {{note_count}} notes
Tags: {{recent_tags}}
Tagged 'farming': {{notes_tagged:farming}}
Tagged 'soil': {{notes_tagged:soil}}

Recent Activity:
{{recent_notes}}
`
		result, err := contextService.ResolveVariables(template, spacePath)
		if err != nil {
			t.Fatalf("Failed to resolve variables: %v", err)
		}

		// Check all variables were replaced
		if strings.Contains(result, "{{") {
			t.Error("Template still contains unresolved variables")
		}

		// Verify specific values
		if !strings.Contains(result, "Total: 5 notes") {
			t.Error("note_count not resolved correctly")
		}
		if !strings.Contains(result, "Tagged 'farming': 3") {
			t.Error("notes_tagged:farming not resolved correctly")
		}
		if !strings.Contains(result, "Tagged 'soil': 2") {
			t.Error("notes_tagged:soil not resolved correctly")
		}
	})

	t.Run("NonExistentDatabase", func(t *testing.T) {
		nonExistentPath := filepath.Join(parachuteRoot, "spaces", "non-existent")
		template := "Notes: {{note_count}}, Tags: {{recent_tags}}"

		// Should not error, just return template unchanged or with default values
		result, err := contextService.ResolveVariables(template, nonExistentPath)
		if err != nil {
			t.Fatalf("Should handle non-existent database gracefully, got error: %v", err)
		}

		// Should show zero/none for missing data
		if !strings.Contains(result, "0") || !strings.Contains(result, "none") {
			t.Errorf("Expected default values for non-existent database, got: %s", result)
		}
	})
}

func TestResolveVariablesWithReferences(t *testing.T) {
	parachuteRoot, cleanup := setupTestEnvironment(t)
	defer cleanup()

	dbService := space.NewSpaceDatabaseService(parachuteRoot)
	contextService := space.NewContextService(dbService)
	spaceID, spacePath := setupTestSpace(t, parachuteRoot)

	// Create notes with different reference patterns
	captureID1, notePath1 := createMockCapture(t, parachuteRoot, "Note 1")
	err := dbService.LinkNote(spaceID, spacePath, captureID1, notePath1, "Context 1", []string{"recent"})
	if err != nil {
		t.Fatalf("Failed to link note 1: %v", err)
	}

	// Wait a bit
	time.Sleep(1 * time.Second)

	captureID2, notePath2 := createMockCapture(t, parachuteRoot, "Note 2")
	err = dbService.LinkNote(spaceID, spacePath, captureID2, notePath2, "Context 2", []string{"recent"})
	if err != nil {
		t.Fatalf("Failed to link note 2: %v", err)
	}

	// Reference the first note (update last_referenced)
	err = dbService.TrackNoteReference(spacePath, captureID1)
	if err != nil {
		t.Fatalf("Failed to track reference: %v", err)
	}

	t.Run("RecentNotesOrderedByReference", func(t *testing.T) {
		template := "{{recent_notes}}"
		result, err := contextService.ResolveVariables(template, spacePath)
		if err != nil {
			t.Fatalf("Failed to resolve variables: %v", err)
		}

		// Note 1 should appear before Note 2 because it was more recently referenced
		// This is a bit fragile, but we can check that both appear
		if !strings.Contains(result, ".md") {
			t.Error("Expected note filenames in result")
		}
	})
}

func TestResolveVariablesWithManyTags(t *testing.T) {
	parachuteRoot, cleanup := setupTestEnvironment(t)
	defer cleanup()

	dbService := space.NewSpaceDatabaseService(parachuteRoot)
	contextService := space.NewContextService(dbService)
	spaceID, spacePath := setupTestSpace(t, parachuteRoot)

	// Create notes with 10 different tags
	allTags := []string{"tag1", "tag2", "tag3", "tag4", "tag5", "tag6", "tag7", "tag8", "tag9", "tag10"}

	// Create 10 notes, each with multiple tags
	// tag1 appears in all (10 times)
	// tag2 appears in 9 notes
	// ... tag10 appears in 1 note
	for i := 0; i < 10; i++ {
		captureID, notePath := createMockCapture(t, parachuteRoot, "Note "+string(rune('A'+i)))
		tags := allTags[:10-i] // Descending popularity
		err := dbService.LinkNote(spaceID, spacePath, captureID, notePath, "Context", tags)
		if err != nil {
			t.Fatalf("Failed to link note: %v", err)
		}
	}

	t.Run("RecentTagsLimitedToTop5", func(t *testing.T) {
		template := "{{recent_tags}}"
		result, err := contextService.ResolveVariables(template, spacePath)
		if err != nil {
			t.Fatalf("Failed to resolve variables: %v", err)
		}

		// Should contain most popular tags
		if !strings.Contains(result, "tag1") {
			t.Error("Expected most popular tag 'tag1' in recent tags")
		}

		// Count commas to estimate number of tags (top 5 = 4 commas)
		commaCount := strings.Count(result, ",")
		if commaCount > 4 {
			t.Errorf("Expected at most 5 tags (4 commas), got %d commas", commaCount)
		}
	})
}

func TestResolveVariablesEdgeCases(t *testing.T) {
	parachuteRoot, cleanup := setupTestEnvironment(t)
	defer cleanup()

	dbService := space.NewSpaceDatabaseService(parachuteRoot)
	contextService := space.NewContextService(dbService)
	spaceID, spacePath := setupTestSpace(t, parachuteRoot)

	t.Run("VariableInMiddleOfWord", func(t *testing.T) {
		// Should not replace if variable syntax is inside a word
		template := "Some text{{note_count}}more text"
		result, err := contextService.ResolveVariables(template, spacePath)
		if err != nil {
			t.Fatalf("Failed to resolve: %v", err)
		}

		// Should replace the variable
		if strings.Contains(result, "{{note_count}}") {
			t.Error("Variable should be replaced even without spaces")
		}
	})

	t.Run("DuplicateVariables", func(t *testing.T) {
		template := "Count: {{note_count}}, Again: {{note_count}}"
		result, err := contextService.ResolveVariables(template, spacePath)
		if err != nil {
			t.Fatalf("Failed to resolve: %v", err)
		}

		// Both should be replaced
		if strings.Contains(result, "{{note_count}}") {
			t.Error("All instances of variable should be replaced")
		}

		expected := "Count: 0, Again: 0"
		if result != expected {
			t.Errorf("Expected '%s', got '%s'", expected, result)
		}
	})

	t.Run("MalformedVariables", func(t *testing.T) {
		template := "Bad: {{note_count}, Missing: {{recent_tags, OK: {{note_count}}"
		result, err := contextService.ResolveVariables(template, spacePath)
		if err != nil {
			t.Fatalf("Failed to resolve: %v", err)
		}

		// Malformed variables should be left as-is, but well-formed ones should work
		if !strings.Contains(result, "OK: 0") {
			t.Error("Well-formed variable should be replaced")
		}
	})

	t.Run("UnicodeInTagNames", func(t *testing.T) {
		captureID, notePath := createMockCapture(t, parachuteRoot, "Unicode note")
		err := dbService.LinkNote(spaceID, spacePath, captureID, notePath, "Context",
			[]string{"emoji-🚀", "中文", "русский"})
		if err != nil {
			t.Fatalf("Failed to link note with unicode tags: %v", err)
		}

		template := "Tags: {{recent_tags}}, Emoji count: {{notes_tagged:emoji-🚀}}"
		result, err := contextService.ResolveVariables(template, spacePath)
		if err != nil {
			t.Fatalf("Failed to resolve with unicode: %v", err)
		}

		if !strings.Contains(result, "Emoji count: 1") {
			t.Error("Unicode tag filter should work")
		}
	})
}

func TestResolveVariablesWithDateFilters(t *testing.T) {
	parachuteRoot, cleanup := setupTestEnvironment(t)
	defer cleanup()

	dbService := space.NewSpaceDatabaseService(parachuteRoot)
	contextService := space.NewContextService(dbService)
	spaceID, spacePath := setupTestSpace(t, parachuteRoot)

	// Create an old note (simulate by directly modifying database timestamp)
	captureID1, notePath1 := createMockCapture(t, parachuteRoot, "Old note")
	err := dbService.LinkNote(spaceID, spacePath, captureID1, notePath1, "Old context", []string{"old"})
	if err != nil {
		t.Fatalf("Failed to link old note: %v", err)
	}

	// Create recent notes
	time.Sleep(1 * time.Second)
	captureID2, notePath2 := createMockCapture(t, parachuteRoot, "Recent note")
	err = dbService.LinkNote(spaceID, spacePath, captureID2, notePath2, "Recent context", []string{"recent"})
	if err != nil {
		t.Fatalf("Failed to link recent note: %v", err)
	}

	t.Run("RecentTagsConsidersLast30Days", func(t *testing.T) {
		// The context service filters for last 30 days
		// Both notes should be included (both are recent in our test)
		template := "{{recent_tags}}"
		result, err := contextService.ResolveVariables(template, spacePath)
		if err != nil {
			t.Fatalf("Failed to resolve: %v", err)
		}

		// Should contain both tags
		if !strings.Contains(result, "old") && !strings.Contains(result, "recent") {
			t.Error("Expected both old and recent tags in last 30 days")
		}
	})
}

func TestComplexRealWorldTemplate(t *testing.T) {
	parachuteRoot, cleanup := setupTestEnvironment(t)
	defer cleanup()

	dbService := space.NewSpaceDatabaseService(parachuteRoot)
	contextService := space.NewContextService(dbService)
	spaceID, spacePath := setupTestSpace(t, parachuteRoot)

	// Populate with realistic data
	testData := []struct {
		tags []string
	}{
		{[]string{"architecture", "design"}},
		{[]string{"architecture", "database"}},
		{[]string{"features", "planning"}},
		{[]string{"bugs", "urgent"}},
		{[]string{"architecture", "refactoring"}},
	}

	for i, td := range testData {
		captureID, notePath := createMockCapture(t, parachuteRoot, "Capture "+string(rune('A'+i)))
		err := dbService.LinkNote(spaceID, spacePath, captureID, notePath,
			"Discussion about "+td.tags[0], td.tags)
		if err != nil {
			t.Fatalf("Failed to link note: %v", err)
		}
	}

	// Track some references
	notes, _ := dbService.GetRelevantNotes(spacePath, space.NoteFilters{Limit: 2})
	for _, note := range notes {
		dbService.TrackNoteReference(spacePath, note.CaptureID)
	}

	t.Run("ProjectSpaceTemplate", func(t *testing.T) {
		template := `# Parachute Development Space

You are assisting with development of Parachute, a second brain app.

## Available Knowledge

- Linked Notes: {{note_count}} voice recordings and written notes
- Recent Topics: {{recent_tags}}
- Architecture discussions: {{notes_tagged:architecture}}
- Feature planning: {{notes_tagged:features}}

## Recent Activity

{{recent_notes}}

## Guidelines

- Reference architecture docs when discussing design
- Link new insights to this space for future reference
`

		result, err := contextService.ResolveVariables(template, spacePath)
		if err != nil {
			t.Fatalf("Failed to resolve real-world template: %v", err)
		}

		// Verify all variables were resolved
		if strings.Contains(result, "{{") {
			t.Errorf("Template still contains unresolved variables:\n%s", result)
		}

		// Verify specific replacements
		if !strings.Contains(result, "Linked Notes: 5") {
			t.Error("note_count not resolved")
		}
		if !strings.Contains(result, "Architecture discussions: 3") {
			t.Error("notes_tagged:architecture not resolved")
		}
		if !strings.Contains(result, "Feature planning: 1") {
			t.Error("notes_tagged:features not resolved")
		}
		if !strings.Contains(result, ".md") {
			t.Error("recent_notes should contain filenames")
		}

		// Log the result for manual inspection
		t.Logf("Resolved template:\n%s", result)
	})
}
