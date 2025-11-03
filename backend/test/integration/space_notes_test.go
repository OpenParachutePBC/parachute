package integration

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/gofiber/fiber/v3"
	"github.com/google/uuid"
	"github.com/unforced/parachute-backend/internal/api/handlers"
	"github.com/unforced/parachute-backend/internal/domain/space"
	sqliteStorage "github.com/unforced/parachute-backend/internal/storage/sqlite"
)

// testContext holds shared test infrastructure
type testContext struct {
	app            *fiber.App
	tmpDir         string
	db             *sqliteStorage.Database
	spaceService   *space.Service
	spaceDBService *space.SpaceDatabaseService
	cleanup        func()
}

// setupTestApp creates a test Fiber app with Space Notes routes
func setupTestApp(t *testing.T) *testContext {
	// Create temporary directory
	tmpDir, err := os.MkdirTemp("", "parachute-integration-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}

	// Create database
	dbPath := filepath.Join(tmpDir, "test.db")
	db, err := sqliteStorage.NewDatabase(dbPath)
	if err != nil {
		t.Fatalf("Failed to create database: %v", err)
	}

	// Create services
	spaceRepo := sqliteStorage.NewSpaceRepository(db.DB)
	spaceService := space.NewService(spaceRepo, tmpDir)
	spaceDBService := space.NewSpaceDatabaseService(tmpDir)

	// Create handlers
	spaceNotesHandler := handlers.NewSpaceNotesHandler(spaceService, spaceDBService)

	// Create Fiber app
	app := fiber.New()

	// Register routes
	api := app.Group("/api")
	spaces := api.Group("/spaces")
	spaces.Get("/:id/notes", spaceNotesHandler.GetNotes)
	spaces.Post("/:id/notes", spaceNotesHandler.LinkNote)
	spaces.Put("/:id/notes/:capture_id", spaceNotesHandler.UpdateNoteContext)
	spaces.Delete("/:id/notes/:capture_id", spaceNotesHandler.UnlinkNote)
	spaces.Get("/:id/notes/:capture_id/content", spaceNotesHandler.GetNoteContent)
	spaces.Get("/:id/database/stats", spaceNotesHandler.GetDatabaseStats)
	spaces.Get("/:id/database/tables/:table_name", spaceNotesHandler.GetTableData)

	cleanup := func() {
		db.Close()
		os.RemoveAll(tmpDir)
	}

	return &testContext{
		app:            app,
		tmpDir:         tmpDir,
		db:             db,
		spaceService:   spaceService,
		spaceDBService: spaceDBService,
		cleanup:        cleanup,
	}
}

// createTestSpace creates a space in the test environment using the space service
func createTestSpace(t *testing.T, ctx *testContext) (spaceID, spacePath string) {
	// Use the space service to create a proper space
	testCtx := context.Background()
	testSpace, err := ctx.spaceService.Create(
		testCtx,
		"test-user",
		space.CreateSpaceParams{
			Name: "Test Space " + uuid.New().String()[:8],
		},
	)
	if err != nil {
		t.Fatalf("Failed to create space: %v", err)
	}

	// Initialize space.sqlite
	if err := ctx.spaceDBService.InitializeSpaceDatabase(testSpace.ID, testSpace.Path); err != nil {
		t.Fatalf("Failed to initialize space database: %v", err)
	}

	return testSpace.ID, testSpace.Path
}

// createTestCapture creates a mock capture file
func createTestCapture(t *testing.T, tmpDir string, content string) (captureID, notePath string) {
	capturesDir := filepath.Join(tmpDir, "captures")
	if err := os.MkdirAll(capturesDir, 0755); err != nil {
		t.Fatalf("Failed to create captures directory: %v", err)
	}

	captureID = uuid.New().String()
	timestamp := time.Now().Format("2006-01-02_15-04-05")
	filename := timestamp + ".md"
	notePath = filepath.Join("captures", filename)
	fullPath := filepath.Join(tmpDir, notePath)

	if err := os.WriteFile(fullPath, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create capture file: %v", err)
	}

	return captureID, notePath
}

func TestLinkNoteEndpoint(t *testing.T) {
	ctx := setupTestApp(t)
	defer ctx.cleanup()

	spaceID, _ := createTestSpace(t, ctx)
	captureID, notePath := createTestCapture(t, ctx.tmpDir, "Test capture content")

	t.Run("SuccessWithAllFields", func(t *testing.T) {
		reqBody := map[string]interface{}{
			"capture_id": captureID,
			"note_path":  notePath,
			"context":    "This is a test note",
			"tags":       []string{"test", "integration"},
		}

		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", fmt.Sprintf("/api/spaces/%s/notes", spaceID), bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusCreated {
			t.Errorf("Expected status 201, got %d", resp.StatusCode)
		}

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)

		if result["capture_id"] != captureID {
			t.Errorf("Expected capture_id %s, got %v", captureID, result["capture_id"])
		}
	})

	t.Run("SuccessWithMinimalFields", func(t *testing.T) {
		captureID2, notePath2 := createTestCapture(t, ctx.tmpDir, "Minimal capture")

		reqBody := map[string]interface{}{
			"capture_id": captureID2,
			"note_path":  notePath2,
		}

		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", fmt.Sprintf("/api/spaces/%s/notes", spaceID), bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusCreated {
			t.Errorf("Expected status 201, got %d", resp.StatusCode)
		}
	})

	t.Run("ErrorMissingCaptureID", func(t *testing.T) {
		reqBody := map[string]interface{}{
			"note_path": notePath,
		}

		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", fmt.Sprintf("/api/spaces/%s/notes", spaceID), bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusBadRequest {
			t.Errorf("Expected status 400, got %d", resp.StatusCode)
		}
	})

	t.Run("ErrorMissingNotePath", func(t *testing.T) {
		reqBody := map[string]interface{}{
			"capture_id": captureID,
		}

		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", fmt.Sprintf("/api/spaces/%s/notes", spaceID), bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusBadRequest {
			t.Errorf("Expected status 400, got %d", resp.StatusCode)
		}
	})

	t.Run("ErrorInvalidSpaceID", func(t *testing.T) {
		reqBody := map[string]interface{}{
			"capture_id": captureID,
			"note_path":  notePath,
		}

		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/api/spaces/invalid-space-id/notes", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusNotFound {
			t.Errorf("Expected status 404, got %d", resp.StatusCode)
		}
	})

	t.Run("UpsertBehavior", func(t *testing.T) {
		// Link the same capture again with different context
		reqBody := map[string]interface{}{
			"capture_id": captureID,
			"note_path":  notePath,
			"context":    "Updated context",
			"tags":       []string{"updated"},
		}

		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", fmt.Sprintf("/api/spaces/%s/notes", spaceID), bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusCreated {
			t.Errorf("Expected status 201 on upsert, got %d", resp.StatusCode)
		}

		// Verify only one note exists
		getReq := httptest.NewRequest("GET", fmt.Sprintf("/api/spaces/%s/notes", spaceID), nil)
		getResp, _ := ctx.app.Test(getReq)

		var getResult map[string]interface{}
		json.NewDecoder(getResp.Body).Decode(&getResult)

		notes := getResult["notes"].([]interface{})
		// Should have 2 total notes (captureID and captureID2)
		if len(notes) != 2 {
			t.Errorf("Expected 2 notes total, got %d", len(notes))
		}
	})
}

func TestGetNotesEndpoint(t *testing.T) {
	ctx := setupTestApp(t)
	defer ctx.cleanup()

	spaceID, spacePath := createTestSpace(t, ctx)

	t.Run("EmptyList", func(t *testing.T) {
		req := httptest.NewRequest("GET", fmt.Sprintf("/api/spaces/%s/notes", spaceID), nil)
		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusOK {
			t.Errorf("Expected status 200, got %d", resp.StatusCode)
		}

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)

		notes := result["notes"].([]interface{})
		if len(notes) != 0 {
			t.Errorf("Expected 0 notes, got %d", len(notes))
		}
	})

	// Link some notes (use spacePath from createTestSpace)

	testNotes := []struct {
		tags []string
	}{
		{[]string{"tag1", "tag2"}},
		{[]string{"tag2", "tag3"}},
		{[]string{"tag3", "tag4"}},
	}

	for _, tn := range testNotes {
		captureID, notePath := createTestCapture(t, ctx.tmpDir, "Content")
		ctx.spaceDBService.LinkNote(spaceID, spacePath, captureID, notePath, "Context", tn.tags)
	}

	t.Run("ListWithMultipleNotes", func(t *testing.T) {
		req := httptest.NewRequest("GET", fmt.Sprintf("/api/spaces/%s/notes", spaceID), nil)
		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusOK {
			t.Errorf("Expected status 200, got %d", resp.StatusCode)
		}

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)

		notes := result["notes"].([]interface{})
		if len(notes) != 3 {
			t.Errorf("Expected 3 notes, got %d", len(notes))
		}
	})

	t.Run("FilterByTags", func(t *testing.T) {
		req := httptest.NewRequest("GET", fmt.Sprintf("/api/spaces/%s/notes?tags=tag2", spaceID), nil)
		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)

		notes := result["notes"].([]interface{})
		if len(notes) != 2 {
			t.Errorf("Expected 2 notes with tag2, got %d", len(notes))
		}
	})

	t.Run("Pagination", func(t *testing.T) {
		req := httptest.NewRequest("GET", fmt.Sprintf("/api/spaces/%s/notes?limit=2&offset=0", spaceID), nil)
		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)

		notes := result["notes"].([]interface{})
		if len(notes) != 2 {
			t.Errorf("Expected 2 notes on first page, got %d", len(notes))
		}

		// Second page
		req2 := httptest.NewRequest("GET", fmt.Sprintf("/api/spaces/%s/notes?limit=2&offset=2", spaceID), nil)
		resp2, _ := ctx.app.Test(req2)

		var result2 map[string]interface{}
		json.NewDecoder(resp2.Body).Decode(&result2)

		notes2 := result2["notes"].([]interface{})
		if len(notes2) != 1 {
			t.Errorf("Expected 1 note on second page, got %d", len(notes2))
		}
	})

	t.Run("DateRangeFilter", func(t *testing.T) {
		now := time.Now()
		startDate := now.Add(-1 * time.Hour).Format(time.RFC3339)
		endDate := now.Add(1 * time.Hour).Format(time.RFC3339)

		req := httptest.NewRequest("GET",
			fmt.Sprintf("/api/spaces/%s/notes?start_date=%s&end_date=%s", spaceID, startDate, endDate),
			nil)
		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusOK {
			t.Errorf("Expected status 200, got %d", resp.StatusCode)
		}
	})
}

func TestUpdateNoteContextEndpoint(t *testing.T) {
	ctx := setupTestApp(t)
	defer ctx.cleanup()

	spaceID, spacePath := createTestSpace(t, ctx)
	captureID, notePath := createTestCapture(t, ctx.tmpDir, "Test capture")

	// Link initial note
	ctx.spaceDBService.LinkNote(spaceID, spacePath, captureID, notePath, "Original context", []string{"original"})

	t.Run("UpdateContextOnly", func(t *testing.T) {
		reqBody := map[string]interface{}{
			"context": "Updated context only",
		}

		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("PUT",
			fmt.Sprintf("/api/spaces/%s/notes/%s", spaceID, captureID),
			bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusOK {
			t.Errorf("Expected status 200, got %d", resp.StatusCode)
		}
	})

	t.Run("UpdateTagsOnly", func(t *testing.T) {
		reqBody := map[string]interface{}{
			"tags": []string{"new", "tags"},
		}

		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("PUT",
			fmt.Sprintf("/api/spaces/%s/notes/%s", spaceID, captureID),
			bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusOK {
			t.Errorf("Expected status 200, got %d", resp.StatusCode)
		}
	})

	t.Run("UpdateBoth", func(t *testing.T) {
		reqBody := map[string]interface{}{
			"context": "Both updated",
			"tags":    []string{"both"},
		}

		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("PUT",
			fmt.Sprintf("/api/spaces/%s/notes/%s", spaceID, captureID),
			bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusOK {
			t.Errorf("Expected status 200, got %d", resp.StatusCode)
		}
	})

	t.Run("ErrorNoteNotFound", func(t *testing.T) {
		nonExistentID := uuid.New().String()
		reqBody := map[string]interface{}{
			"context": "Should fail",
		}

		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("PUT",
			fmt.Sprintf("/api/spaces/%s/notes/%s", spaceID, nonExistentID),
			bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusNotFound {
			t.Errorf("Expected status 404, got %d", resp.StatusCode)
		}
	})

	t.Run("ErrorNoFieldsProvided", func(t *testing.T) {
		reqBody := map[string]interface{}{}

		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("PUT",
			fmt.Sprintf("/api/spaces/%s/notes/%s", spaceID, captureID),
			bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusBadRequest {
			t.Errorf("Expected status 400, got %d", resp.StatusCode)
		}
	})
}

func TestUnlinkNoteEndpoint(t *testing.T) {
	ctx := setupTestApp(t)
	defer ctx.cleanup()

	spaceID, spacePath := createTestSpace(t, ctx)
	captureID, notePath := createTestCapture(t, ctx.tmpDir, "Test capture")

	// Link note
	ctx.spaceDBService.LinkNote(spaceID, spacePath, captureID, notePath, "Context", []string{"tag"})

	t.Run("SuccessfulUnlink", func(t *testing.T) {
		req := httptest.NewRequest("DELETE",
			fmt.Sprintf("/api/spaces/%s/notes/%s", spaceID, captureID),
			nil)

		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusOK {
			t.Errorf("Expected status 200, got %d", resp.StatusCode)
		}

		// Verify note is gone
		getReq := httptest.NewRequest("GET", fmt.Sprintf("/api/spaces/%s/notes", spaceID), nil)
		getResp, _ := ctx.app.Test(getReq)

		var result map[string]interface{}
		json.NewDecoder(getResp.Body).Decode(&result)

		notes := result["notes"].([]interface{})
		if len(notes) != 0 {
			t.Errorf("Expected 0 notes after unlink, got %d", len(notes))
		}
	})

	t.Run("ErrorNoteNotFound", func(t *testing.T) {
		nonExistentID := uuid.New().String()
		req := httptest.NewRequest("DELETE",
			fmt.Sprintf("/api/spaces/%s/notes/%s", spaceID, nonExistentID),
			nil)

		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusNotFound {
			t.Errorf("Expected status 404, got %d", resp.StatusCode)
		}
	})
}

func TestGetNoteContentEndpoint(t *testing.T) {
	ctx := setupTestApp(t)
	defer ctx.cleanup()

	spaceID, spacePath := createTestSpace(t, ctx)
	captureContent := "# Test Capture\n\nThis is the content of the capture."
	captureID, notePath := createTestCapture(t, ctx.tmpDir, captureContent)

	// Link note
	contextText := "Space-specific context"
	tags := []string{"test", "content"}
	ctx.spaceDBService.LinkNote(spaceID, spacePath, captureID, notePath, contextText, tags)

	t.Run("SuccessfulGetContent", func(t *testing.T) {
		req := httptest.NewRequest("GET",
			fmt.Sprintf("/api/spaces/%s/notes/%s/content", spaceID, captureID),
			nil)

		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusOK {
			bodyBytes, _ := io.ReadAll(resp.Body)
			t.Errorf("Expected status 200, got %d. Body: %s", resp.StatusCode, string(bodyBytes))
		}

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)

		if result["content"] != captureContent {
			t.Errorf("Expected content %s, got %v", captureContent, result["content"])
		}

		if result["space_context"] != contextText {
			t.Errorf("Expected space_context %s, got %v", contextText, result["space_context"])
		}

		if result["capture_id"] != captureID {
			t.Errorf("Expected capture_id %s, got %v", captureID, result["capture_id"])
		}

		// Verify tags
		resultTags := result["tags"].([]interface{})
		if len(resultTags) != 2 {
			t.Errorf("Expected 2 tags, got %d", len(resultTags))
		}
	})

	t.Run("ErrorNoteNotFound", func(t *testing.T) {
		nonExistentID := uuid.New().String()
		req := httptest.NewRequest("GET",
			fmt.Sprintf("/api/spaces/%s/notes/%s/content", spaceID, nonExistentID),
			nil)

		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusNotFound {
			t.Errorf("Expected status 404, got %d", resp.StatusCode)
		}
	})

	t.Run("LastReferencedTracking", func(t *testing.T) {
		// Get the note (which should track the reference)
		req := httptest.NewRequest("GET",
			fmt.Sprintf("/api/spaces/%s/notes/%s/content", spaceID, captureID),
			nil)
		ctx.app.Test(req)

		// Get the note metadata to check last_referenced was set
		note, _ := ctx.spaceDBService.GetNoteByID(spacePath, captureID)
		if note.LastReferenced == nil {
			t.Error("Expected last_referenced to be set after getting content")
		}
	})
}

func TestGetDatabaseStatsEndpoint(t *testing.T) {
	ctx := setupTestApp(t)
	defer ctx.cleanup()

	spaceID, spacePath := createTestSpace(t, ctx)

	// Link some notes
	for i := 0; i < 3; i++ {
		captureID, notePath := createTestCapture(t, ctx.tmpDir, fmt.Sprintf("Capture %d", i))
		ctx.spaceDBService.LinkNote(spaceID, spacePath, captureID, notePath, "Context", []string{"tag1", "tag2"})
	}

	t.Run("GetStats", func(t *testing.T) {
		req := httptest.NewRequest("GET",
			fmt.Sprintf("/api/spaces/%s/database/stats", spaceID),
			nil)

		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusOK {
			t.Errorf("Expected status 200, got %d", resp.StatusCode)
		}

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)

		if result["total_notes"] != float64(3) {
			t.Errorf("Expected total_notes 3, got %v", result["total_notes"])
		}

		if result["space_id"] != spaceID {
			t.Errorf("Expected space_id %s, got %v", spaceID, result["space_id"])
		}

		if result["schema_version"] != "1" {
			t.Errorf("Expected schema_version 1, got %v", result["schema_version"])
		}

		// Check tables array
		tables := result["tables"].([]interface{})
		if len(tables) < 2 {
			t.Errorf("Expected at least 2 tables, got %d", len(tables))
		}
	})
}

func TestGetTableDataEndpoint(t *testing.T) {
	ctx := setupTestApp(t)
	defer ctx.cleanup()

	spaceID, spacePath := createTestSpace(t, ctx)

	// Link a note
	captureID, notePath := createTestCapture(t, ctx.tmpDir, "Test")
	ctx.spaceDBService.LinkNote(spaceID, spacePath, captureID, notePath, "Context", []string{"tag1"})

	t.Run("QueryRelevantNotesTable", func(t *testing.T) {
		req := httptest.NewRequest("GET",
			fmt.Sprintf("/api/spaces/%s/database/tables/relevant_notes", spaceID),
			nil)

		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusOK {
			t.Errorf("Expected status 200, got %d", resp.StatusCode)
		}

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)

		if result["table_name"] != "relevant_notes" {
			t.Errorf("Expected table_name 'relevant_notes', got %v", result["table_name"])
		}

		if result["row_count"] != float64(1) {
			t.Errorf("Expected row_count 1, got %v", result["row_count"])
		}
	})

	t.Run("QueryInvalidTable", func(t *testing.T) {
		// Use a simple invalid table name (the actual SQL injection protection is tested in unit tests)
		req := httptest.NewRequest("GET",
			fmt.Sprintf("/api/spaces/%s/database/tables/invalid_table_name", spaceID),
			nil)

		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusInternalServerError {
			t.Errorf("Expected status 500 for invalid table, got %d", resp.StatusCode)
		}
	})

	t.Run("QueryNonExistentTable", func(t *testing.T) {
		req := httptest.NewRequest("GET",
			fmt.Sprintf("/api/spaces/%s/database/tables/non_existent", spaceID),
			nil)

		resp, err := ctx.app.Test(req)
		if err != nil {
			t.Fatalf("Request failed: %v", err)
		}

		if resp.StatusCode != fiber.StatusInternalServerError {
			t.Errorf("Expected status 500 for non-existent table, got %d", resp.StatusCode)
		}
	})
}
