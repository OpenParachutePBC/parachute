package handlers

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"

	"github.com/gofiber/fiber/v3"
	"github.com/unforced/parachute-backend/internal/domain/space"
)

// SpaceNotesHandler handles space notes HTTP requests
type SpaceNotesHandler struct {
	spaceService   *space.Service
	spaceDBService *space.SpaceDatabaseService
}

// NewSpaceNotesHandler creates a new space notes handler
func NewSpaceNotesHandler(spaceService *space.Service, spaceDBService *space.SpaceDatabaseService) *SpaceNotesHandler {
	return &SpaceNotesHandler{
		spaceService:   spaceService,
		spaceDBService: spaceDBService,
	}
}

// LinkNoteRequest represents a request to link a note to a space
type LinkNoteRequest struct {
	CaptureID string   `json:"capture_id"`
	NotePath  string   `json:"note_path"`
	Context   string   `json:"context"`
	Tags      []string `json:"tags"`
}

// UpdateNoteContextRequest represents a request to update note context
type UpdateNoteContextRequest struct {
	Context *string   `json:"context,omitempty"`
	Tags    *[]string `json:"tags,omitempty"`
}

// GetNotesResponse wraps the list of notes
type GetNotesResponse struct {
	Notes []space.RelevantNote `json:"notes"`
	Total int                  `json:"total"`
}

// GetNotes handles GET /api/spaces/:id/notes
func (h *SpaceNotesHandler) GetNotes(c fiber.Ctx) error {
	spaceID := c.Params("id")
	if spaceID == "" {
		return fiber.NewError(fiber.StatusBadRequest, "space_id is required")
	}

	// Get space to get its path
	spaceObj, err := h.spaceService.GetByID(c.Context(), spaceID)
	if err != nil {
		return fiber.NewError(fiber.StatusNotFound, "space not found")
	}

	// Parse query parameters for filtering
	filters := space.NoteFilters{
		Limit:  50, // Default limit
		Offset: 0,
		Tags:   []string{},
	}

	// Parse tags filter (comma-separated)
	if tagsParam := c.Query("tags"); tagsParam != "" {
		// Simple split by comma (could enhance with proper parsing)
		filters.Tags = splitAndTrim(tagsParam, ",")
	}

	// Parse date filters
	if startDateStr := c.Query("start_date"); startDateStr != "" {
		if startDate, err := time.Parse(time.RFC3339, startDateStr); err == nil {
			filters.StartDate = &startDate
		}
	}

	if endDateStr := c.Query("end_date"); endDateStr != "" {
		if endDate, err := time.Parse(time.RFC3339, endDateStr); err == nil {
			filters.EndDate = &endDate
		}
	}

	// Parse limit and offset
	if limitStr := c.Query("limit"); limitStr != "" {
		if limit, err := parseInt(limitStr); err == nil && limit > 0 {
			filters.Limit = limit
		}
	}

	if offsetStr := c.Query("offset"); offsetStr != "" {
		if offset, err := parseInt(offsetStr); err == nil && offset >= 0 {
			filters.Offset = offset
		}
	}

	// Get notes from space database
	notes, err := h.spaceDBService.GetRelevantNotes(spaceObj.Path, filters)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, fmt.Sprintf("failed to get notes: %v", err))
	}

	return c.JSON(GetNotesResponse{
		Notes: notes,
		Total: len(notes),
	})
}

// LinkNote handles POST /api/spaces/:id/notes
func (h *SpaceNotesHandler) LinkNote(c fiber.Ctx) error {
	spaceID := c.Params("id")
	if spaceID == "" {
		return fiber.NewError(fiber.StatusBadRequest, "space_id is required")
	}

	// Get space to get its path
	spaceObj, err := h.spaceService.GetByID(c.Context(), spaceID)
	if err != nil {
		return fiber.NewError(fiber.StatusNotFound, "space not found")
	}

	// Parse request body
	var req LinkNoteRequest
	if err := c.Bind().JSON(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}

	// Validate required fields
	if req.CaptureID == "" {
		return fiber.NewError(fiber.StatusBadRequest, "capture_id is required")
	}
	if req.NotePath == "" {
		return fiber.NewError(fiber.StatusBadRequest, "note_path is required")
	}

	// Ensure space.sqlite exists
	if err := h.spaceDBService.InitializeSpaceDatabase(spaceID, spaceObj.Path); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, fmt.Sprintf("failed to initialize space database: %v", err))
	}

	// Link the note
	if err := h.spaceDBService.LinkNote(spaceID, spaceObj.Path, req.CaptureID, req.NotePath, req.Context, req.Tags); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, fmt.Sprintf("failed to link note: %v", err))
	}

	return c.Status(fiber.StatusCreated).JSON(fiber.Map{
		"message":    "note linked successfully",
		"space_id":   spaceID,
		"capture_id": req.CaptureID,
	})
}

// UpdateNoteContext handles PUT /api/spaces/:id/notes/:capture_id
func (h *SpaceNotesHandler) UpdateNoteContext(c fiber.Ctx) error {
	spaceID := c.Params("id")
	captureID := c.Params("capture_id")

	if spaceID == "" || captureID == "" {
		return fiber.NewError(fiber.StatusBadRequest, "space_id and capture_id are required")
	}

	// Get space to get its path
	spaceObj, err := h.spaceService.GetByID(c.Context(), spaceID)
	if err != nil {
		return fiber.NewError(fiber.StatusNotFound, "space not found")
	}

	// Parse request body
	var req UpdateNoteContextRequest
	if err := c.Bind().JSON(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}

	// Validate at least one field is provided
	if req.Context == nil && req.Tags == nil {
		return fiber.NewError(fiber.StatusBadRequest, "at least one of context or tags must be provided")
	}

	// Update note context
	if err := h.spaceDBService.UpdateNoteContext(spaceObj.Path, captureID, req.Context, req.Tags); err != nil {
		if err.Error() == "note not found in space" {
			return fiber.NewError(fiber.StatusNotFound, "note not found in space")
		}
		return fiber.NewError(fiber.StatusInternalServerError, fmt.Sprintf("failed to update note context: %v", err))
	}

	return c.JSON(fiber.Map{
		"message":    "note context updated successfully",
		"space_id":   spaceID,
		"capture_id": captureID,
	})
}

// UnlinkNote handles DELETE /api/spaces/:id/notes/:capture_id
func (h *SpaceNotesHandler) UnlinkNote(c fiber.Ctx) error {
	spaceID := c.Params("id")
	captureID := c.Params("capture_id")

	if spaceID == "" || captureID == "" {
		return fiber.NewError(fiber.StatusBadRequest, "space_id and capture_id are required")
	}

	// Get space to get its path
	spaceObj, err := h.spaceService.GetByID(c.Context(), spaceID)
	if err != nil {
		return fiber.NewError(fiber.StatusNotFound, "space not found")
	}

	// Unlink the note
	if err := h.spaceDBService.UnlinkNote(spaceObj.Path, captureID); err != nil {
		if err.Error() == "note not found in space" {
			return fiber.NewError(fiber.StatusNotFound, "note not found in space")
		}
		return fiber.NewError(fiber.StatusInternalServerError, fmt.Sprintf("failed to unlink note: %v", err))
	}

	return c.JSON(fiber.Map{
		"message":    "note unlinked successfully",
		"space_id":   spaceID,
		"capture_id": captureID,
	})
}

// GetNoteContent handles GET /api/spaces/:id/notes/:capture_id/content
func (h *SpaceNotesHandler) GetNoteContent(c fiber.Ctx) error {
	spaceID := c.Params("id")
	captureID := c.Params("capture_id")

	if spaceID == "" || captureID == "" {
		return fiber.NewError(fiber.StatusBadRequest, "space_id and capture_id are required")
	}

	// Get space to get its path
	spaceObj, err := h.spaceService.GetByID(c.Context(), spaceID)
	if err != nil {
		return fiber.NewError(fiber.StatusNotFound, "space not found")
	}

	// Get note metadata from space database
	note, err := h.spaceDBService.GetNoteByID(spaceObj.Path, captureID)
	if err != nil {
		if err.Error() == "note not found in space" {
			return fiber.NewError(fiber.StatusNotFound, "note not found in space")
		}
		return fiber.NewError(fiber.StatusInternalServerError, fmt.Sprintf("failed to get note: %v", err))
	}

	// Read note content from file system
	// note.NotePath is relative (e.g., "captures/2025-10-26_00-00-17.md")
	// We need to construct the full path from parachute root
	parachuteRoot := filepath.Dir(filepath.Dir(spaceObj.Path)) // Go up from spaces/space-name to ~/Parachute
	notePath := filepath.Join(parachuteRoot, note.NotePath)

	log.Printf("🔍 Reading note content:")
	log.Printf("  - Space path: %s", spaceObj.Path)
	log.Printf("  - Parachute root: %s", parachuteRoot)
	log.Printf("  - Note relative path: %s", note.NotePath)
	log.Printf("  - Full note path: %s", notePath)

	content, err := os.ReadFile(notePath)
	if err != nil {
		log.Printf("❌ Failed to read note file: %v", err)
		return fiber.NewError(fiber.StatusNotFound, fmt.Sprintf("note file not found: %s", notePath))
	}

	log.Printf("✅ Successfully read note content (%d bytes)", len(content))

	// Track that this note was referenced
	_ = h.spaceDBService.TrackNoteReference(spaceObj.Path, captureID) // Don't fail if tracking fails

	// Return both content and space-specific metadata
	return c.JSON(fiber.Map{
		"capture_id":      note.CaptureID,
		"note_path":       note.NotePath,
		"content":         string(content),
		"space_context":   note.Context,
		"tags":            note.Tags,
		"linked_at":       note.LinkedAt,
		"last_referenced": note.LastReferenced,
	})
}

// Helper functions

func splitAndTrim(s, sep string) []string {
	if s == "" {
		return []string{}
	}
	parts := []string{}
	for _, part := range splitString(s, sep) {
		trimmed := trimString(part)
		if trimmed != "" {
			parts = append(parts, trimmed)
		}
	}
	return parts
}

func splitString(s, sep string) []string {
	result := []string{}
	current := ""
	for _, char := range s {
		if string(char) == sep {
			result = append(result, current)
			current = ""
		} else {
			current += string(char)
		}
	}
	result = append(result, current)
	return result
}

func trimString(s string) string {
	start := 0
	end := len(s)

	// Trim leading whitespace
	for start < end && (s[start] == ' ' || s[start] == '\t' || s[start] == '\n' || s[start] == '\r') {
		start++
	}

	// Trim trailing whitespace
	for end > start && (s[end-1] == ' ' || s[end-1] == '\t' || s[end-1] == '\n' || s[end-1] == '\r') {
		end--
	}

	return s[start:end]
}

func parseInt(s string) (int, error) {
	result := 0
	for _, char := range s {
		if char < '0' || char > '9' {
			return 0, fmt.Errorf("invalid integer")
		}
		result = result*10 + int(char-'0')
	}
	return result, nil
}

// GetDatabaseStats handles GET /api/spaces/:id/database/stats
func (h *SpaceNotesHandler) GetDatabaseStats(c fiber.Ctx) error {
	spaceID := c.Params("id")
	if spaceID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "space_id is required",
		})
	}

	// Get space
	spaceObj, err := h.spaceService.GetByID(c.Context(), spaceID)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Space not found",
		})
	}

	// Get database stats
	stats, err := h.spaceDBService.GetDatabaseStats(spaceObj.Path)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": fmt.Sprintf("Failed to get database stats: %v", err),
		})
	}

	return c.JSON(stats)
}

// GetTableData handles GET /api/spaces/:id/database/tables/:table_name
func (h *SpaceNotesHandler) GetTableData(c fiber.Ctx) error {
	spaceID := c.Params("id")
	tableName := c.Params("table_name")

	if spaceID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "space_id is required",
		})
	}

	if tableName == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "table_name is required",
		})
	}

	// Get space
	spaceObj, err := h.spaceService.GetByID(c.Context(), spaceID)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Space not found",
		})
	}

	// Query table
	result, err := h.spaceDBService.QueryTable(spaceObj.Path, tableName)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": fmt.Sprintf("Failed to query table: %v", err),
		})
	}

	return c.JSON(result)
}
