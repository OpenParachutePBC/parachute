package acp

import (
	"encoding/json"
	"fmt"
	"log"
)

// PermissionRequest represents a session/request_permission request
type PermissionRequest struct {
	SessionID string             `json:"sessionId"`
	ToolCall  ToolCallInfo       `json:"toolCall"`
	Options   []PermissionOption `json:"options"`
}

// ToolCallInfo contains information about the tool being called
type ToolCallInfo struct {
	ToolCallID string                 `json:"toolCallId"`
	RawInput   map[string]interface{} `json:"rawInput"`
}

// PermissionOption represents an available permission choice
type PermissionOption struct {
	OptionID string `json:"optionId"` // e.g., "allow", "allow_always", "reject"
	Name     string `json:"name"`
	Kind     string `json:"kind"`
}

// PermissionResponse is what we send back to ACP
// The response must match the ACP RequestPermissionResponse schema
type PermissionResponse struct {
	Outcome PermissionOutcome `json:"outcome"`
}

// PermissionOutcome represents the user's decision
type PermissionOutcome struct {
	Outcome  string `json:"outcome"`  // "selected" or "cancelled"
	OptionID string `json:"optionId"` // The option that was selected (only for "selected")
}

// ParsePermissionRequest parses a session/request_permission request
func ParsePermissionRequest(req *JSONRPCIncomingRequest) (*PermissionRequest, error) {
	if req.Method != "session/request_permission" {
		return nil, fmt.Errorf("not a permission request: %s", req.Method)
	}

	var permReq PermissionRequest
	if err := json.Unmarshal(req.Params, &permReq); err != nil {
		return nil, fmt.Errorf("failed to parse permission request: %w", err)
	}

	return &permReq, nil
}

// ShouldAutoApprove determines if a tool call should be automatically approved
// Currently auto-approves safe read-only operations
func ShouldAutoApprove(toolCall ToolCallInfo) bool {
	// Check if it's a web search operation (has "query" field)
	if _, hasQuery := toolCall.RawInput["query"]; hasQuery {
		log.Printf("🟢 Auto-approving web search operation")
		return true
	}

	// Check if it's a web fetch operation (has "url" field)
	if _, hasURL := toolCall.RawInput["url"]; hasURL {
		log.Printf("🟢 Auto-approving web fetch operation")
		return true
	}

	// Check for file read operations (has "file_path" or "path" field)
	if _, hasFilePath := toolCall.RawInput["file_path"]; hasFilePath {
		// Auto-approve if it's a read operation or no operation specified (read is default)
		if operation, ok := toolCall.RawInput["operation"].(string); ok {
			if operation == "read" {
				log.Printf("🟢 Auto-approving file read operation")
				return true
			}
		} else {
			// No operation field means it's a read
			log.Printf("🟢 Auto-approving file read operation (implicit)")
			return true
		}
	}

	// Check for other read-only file operations
	if operation, ok := toolCall.RawInput["operation"].(string); ok {
		switch operation {
		case "read":
			// Handle read operation with "path" field
			if _, hasPath := toolCall.RawInput["path"]; hasPath {
				log.Printf("🟢 Auto-approving file read operation")
				return true
			}
		case "glob", "grep", "list":
			log.Printf("🟢 Auto-approving read-only file operation: %s", operation)
			return true
		}
	}

	// Check for safe bash commands
	if command, ok := toolCall.RawInput["command"].(string); ok {
		// List of safe read-only commands
		safeCommands := []string{"ls", "cat", "grep", "git status", "pwd", "whoami", "echo", "date"}
		for _, safe := range safeCommands {
			if command == safe || len(command) > len(safe) && command[:len(safe)+1] == safe+" " {
				log.Printf("🟢 Auto-approving safe bash command: %s", command)
				return true
			}
		}
	}

	log.Printf("🟡 Tool requires manual approval: %+v", toolCall.RawInput)
	return false
}

// FindAllowOption finds the "allow" or "allow_once" option from the list
func FindAllowOption(options []PermissionOption) *PermissionOption {
	// Prefer "allow" over "allow_once" over "allow_always"
	for _, opt := range options {
		if opt.OptionID == "allow" {
			return &opt
		}
	}
	for _, opt := range options {
		if opt.OptionID == "allow_once" {
			return &opt
		}
	}
	for _, opt := range options {
		if opt.OptionID == "allow_always" {
			return &opt
		}
	}
	return nil
}
