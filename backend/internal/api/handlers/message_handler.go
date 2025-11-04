package handlers

import (
	"context"
	"fmt"
	"log"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/gofiber/fiber/v3"
	"github.com/unforced/parachute-backend/internal/acp"
	"github.com/unforced/parachute-backend/internal/domain/conversation"
	"github.com/unforced/parachute-backend/internal/domain/space"
)

// MessageHandler handles message-related HTTP requests
type MessageHandler struct {
	conversationService *conversation.Service
	spaceService        *space.Service
	contextService      *space.ContextService
	acpClient           *acp.ACPClient
	wsHandler           *WebSocketHandler
	// Session management: one ACP session per Conversation
	// Map: ConversationID -> SessionID
	conversationSessions map[string]string
	// Track if we've started a listener for this conversation
	activeListeners map[string]bool
	// Completion signals: Map SessionID -> channel to signal prompt completion
	completionSignals map[string]chan bool
	sessionMu         sync.RWMutex
}

// NewMessageHandler creates a new message handler
func NewMessageHandler(
	conversationService *conversation.Service,
	spaceService *space.Service,
	contextService *space.ContextService,
	acpClient *acp.ACPClient,
	wsHandler *WebSocketHandler,
) *MessageHandler {
	return &MessageHandler{
		conversationService:  conversationService,
		spaceService:         spaceService,
		contextService:       contextService,
		acpClient:            acpClient,
		wsHandler:            wsHandler,
		conversationSessions: make(map[string]string),
		activeListeners:      make(map[string]bool),
		completionSignals:    make(map[string]chan bool),
	}
}

// SendMessageRequest represents a request to send a message
type SendMessageRequest struct {
	ConversationID string `json:"conversation_id"`
	Content        string `json:"content"`
}

// SendMessage handles POST /api/messages
// This creates a user message and sends it to ACP
func (h *MessageHandler) SendMessage(c fiber.Ctx) error {
	// Note: SendMessage can take a while with ACP, so use longer timeout
	ctx, cancel := context.WithTimeout(c.Context(), 60*time.Second)
	defer cancel()

	// Parse request
	var req SendMessageRequest
	if err := c.Bind().JSON(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	if req.ConversationID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "conversation_id is required",
		})
	}

	if req.Content == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "content is required",
		})
	}

	// Get conversation
	conv, err := h.conversationService.GetConversation(ctx, req.ConversationID)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Conversation not found",
		})
	}

	// Get space
	spaceObj, err := h.spaceService.GetByID(ctx, conv.SpaceID)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Space not found",
		})
	}

	// Get conversation history BEFORE creating the new message
	messages, err := h.conversationService.ListMessages(ctx, req.ConversationID)
	if err != nil {
		log.Printf("Failed to get message history: %v", err)
		messages = []*conversation.Message{} // Continue with empty history
	}

	// Check if this is the first user message
	isFirstMessage := len(messages) == 0

	// Create user message
	userMessage, err := h.conversationService.CreateMessage(ctx, conversation.CreateMessageParams{
		ConversationID: req.ConversationID,
		Role:           "user",
		Content:        req.Content,
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to create message",
		})
	}

	// Auto-update conversation title from first message
	if isFirstMessage && conv.Title == "New Conversation" {
		title := h.generateConversationTitle(req.Content)

		// Update the conversation title
		_, err = h.conversationService.UpdateConversation(ctx, req.ConversationID, title)
		if err != nil {
			log.Printf("Failed to auto-update conversation title: %v", err)
			// Don't fail the request if title update fails
		}
	}

	// Build prompt with context and send to ACP if available
	if h.acpClient != nil {
		prompt := h.buildPromptWithContext(spaceObj, messages, req.Content)

		// Use vault root as working directory to avoid SDK double-loading CLAUDE.md
		// SDK has settingSources: ["user", "project", "local"] enabled by default,
		// which would read CLAUDE.md from spaceObj.Path. Since we manually prepend
		// CLAUDE.md with variable resolution, we set cwd to vault root where no
		// CLAUDE.md exists, preventing duplication.
		vaultRoot := filepath.Dir(filepath.Dir(spaceObj.Path)) // Go up from spaces/space-name to ~/Parachute

		// Get or create ACP session for this conversation
		sessionID, isNew, err := h.getOrCreateSession(req.ConversationID, vaultRoot)
		if err != nil {
			log.Printf("❌ Failed to get/create ACP session: %v", err)
			// Continue without ACP
		} else {
			// Start persistent listener only for new sessions
			if isNew {
				go h.startSessionListener(sessionID, req.ConversationID)
			}

			// Send prompt to ACP (non-blocking)
			go h.sendPrompt(sessionID, prompt)
		}
	}

	// Return user message immediately
	return c.Status(fiber.StatusCreated).JSON(userMessage)
}

// getOrCreateSession gets an existing ACP session for a conversation or creates a new one
// Returns: (sessionID, isNewSession, error)
func (h *MessageHandler) getOrCreateSession(conversationID, workingDir string) (string, bool, error) {
	// Lock for the entire operation to prevent race conditions
	h.sessionMu.Lock()
	defer h.sessionMu.Unlock()

	// Check if we already have a session for this conversation
	sessionID, exists := h.conversationSessions[conversationID]
	if exists {
		log.Printf("♻️  Reusing existing session %s for conversation %s", sessionID[:8], conversationID[:8])
		return sessionID, false, nil
	}

	// Create new session while holding the lock
	log.Printf("🆕 Creating new ACP session for conversation %s", conversationID[:8])
	sessionID, err := h.acpClient.NewSession(workingDir, nil)
	if err != nil {
		return "", false, fmt.Errorf("failed to create session: %w", err)
	}

	// Cache the session (still holding lock)
	h.conversationSessions[conversationID] = sessionID

	log.Printf("✅ Created and cached session %s for conversation %s", sessionID[:8], conversationID[:8])
	return sessionID, true, nil
}

// sendPrompt sends a prompt to an ACP session and signals completion
func (h *MessageHandler) sendPrompt(sessionID, prompt string) {
	log.Printf("🤖 Sending prompt to ACP session %s", sessionID[:8])
	if err := h.acpClient.SessionPrompt(sessionID, prompt); err != nil {
		log.Printf("❌ Failed to send prompt to ACP: %v", err)
		return
	}
	log.Printf("✅ Prompt sent to ACP (session/prompt returned)")

	// Signal completion so the listener can save the accumulated message
	h.sessionMu.RLock()
	if completionChan, ok := h.completionSignals[sessionID]; ok {
		select {
		case completionChan <- true:
			log.Printf("📣 Signaled completion for session %s", sessionID[:8])
		default:
			log.Printf("⚠️  Completion channel full for session %s", sessionID[:8])
		}
	}
	h.sessionMu.RUnlock()
}

// startSessionListener starts a persistent listener for a session
// This runs for the lifetime of the conversation, handling all messages
func (h *MessageHandler) startSessionListener(sessionID, conversationID string) {
	ctx := context.Background()
	log.Printf("🎧 Starting persistent listener for session %s (conversation %s)", sessionID[:8], conversationID[:8])

	// Register this session to receive its own requests and notifications
	sessionRequests, sessionNotifications := h.acpClient.RegisterSession(sessionID)

	// Ensure cleanup when listener exits
	defer func() {
		h.acpClient.UnregisterSession(sessionID)
		log.Printf("🛑 Session listener stopped for %s", sessionID[:8])
	}()

	// Create completion signal channel
	completionChan := make(chan bool, 10)
	h.sessionMu.Lock()
	h.completionSignals[sessionID] = completionChan
	h.sessionMu.Unlock()

	// Track current response being built
	var currentResponse string

	for {
		select {
		case req := <-sessionRequests:
			// Handle incoming JSON-RPC requests from ACP
			if req.Method == "session/request_permission" {
				if req.ID == nil {
					log.Printf("⚠️  Permission request has no ID, skipping")
					continue
				}
				log.Printf("🔐 [%s] Received permission request (ID=%d)", sessionID[:8], *req.ID)

				permReq, err := acp.ParsePermissionRequest(req)
				if err != nil {
					log.Printf("❌ Failed to parse permission request: %v", err)
					continue
				}

				// Log the full request for debugging
				log.Printf("📋 Permission request - ToolCallID: %s, Options: %v",
					permReq.ToolCall.ToolCallID, permReq.Options)

				// Auto-approve safe operations
				if acp.ShouldAutoApprove(permReq.ToolCall) {
					allowOpt := acp.FindAllowOption(permReq.Options)
					if allowOpt != nil {
						log.Printf("✅ Auto-approving with option: %s", allowOpt.OptionID)
						response := acp.PermissionResponse{
							Outcome: acp.PermissionOutcome{
								Outcome:  "selected",
								OptionID: allowOpt.OptionID,
							},
						}
						if err := h.acpClient.SendResponse(*req.ID, response); err != nil {
							log.Printf("❌ Failed to send permission response: %v", err)
						}
					} else {
						log.Printf("⚠️  No allow option found in permission request")
					}
				} else {
					// TODO: For now, reject operations that need manual approval
					// In the future, this will show a UI dialog
					log.Printf("🚫 Rejecting operation that requires manual approval")
					rejectOpt := acp.PermissionOption{}
					for _, opt := range permReq.Options {
						if opt.OptionID == "reject" || opt.OptionID == "reject_once" {
							rejectOpt = opt
							break
						}
					}
					if rejectOpt.OptionID != "" {
						response := acp.PermissionResponse{
							Outcome: acp.PermissionOutcome{
								Outcome:  "selected",
								OptionID: rejectOpt.OptionID,
							},
						}
						if err := h.acpClient.SendResponse(*req.ID, response); err != nil {
							log.Printf("❌ Failed to send rejection response: %v", err)
						}
					}
				}
			}

		case notif := <-sessionNotifications:
			log.Printf("🔔 [%s] Received notification: method=%s", sessionID[:8], notif.Method)

			if notif.Method != "session/update" {
				log.Printf("   Skipping non-session/update notification")
				continue
			}

			update, err := acp.ParseSessionUpdate(notif)
			if err != nil {
				log.Printf("❌ [%s] Failed to parse update: %v", sessionID[:8], err)
				continue
			}

			log.Printf("🔔 [%s] Notification sessionID: %s, my sessionID: %s",
				sessionID[:8], update.SessionID[:8], sessionID[:8])

			// Only process notifications for our session
			if update.SessionID != sessionID {
				log.Printf("   Skipping notification for different session (full IDs: %s vs %s)",
					update.SessionID, sessionID)
				continue
			}

			log.Printf("📝 [%s] Processing update", sessionID[:8])

			// Extract text from update
			if sessionUpdate, ok := update.Update["sessionUpdate"].(string); ok {
				log.Printf("   Session update type: %s", sessionUpdate)

				if sessionUpdate == "agent_message_chunk" {
					// Extract text from content field
					if content, ok := update.Update["content"].(map[string]interface{}); ok {
						if text, ok := content["text"].(string); ok {
							currentResponse += text
							log.Printf("   ✍️  Added text chunk (total: %d chars)", len(currentResponse))

							// Broadcast chunk to WebSocket clients
							if h.wsHandler != nil {
								log.Printf("   📡 Broadcasting chunk to WebSocket clients...")
								h.wsHandler.BroadcastMessageChunk(conversationID, text)
							} else {
								log.Printf("   ⚠️  wsHandler is nil, cannot broadcast")
							}
						}
					}
				} else if sessionUpdate == "tool_call" {
					// Extract tool call info
					log.Printf("   🔧 Tool call initiated")

					// Broadcast tool call to WebSocket clients
					if h.wsHandler != nil {
						toolCallID := ""
						title := ""
						kind := ""
						status := ""

						if id, ok := update.Update["toolCallId"].(string); ok {
							toolCallID = id
						}
						if t, ok := update.Update["title"].(string); ok {
							title = t
						}
						if k, ok := update.Update["kind"].(string); ok {
							kind = k
						}
						if s, ok := update.Update["status"].(string); ok {
							status = s
						}

						log.Printf("   📡 Broadcasting tool call: %s (%s)", title, kind)
						h.wsHandler.BroadcastToolCall(conversationID, toolCallID, title, kind, status)
					}
				} else if sessionUpdate == "tool_call_update" {
					// Tool call completed or updated
					log.Printf("   ✅ Tool call update")

					// Broadcast tool call update to WebSocket clients
					if h.wsHandler != nil {
						toolCallID := ""
						status := ""

						if id, ok := update.Update["toolCallId"].(string); ok {
							toolCallID = id
						}
						if s, ok := update.Update["status"].(string); ok {
							status = s
						}

						log.Printf("   📡 Broadcasting tool call update: %s -> %s", toolCallID, status)
						h.wsHandler.BroadcastToolCallUpdate(conversationID, toolCallID, status)
					}
				}
			}

		case <-completionChan:
			// Prompt completed - save accumulated response
			if currentResponse != "" {
				log.Printf("💾 Saving assistant response (%d chars) to conversation %s", len(currentResponse), conversationID[:8])
				_, err := h.conversationService.CreateMessage(ctx, conversation.CreateMessageParams{
					ConversationID: conversationID,
					Role:           "assistant",
					Content:        currentResponse,
				})
				if err != nil {
					log.Printf("❌ Failed to save assistant message: %v", err)
				} else {
					log.Printf("✅ Assistant message saved successfully")
				}
				// Reset for next message
				currentResponse = ""
			} else {
				log.Printf("⚠️  Received completion signal but no response accumulated")
			}
		}
	}
}

// buildPromptWithContext builds a prompt including conversation history and SPACE.md
func (h *MessageHandler) buildPromptWithContext(
	spaceObj *space.Space,
	messages []*conversation.Message,
	currentPrompt string,
) string {
	prompt := ""

	// Include SPACE.md context if it exists
	spaceMD, err := h.spaceService.ReadSpaceMD(spaceObj)
	if err == nil && spaceMD != "" {
		// Resolve dynamic variables in SPACE.md
		resolvedSpaceMD, err := h.contextService.ResolveVariables(spaceMD, spaceObj.Path)
		if err != nil {
			log.Printf("⚠️  Failed to resolve SPACE.md variables: %v", err)
			resolvedSpaceMD = spaceMD // Fallback to unresolved
		}

		prompt += "# Context from SPACE.md\n\n"
		prompt += resolvedSpaceMD
		prompt += "\n\n---\n\n"
	}

	// Include conversation history (last 10 messages for now)
	if len(messages) > 0 {
		prompt += "# Conversation History\n\n"

		start := 0
		if len(messages) > 10 {
			start = len(messages) - 10
		}

		for _, msg := range messages[start:] {
			if msg.Role == "user" {
				prompt += fmt.Sprintf("User: %s\n\n", msg.Content)
			} else {
				prompt += fmt.Sprintf("Assistant: %s\n\n", msg.Content)
			}
		}

		prompt += "---\n\n"
	}

	// Current prompt
	prompt += currentPrompt

	return prompt
}

// generateConversationTitle creates a smart title from the first message
func (h *MessageHandler) generateConversationTitle(content string) string {
	// Remove leading/trailing whitespace
	content = strings.TrimSpace(content)

	if content == "" {
		return "New Conversation"
	}

	// Split into sentences
	sentences := strings.FieldsFunc(content, func(r rune) bool {
		return r == '.' || r == '!' || r == '?'
	})

	var title string
	if len(sentences) > 0 {
		// Use first sentence
		title = strings.TrimSpace(sentences[0])
	} else {
		// No sentence breaks, use first line
		lines := strings.Split(content, "\n")
		title = strings.TrimSpace(lines[0])
	}

	// Limit length
	maxLen := 60
	if len(title) > maxLen {
		// Try to break at a word boundary
		if idx := strings.LastIndex(title[:maxLen-3], " "); idx > 20 {
			title = title[:idx] + "..."
		} else {
			title = title[:maxLen-3] + "..."
		}
	}

	// Remove common question words at the start if too long
	if len(title) > 45 {
		prefixes := []string{"Can you ", "Could you ", "Please ", "I want to ", "I need to ", "How do I ", "What is ", "Why does "}
		for _, prefix := range prefixes {
			if strings.HasPrefix(title, prefix) {
				title = title[len(prefix):]
				// Capitalize first letter
				if len(title) > 0 {
					title = strings.ToUpper(string(title[0])) + title[1:]
				}
				break
			}
		}
	}

	return title
}

// ListMessages handles GET /api/messages?conversation_id=...
func (h *MessageHandler) ListMessages(c fiber.Ctx) error {
	ctx, cancel := context.WithTimeout(c.Context(), 5*time.Second)
	defer cancel()

	conversationID := c.Query("conversation_id")
	if conversationID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "conversation_id query parameter required",
		})
	}

	messages, err := h.conversationService.ListMessages(ctx, conversationID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to list messages",
		})
	}

	// Ensure we always return an array, never null
	if messages == nil {
		messages = []*conversation.Message{}
	}

	return c.JSON(fiber.Map{
		"messages": messages,
	})
}
