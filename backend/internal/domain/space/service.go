package space

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/unforced/parachute-backend/internal/domain"
)

// Service provides business logic for spaces
type Service struct {
	repo          Repository
	parachuteRoot string
}

// NewService creates a new space service
func NewService(repo Repository, parachuteRoot string) *Service {
	return &Service{
		repo:          repo,
		parachuteRoot: parachuteRoot,
	}
}

// sanitizeName converts a space name to a filesystem-safe name
// Example: "Work Project" -> "work-project"
func sanitizeName(name string) string {
	// Convert to lowercase
	s := strings.ToLower(name)

	// Replace spaces and underscores with hyphens
	s = strings.ReplaceAll(s, " ", "-")
	s = strings.ReplaceAll(s, "_", "-")

	// Remove any non-alphanumeric characters except hyphens
	reg := regexp.MustCompile("[^a-z0-9-]+")
	s = reg.ReplaceAllString(s, "")

	// Remove leading/trailing hyphens
	s = strings.Trim(s, "-")

	// Replace multiple consecutive hyphens with single hyphen
	reg = regexp.MustCompile("-+")
	s = reg.ReplaceAllString(s, "-")

	return s
}

// Create creates a new space with validation and auto-generated path
func (s *Service) Create(ctx context.Context, userID string, params CreateSpaceParams) (*Space, error) {
	// Validate name
	if params.Name == "" {
		return nil, domain.NewValidationError("name", "space name is required")
	}

	// Auto-generate path from name
	sanitized := sanitizeName(params.Name)
	if sanitized == "" {
		return nil, domain.NewValidationError("name", "space name contains no valid characters")
	}

	// Build absolute path: ~/Parachute/spaces/{sanitized-name}
	spacePath := filepath.Join(s.parachuteRoot, "spaces", sanitized)

	// Check if space already exists at this path
	existing, err := s.repo.GetByPath(ctx, spacePath)
	if err == nil && existing != nil {
		return nil, domain.NewConflictError("space", fmt.Sprintf("space already exists with name: %s", params.Name))
	}

	// Create the directory structure
	if err := os.MkdirAll(spacePath, 0755); err != nil {
		return nil, fmt.Errorf("failed to create space directory: %w", err)
	}

	// Create files/ subdirectory
	filesDir := filepath.Join(spacePath, "files")
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create files directory: %w", err)
	}

	// Create SPACE.md with template (agent-agnostic, works with any AI assistant)
	spaceMDPath := filepath.Join(spacePath, "SPACE.md")
	spaceMDTemplate := fmt.Sprintf(`# %s

This space is for organizing conversations and knowledge related to %s.

## Context
Add relevant context here to help AI assistants understand this space.

## Available Knowledge
- Linked notes will appear here as you connect recordings and notes to this space
- Use the space.sqlite database to track relationships and metadata

## Guidelines
- Keep conversations focused on topics related to this space
- Upload relevant files to the files/ directory
- Link recordings and notes to build your knowledge base

## Files
See the files/ directory for uploaded documents and resources.
`, params.Name, params.Name)

	if err := os.WriteFile(spaceMDPath, []byte(spaceMDTemplate), 0644); err != nil {
		return nil, fmt.Errorf("failed to create SPACE.md: %w", err)
	}

	// Create space record
	now := time.Now()
	space := &Space{
		ID:        uuid.New().String(),
		UserID:    userID,
		Name:      params.Name,
		Path:      spacePath,
		Icon:      params.Icon,
		Color:     params.Color,
		CreatedAt: now,
		UpdatedAt: now,
	}

	if err := s.repo.Create(ctx, space); err != nil {
		return nil, fmt.Errorf("failed to create space: %w", err)
	}

	return space, nil
}

// GetByID retrieves a space by ID
func (s *Service) GetByID(ctx context.Context, id string) (*Space, error) {
	space, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return nil, domain.NewNotFoundError("space", id)
	}
	return space, nil
}

// List retrieves all spaces for a user
func (s *Service) List(ctx context.Context, userID string) ([]*Space, error) {
	return s.repo.List(ctx, userID)
}

// Update updates a space
func (s *Service) Update(ctx context.Context, id string, params UpdateSpaceParams) (*Space, error) {
	// Get existing space
	space, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}

	// Update fields
	if params.Name != "" {
		space.Name = params.Name
	}
	if params.Icon != "" {
		space.Icon = params.Icon
	}
	if params.Color != "" {
		space.Color = params.Color
	}

	// Save
	if err := s.repo.Update(ctx, space); err != nil {
		return nil, fmt.Errorf("failed to update space: %w", err)
	}

	return space, nil
}

// Delete deletes a space
func (s *Service) Delete(ctx context.Context, id string) error {
	return s.repo.Delete(ctx, id)
}

// GetSpaceMDPath returns the path to the SPACE.md file for a space
func (s *Service) GetSpaceMDPath(space *Space) string {
	return filepath.Join(space.Path, "SPACE.md")
}

// GetMCPConfigPath returns the path to the .mcp.json file for a space
func (s *Service) GetMCPConfigPath(space *Space) string {
	return filepath.Join(space.Path, ".mcp.json")
}

// ReadSpaceMD reads the SPACE.md file for a space
// Falls back to agents.md or CLAUDE.md for backward compatibility
func (s *Service) ReadSpaceMD(space *Space) (string, error) {
	// Try SPACE.md first (current standard)
	spaceMDPath := filepath.Join(space.Path, "SPACE.md")
	data, err := os.ReadFile(spaceMDPath)
	if err == nil {
		return string(data), nil
	}

	// Fall back to agents.md (previous iteration)
	agentsMDPath := filepath.Join(space.Path, "agents.md")
	data, err = os.ReadFile(agentsMDPath)
	if err == nil {
		return string(data), nil
	}

	// Fall back to CLAUDE.md (legacy)
	claudeMDPath := filepath.Join(space.Path, "CLAUDE.md")
	data, err = os.ReadFile(claudeMDPath)
	if err != nil {
		if os.IsNotExist(err) {
			return "", nil // No context file is okay
		}
		return "", fmt.Errorf("failed to read space context file: %w", err)
	}

	return string(data), nil
}

// ReadClaudeMD is deprecated, use ReadSpaceMD instead
// Kept for backward compatibility
func (s *Service) ReadClaudeMD(space *Space) (string, error) {
	return s.ReadSpaceMD(space)
}
