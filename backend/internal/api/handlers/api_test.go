package handlers_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/gofiber/fiber/v3"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/unforced/parachute-backend/internal/api/handlers"
	"github.com/unforced/parachute-backend/internal/domain/conversation"
	"github.com/unforced/parachute-backend/internal/domain/space"
	"github.com/unforced/parachute-backend/internal/storage/sqlite"
)

// setupTestApp creates a test Fiber app with all routes configured
func setupTestApp(t *testing.T) (*fiber.App, *sqlite.Database) {
	// Create temporary database
	dbPath := t.TempDir() + "/test.db"
	db, err := sqlite.NewDatabase(dbPath)
	require.NoError(t, err)
	t.Cleanup(func() { db.Close() })

	// Initialize repositories
	spaceRepo := sqlite.NewSpaceRepository(db.DB)
	conversationRepo := sqlite.NewConversationRepository(db.DB)

	// Initialize services
	spaceService := space.NewService(spaceRepo, "/tmp/parachute-test")
	conversationService := conversation.NewService(conversationRepo)
	spaceDBService := space.NewSpaceDatabaseService("/tmp/parachute-test")
	contextService := space.NewContextService(spaceDBService)

	// Initialize handlers
	spaceHandler := handlers.NewSpaceHandler(spaceService)
	messageHandler := handlers.NewMessageHandler(conversationService, spaceService, contextService, nil, nil) // No ACP or WebSocket for tests

	// Create Fiber app
	app := fiber.New()

	// API routes
	api := app.Group("/api")

	// Space routes
	spaces := api.Group("/spaces")
	spaces.Get("/", spaceHandler.List)
	spaces.Post("/", spaceHandler.Create)
	spaces.Get("/:id", spaceHandler.Get)
	spaces.Put("/:id", spaceHandler.Update)
	spaces.Delete("/:id", spaceHandler.Delete)

	// Conversation routes
	conversations := api.Group("/conversations")
	conversations.Get("/", func(c fiber.Ctx) error {
		spaceID := c.Query("space_id")
		if spaceID == "" {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": "space_id query parameter required",
			})
		}

		convs, err := conversationService.ListConversations(c.Context(), spaceID)
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Failed to list conversations",
			})
		}

		return c.JSON(fiber.Map{
			"conversations": convs,
		})
	})

	conversations.Post("/", func(c fiber.Ctx) error {
		var params conversation.CreateConversationParams
		if err := c.Bind().JSON(&params); err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": "Invalid request body",
			})
		}

		conv, err := conversationService.CreateConversation(c.Context(), params)
		if err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": err.Error(),
			})
		}

		return c.Status(fiber.StatusCreated).JSON(conv)
	})

	// Message routes
	messages := api.Group("/messages")
	messages.Get("/", messageHandler.ListMessages)
	messages.Post("/", messageHandler.SendMessage)

	return app, db
}

// TestSpaceAPI tests all space-related endpoints
func TestSpaceAPI(t *testing.T) {
	app, _ := setupTestApp(t)

	var createdSpaceID string

	t.Run("CreateSpace", func(t *testing.T) {
		payload := map[string]interface{}{
			"name": "Test Space",
		}
		body, _ := json.Marshal(payload)

		req := httptest.NewRequest(http.MethodPost, "/api/spaces", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := app.Test(req)
		require.NoError(t, err)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusCreated, resp.StatusCode)

		var result map[string]interface{}
		err = json.NewDecoder(resp.Body).Decode(&result)
		require.NoError(t, err)

		assert.Equal(t, "Test Space", result["name"])
		// Path is auto-generated as {parachuteRoot}/spaces/test-space
		assert.Contains(t, result["path"], "/spaces/test-space")
		assert.NotEmpty(t, result["id"])

		createdSpaceID = result["id"].(string)
	})

	t.Run("ListSpaces", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/spaces", nil)

		resp, err := app.Test(req)
		require.NoError(t, err)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusOK, resp.StatusCode)

		var result map[string]interface{}
		err = json.NewDecoder(resp.Body).Decode(&result)
		require.NoError(t, err)

		spaces, ok := result["spaces"].([]interface{})
		require.True(t, ok, "Expected 'spaces' key with array value")
		assert.Greater(t, len(spaces), 0)
	})

	t.Run("GetSpace", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/spaces/"+createdSpaceID, nil)

		resp, err := app.Test(req)
		require.NoError(t, err)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusOK, resp.StatusCode)

		var result map[string]interface{}
		err = json.NewDecoder(resp.Body).Decode(&result)
		require.NoError(t, err)

		assert.Equal(t, createdSpaceID, result["id"])
		assert.Equal(t, "Test Space", result["name"])
	})

	t.Run("UpdateSpace", func(t *testing.T) {
		payload := map[string]interface{}{
			"name": "Updated Space",
		}
		body, _ := json.Marshal(payload)

		req := httptest.NewRequest(http.MethodPut, "/api/spaces/"+createdSpaceID, bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := app.Test(req)
		require.NoError(t, err)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusOK, resp.StatusCode)

		var result map[string]interface{}
		err = json.NewDecoder(resp.Body).Decode(&result)
		require.NoError(t, err)

		assert.Equal(t, "Updated Space", result["name"])
	})

	t.Run("DeleteSpace", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodDelete, "/api/spaces/"+createdSpaceID, nil)

		resp, err := app.Test(req)
		require.NoError(t, err)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusNoContent, resp.StatusCode)
	})
}

// TestConversationAPI tests conversation-related endpoints
func TestConversationAPI(t *testing.T) {
	app, _ := setupTestApp(t)

	// First create a space
	spacePayload := map[string]interface{}{
		"name": "Test Space",
		"path": "/tmp/test-space",
	}
	spaceBody, _ := json.Marshal(spacePayload)
	spaceReq := httptest.NewRequest(http.MethodPost, "/api/spaces", bytes.NewReader(spaceBody))
	spaceReq.Header.Set("Content-Type", "application/json")
	spaceResp, _ := app.Test(spaceReq)
	var spaceResult map[string]interface{}
	json.NewDecoder(spaceResp.Body).Decode(&spaceResult)
	spaceID := spaceResult["id"].(string)
	spaceResp.Body.Close()

	var createdConvID string

	t.Run("CreateConversation", func(t *testing.T) {
		payload := map[string]interface{}{
			"space_id": spaceID,
			"title":    "Test Conversation",
		}
		body, _ := json.Marshal(payload)

		req := httptest.NewRequest(http.MethodPost, "/api/conversations", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := app.Test(req)
		require.NoError(t, err)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusCreated, resp.StatusCode)

		var result map[string]interface{}
		err = json.NewDecoder(resp.Body).Decode(&result)
		require.NoError(t, err)

		assert.Equal(t, "Test Conversation", result["title"])
		assert.Equal(t, spaceID, result["space_id"])
		assert.NotEmpty(t, result["id"])

		createdConvID = result["id"].(string)
	})

	t.Run("ListConversations", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/conversations?space_id="+spaceID, nil)

		resp, err := app.Test(req)
		require.NoError(t, err)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusOK, resp.StatusCode)

		var result map[string]interface{}
		err = json.NewDecoder(resp.Body).Decode(&result)
		require.NoError(t, err)

		conversations, ok := result["conversations"].([]interface{})
		require.True(t, ok, "Expected 'conversations' key with array value")
		assert.Greater(t, len(conversations), 0)
	})

	t.Run("ListConversationsWithoutSpaceID", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/conversations", nil)

		resp, err := app.Test(req)
		require.NoError(t, err)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusBadRequest, resp.StatusCode)
	})

	_ = createdConvID // For future message tests
}

// TestMessageAPI tests message-related endpoints
func TestMessageAPI(t *testing.T) {
	app, _ := setupTestApp(t)

	// Create space and conversation
	spacePayload := map[string]interface{}{
		"name": "Test Space",
		"path": "/tmp/test-space",
	}
	spaceBody, _ := json.Marshal(spacePayload)
	spaceReq := httptest.NewRequest(http.MethodPost, "/api/spaces", bytes.NewReader(spaceBody))
	spaceReq.Header.Set("Content-Type", "application/json")
	spaceResp, _ := app.Test(spaceReq)
	var spaceResult map[string]interface{}
	json.NewDecoder(spaceResp.Body).Decode(&spaceResult)
	spaceID := spaceResult["id"].(string)
	spaceResp.Body.Close()

	convPayload := map[string]interface{}{
		"space_id": spaceID,
		"title":    "Test Conversation",
	}
	convBody, _ := json.Marshal(convPayload)
	convReq := httptest.NewRequest(http.MethodPost, "/api/conversations", bytes.NewReader(convBody))
	convReq.Header.Set("Content-Type", "application/json")
	convResp, _ := app.Test(convReq)
	var convResult map[string]interface{}
	json.NewDecoder(convResp.Body).Decode(&convResult)
	convID := convResult["id"].(string)
	convResp.Body.Close()

	t.Run("SendMessage", func(t *testing.T) {
		payload := map[string]interface{}{
			"conversation_id": convID,
			"content":         "Hello, this is a test message",
		}
		body, _ := json.Marshal(payload)

		req := httptest.NewRequest(http.MethodPost, "/api/messages", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := app.Test(req)
		require.NoError(t, err)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusCreated, resp.StatusCode)

		var result map[string]interface{}
		err = json.NewDecoder(resp.Body).Decode(&result)
		require.NoError(t, err)

		assert.Equal(t, "Hello, this is a test message", result["content"])
		assert.Equal(t, "user", result["role"])
	})

	t.Run("ListMessages", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/messages?conversation_id="+convID, nil)

		resp, err := app.Test(req)
		require.NoError(t, err)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusOK, resp.StatusCode)

		var result map[string]interface{}
		err = json.NewDecoder(resp.Body).Decode(&result)
		require.NoError(t, err)

		messages, ok := result["messages"].([]interface{})
		require.True(t, ok, "Expected 'messages' key with array value")
		assert.Greater(t, len(messages), 0)
	})
}

func TestMain(m *testing.M) {
	// Run tests
	code := m.Run()
	os.Exit(code)
}
