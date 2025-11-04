package acp

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sync"

	"github.com/unforced/parachute-backend/internal/acp/prompts"
)

// ACPClient provides high-level ACP protocol methods
type ACPClient struct {
	jsonrpc *JSONRPCClient
	process *ACPProcess

	// Per-session request routing
	sessionRequests map[string]chan *JSONRPCIncomingRequest

	// Notification broadcasting - all listeners get all notifications
	sessionNotifications map[string]chan *JSONRPCNotification
	mu                   sync.RWMutex
}

// NewACPClient creates a new ACP client with the given API key
// If apiKey is empty, the ACP SDK will use OAuth credentials from the system
func NewACPClient(apiKey string) (*ACPClient, error) {
	// Spawn ACP process (apiKey can be empty to use OAuth credentials)
	process, err := SpawnACP(apiKey)
	if err != nil {
		return nil, fmt.Errorf("failed to spawn ACP: %w", err)
	}

	// Create JSON-RPC client
	jsonrpc := NewJSONRPCClient(process)

	client := &ACPClient{
		jsonrpc:              jsonrpc,
		process:              process,
		sessionRequests:      make(map[string]chan *JSONRPCIncomingRequest),
		sessionNotifications: make(map[string]chan *JSONRPCNotification),
	}

	// Start request router and notification broadcaster
	go client.routeRequests()
	go client.broadcastNotifications()

	return client, nil
}

// Close shuts down the ACP client
func (c *ACPClient) Close() error {
	return c.process.Close()
}

// Kill forcefully terminates the ACP process
func (c *ACPClient) Kill() error {
	return c.process.Kill()
}

// Notifications returns a channel that receives ACP notifications
func (c *ACPClient) Notifications() <-chan *JSONRPCNotification {
	return c.jsonrpc.Notifications()
}

// Requests returns a channel that receives incoming JSON-RPC requests from ACP
// DEPRECATED: Use RegisterSession() instead for per-session routing
func (c *ACPClient) Requests() <-chan *JSONRPCIncomingRequest {
	return c.jsonrpc.Requests()
}

// RegisterSession creates dedicated channels for a session
// Returns (requestChan, notificationChan)
func (c *ACPClient) RegisterSession(sessionID string) (<-chan *JSONRPCIncomingRequest, <-chan *JSONRPCNotification) {
	c.mu.Lock()
	defer c.mu.Unlock()

	// Create buffered channels for this session
	reqChan := make(chan *JSONRPCIncomingRequest, 100)
	notifChan := make(chan *JSONRPCNotification, 100)

	c.sessionRequests[sessionID] = reqChan
	c.sessionNotifications[sessionID] = notifChan

	log.Printf("📝 Registered channels for session %s", sessionID[:8])
	return reqChan, notifChan
}

// UnregisterSession removes the channels for a session
func (c *ACPClient) UnregisterSession(sessionID string) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if ch, exists := c.sessionRequests[sessionID]; exists {
		close(ch)
		delete(c.sessionRequests, sessionID)
	}

	if ch, exists := c.sessionNotifications[sessionID]; exists {
		close(ch)
		delete(c.sessionNotifications, sessionID)
	}

	log.Printf("📝 Unregistered channels for session %s", sessionID[:8])
}

// routeRequests routes incoming requests to the appropriate session channel
func (c *ACPClient) routeRequests() {
	log.Printf("🔀 Request router started")
	for req := range c.jsonrpc.Requests() {
		// Parse sessionId from params
		var params struct {
			SessionID string `json:"sessionId"`
		}

		if err := json.Unmarshal(req.Params, &params); err != nil {
			log.Printf("⚠️  Failed to parse sessionId from request: %v", err)
			continue
		}

		log.Printf("🔀 Routing request for session %s", params.SessionID[:8])

		// Route to appropriate session
		c.mu.RLock()
		if ch, ok := c.sessionRequests[params.SessionID]; ok {
			select {
			case ch <- req:
				log.Printf("✅ Routed request to session %s", params.SessionID[:8])
			default:
				log.Printf("⚠️  Request channel full for session %s, dropping request", params.SessionID[:8])
			}
		} else {
			log.Printf("⚠️  No registered channel for session %s, request dropped", params.SessionID[:8])
		}
		c.mu.RUnlock()
	}
	log.Printf("🔀 Request router stopped")
}

// broadcastNotifications broadcasts notifications to all registered session listeners
func (c *ACPClient) broadcastNotifications() {
	log.Printf("📢 Notification broadcaster started")
	for notif := range c.jsonrpc.Notifications() {
		// Broadcast to all registered sessions
		c.mu.RLock()
		sessionCount := len(c.sessionNotifications)

		log.Printf("📢 Broadcasting notification to %d session(s)", sessionCount)

		if sessionCount == 0 {
			c.mu.RUnlock()
			continue
		}

		// Send to each session's notification channel
		sentCount := 0
		for sessionID, ch := range c.sessionNotifications {
			select {
			case ch <- notif:
				sentCount++
				log.Printf("📢 Sent notification to session %s", sessionID[:8])
			default:
				log.Printf("⚠️  Notification channel full for session %s, dropping notification", sessionID[:8])
			}
		}
		log.Printf("📢 Broadcast complete: sent to %d/%d sessions", sentCount, sessionCount)
		c.mu.RUnlock()
	}
	log.Printf("📢 Notification broadcaster stopped")
}

// SendResponse sends a JSON-RPC response back to ACP
func (c *ACPClient) SendResponse(id int, result interface{}) error {
	return c.jsonrpc.SendResponse(id, result)
}

// InitializeParams represents parameters for the initialize method
type InitializeParams struct {
	ProtocolVersion int    `json:"protocolVersion"`
	ClientName      string `json:"client_name,omitempty"`
	ClientVersion   string `json:"client_version,omitempty"`
}

// InitializeResult represents the result of initialize
type InitializeResult struct {
	ServerName    string `json:"server_name"`
	ServerVersion string `json:"server_version"`
}

// Initialize performs the ACP handshake
func (c *ACPClient) Initialize() (*InitializeResult, error) {
	params := InitializeParams{
		ProtocolVersion: 1, // ACP protocol version
		ClientName:      "Parachute",
		ClientVersion:   "0.1.0",
	}

	result, err := c.jsonrpc.Call("initialize", params)
	if err != nil {
		return nil, fmt.Errorf("initialize failed: %w", err)
	}

	var initResult InitializeResult
	if err := json.Unmarshal(result, &initResult); err != nil {
		return nil, fmt.Errorf("failed to parse initialize result: %w", err)
	}

	return &initResult, nil
}

// MCPServer represents an MCP server configuration
type MCPServer struct {
	Name    string                 `json:"name"`
	Command string                 `json:"command"`
	Args    []string               `json:"args,omitempty"`
	Env     map[string]string      `json:"env,omitempty"`
	Config  map[string]interface{} `json:"config,omitempty"`
}

// NewSessionParams represents parameters for session/new
type NewSessionParams struct {
	Cwd        string       `json:"cwd"`
	McpServers []MCPServer  `json:"mcpServers"`      // Required field, send empty array if no servers
	Meta       *SessionMeta `json:"_meta,omitempty"` // Optional metadata including system prompt
}

// SessionMeta represents optional metadata for session configuration
type SessionMeta struct {
	// SystemPrompt can be a string (replaces default) or a map with "append" key
	// String: Complete replacement of default Claude Code prompt
	// Map: { "append": "text" } appends to default prompt
	SystemPrompt interface{} `json:"systemPrompt,omitempty"`
}

// NewSessionResult represents the result of session/new
type NewSessionResult struct {
	SessionID string `json:"sessionId"`
}

// NewSession creates a new ACP session with Parachute's custom system prompt
func (c *ACPClient) NewSession(workingDir string, mcpServers []MCPServer) (string, error) {
	// Ensure mcpServers is always an array (empty if nil)
	if mcpServers == nil {
		mcpServers = []MCPServer{}
	}

	// Build multi-layer system prompt (base + PARACHUTE.md if exists)
	systemPrompt := c.buildSystemPrompt(workingDir)

	params := NewSessionParams{
		Cwd:        workingDir,
		McpServers: mcpServers,
		Meta: &SessionMeta{
			SystemPrompt: systemPrompt,
		},
	}

	result, err := c.jsonrpc.Call("session/new", params)
	if err != nil {
		return "", fmt.Errorf("session/new failed: %w", err)
	}

	var sessionResult NewSessionResult
	if err := json.Unmarshal(result, &sessionResult); err != nil {
		return "", fmt.Errorf("failed to parse session/new result: %w", err)
	}

	log.Printf("🎯 Created ACP session with Parachute system prompt (vault: %s)", workingDir)
	return sessionResult.SessionID, nil
}

// buildSystemPrompt constructs the multi-layer system prompt for ACP sessions
// Combines base Parachute prompt with optional user customization from PARACHUTE.md
func (c *ACPClient) buildSystemPrompt(vaultRoot string) interface{} {
	// Start with base Parachute prompt
	basePrompt := prompts.BaseParachutePrompt

	// Try to load user's PARACHUTE.md from vault root
	parachuteMDPath := filepath.Join(vaultRoot, "PARACHUTE.md")
	userCustomization, err := os.ReadFile(parachuteMDPath)

	if err == nil && len(userCustomization) > 0 {
		// User has customization - append to base prompt
		// Return as map to preserve Claude Code's base capabilities
		return map[string]interface{}{
			"append": basePrompt + "\n\n---\n\n# User Customization\n\n" + string(userCustomization),
		}
	}

	// No user customization - return base prompt only
	// This replaces Claude Code's default prompt entirely
	return basePrompt
}

// ContentBlock represents a block of content in a prompt
type ContentBlock struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

// SessionPromptParams represents parameters for session/prompt
type SessionPromptParams struct {
	SessionID string         `json:"sessionId"`
	Prompt    []ContentBlock `json:"prompt"`
}

// SessionPrompt sends a prompt to an ACP session
// This method returns immediately - responses come via Notifications()
func (c *ACPClient) SessionPrompt(sessionID, prompt string) error {
	params := SessionPromptParams{
		SessionID: sessionID,
		Prompt: []ContentBlock{
			{
				Type: "text",
				Text: prompt,
			},
		},
	}

	fmt.Printf("🔵 Calling session/prompt for session %s\n", sessionID)
	result, err := c.jsonrpc.Call("session/prompt", params)
	if err != nil {
		fmt.Printf("❌ session/prompt failed: %v\n", err)
		return fmt.Errorf("session/prompt failed: %w", err)
	}

	fmt.Printf("✅ session/prompt returned: %s\n", string(result))
	return nil
}

// SessionUpdate represents a session/update notification
type SessionUpdate struct {
	SessionID string                 `json:"sessionId"` // camelCase, not snake_case!
	Update    map[string]interface{} `json:"update"`
}

// ParseSessionUpdate parses a session/update notification
func ParseSessionUpdate(notif *JSONRPCNotification) (*SessionUpdate, error) {
	if notif.Method != "session/update" {
		return nil, fmt.Errorf("not a session/update notification: %s", notif.Method)
	}

	var update SessionUpdate
	if err := json.Unmarshal(notif.Params, &update); err != nil {
		return nil, fmt.Errorf("failed to parse session/update: %w", err)
	}

	return &update, nil
}
