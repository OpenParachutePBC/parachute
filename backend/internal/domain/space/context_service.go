package space

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// ContextService handles dynamic variable resolution for SPACE.md context files
type ContextService struct {
	spaceDBService *SpaceDatabaseService
}

// NewContextService creates a new context service
func NewContextService(spaceDBService *SpaceDatabaseService) *ContextService {
	return &ContextService{
		spaceDBService: spaceDBService,
	}
}

// ResolveVariables processes a SPACE.md template and replaces dynamic variables
// Supported variables:
// - {{note_count}} - Total number of linked notes
// - {{recent_tags}} - Top 5 most used tags (last 30 days)
// - {{recent_notes}} - Last 5 referenced notes (title + date)
// - {{notes_tagged:TAG}} - Count of notes with specific tag
func (s *ContextService) ResolveVariables(spaceMD string, spacePath string) (string, error) {
	result := spaceMD

	// Get space database connection
	dbPath := filepath.Join(spacePath, "space.sqlite")
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		// If database doesn't exist yet, return template as-is
		return spaceMD, nil
	}
	defer db.Close()

	// Replace {{note_count}}
	result = s.replaceNoteCount(result, db)

	// Replace {{recent_tags}}
	result = s.replaceRecentTags(result, db)

	// Replace {{recent_notes}}
	result = s.replaceRecentNotes(result, db, spacePath)

	// Replace {{notes_tagged:TAG}} patterns
	result = s.replaceNotesTagged(result, db)

	return result, nil
}

// replaceNoteCount replaces {{note_count}} with the total number of linked notes
func (s *ContextService) replaceNoteCount(text string, db *sql.DB) string {
	var count int
	err := db.QueryRow("SELECT COUNT(*) FROM relevant_notes").Scan(&count)
	if err != nil {
		return strings.ReplaceAll(text, "{{note_count}}", "0")
	}
	return strings.ReplaceAll(text, "{{note_count}}", fmt.Sprintf("%d", count))
}

// replaceRecentTags replaces {{recent_tags}} with top 5 most used tags from last 30 days
func (s *ContextService) replaceRecentTags(text string, db *sql.DB) string {
	if !strings.Contains(text, "{{recent_tags}}") {
		return text
	}

	// Get notes from last 30 days
	thirtyDaysAgo := time.Now().AddDate(0, 0, -30).Unix()

	rows, err := db.Query(`
		SELECT tags FROM relevant_notes
		WHERE linked_at >= ? OR last_referenced >= ?
		ORDER BY COALESCE(last_referenced, linked_at) DESC
	`, thirtyDaysAgo, thirtyDaysAgo)
	if err != nil {
		return strings.ReplaceAll(text, "{{recent_tags}}", "none")
	}
	defer rows.Close()

	// Count tag frequencies
	tagCounts := make(map[string]int)
	for rows.Next() {
		var tagsJSON string
		if err := rows.Scan(&tagsJSON); err != nil {
			continue
		}

		var tags []string
		if err := json.Unmarshal([]byte(tagsJSON), &tags); err != nil {
			continue
		}

		for _, tag := range tags {
			tagCounts[tag]++
		}
	}

	// Get top 5 tags
	type tagCount struct {
		tag   string
		count int
	}
	var topTags []tagCount
	for tag, count := range tagCounts {
		topTags = append(topTags, tagCount{tag, count})
	}

	// Sort by count (simple bubble sort for small data)
	for i := 0; i < len(topTags); i++ {
		for j := i + 1; j < len(topTags); j++ {
			if topTags[j].count > topTags[i].count {
				topTags[i], topTags[j] = topTags[j], topTags[i]
			}
		}
	}

	// Take top 5
	limit := 5
	if len(topTags) < limit {
		limit = len(topTags)
	}

	if limit == 0 {
		return strings.ReplaceAll(text, "{{recent_tags}}", "none")
	}

	// Format as comma-separated list
	var tagNames []string
	for i := 0; i < limit; i++ {
		tagNames = append(tagNames, topTags[i].tag)
	}

	return strings.ReplaceAll(text, "{{recent_tags}}", strings.Join(tagNames, ", "))
}

// replaceRecentNotes replaces {{recent_notes}} with last 5 referenced notes
func (s *ContextService) replaceRecentNotes(text string, db *sql.DB, spacePath string) string {
	if !strings.Contains(text, "{{recent_notes}}") {
		return text
	}

	rows, err := db.Query(`
		SELECT note_path, linked_at, last_referenced
		FROM relevant_notes
		ORDER BY COALESCE(last_referenced, linked_at) DESC
		LIMIT 5
	`)
	if err != nil {
		return strings.ReplaceAll(text, "{{recent_notes}}", "none")
	}
	defer rows.Close()

	var notes []string
	for rows.Next() {
		var notePath string
		var linkedAt int64
		var lastReferenced sql.NullInt64

		if err := rows.Scan(&notePath, &linkedAt, &lastReferenced); err != nil {
			continue
		}

		// Extract filename from path
		filename := filepath.Base(notePath)

		// Format date
		var dateStr string
		if lastReferenced.Valid {
			dateStr = time.Unix(lastReferenced.Int64, 0).Format("Jan 2")
		} else {
			dateStr = time.Unix(linkedAt, 0).Format("Jan 2")
		}

		notes = append(notes, fmt.Sprintf("- %s (%s)", filename, dateStr))
	}

	if len(notes) == 0 {
		return strings.ReplaceAll(text, "{{recent_notes}}", "none")
	}

	return strings.ReplaceAll(text, "{{recent_notes}}", strings.Join(notes, "\n"))
}

// replaceNotesTagged replaces {{notes_tagged:TAG}} patterns with counts
func (s *ContextService) replaceNotesTagged(text string, db *sql.DB) string {
	// Find all {{notes_tagged:TAG}} patterns
	re := regexp.MustCompile(`\{\{notes_tagged:([^}]+)\}\}`)
	matches := re.FindAllStringSubmatch(text, -1)

	for _, match := range matches {
		fullMatch := match[0]
		tag := match[1]

		// Count notes with this tag
		var count int
		err := db.QueryRow(`
			SELECT COUNT(*) FROM relevant_notes
			WHERE tags LIKE ?
		`, "%\""+tag+"\"%").Scan(&count)

		if err != nil {
			text = strings.ReplaceAll(text, fullMatch, "0")
		} else {
			text = strings.ReplaceAll(text, fullMatch, fmt.Sprintf("%d", count))
		}
	}

	return text
}
