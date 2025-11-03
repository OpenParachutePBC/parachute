package integration

import (
	"encoding/json"
	"log"
	"os"
	"testing"
	"time"

	"github.com/unforced/parachute-backend/internal/acp"
)

// TestACPConnection tests that we can connect to ACP and get version info
func TestACPConnection(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	// Use OAuth credentials (no API key needed)
	client, err := acp.NewACPClient("")
	if err != nil {
		t.Fatalf("Failed to create ACP client: %v", err)
	}
	defer client.Close()

	// Give it a moment to initialize
	time.Sleep(100 * time.Millisecond)

	log.Printf("✅ Successfully connected to ACP")
}

// TestACPSessionCreation tests creating a new session
func TestACPSessionCreation(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	client, err := acp.NewACPClient("")
	if err != nil {
		t.Fatalf("Failed to create ACP client: %v", err)
	}
	defer client.Close()

	// Create a new session
	sessionID, err := client.NewSession("/tmp", nil)
	if err != nil {
		t.Fatalf("Failed to create session: %v", err)
	}

	if sessionID == "" {
		t.Error("Expected non-empty session ID")
	}

	log.Printf("✅ Created session: %s", sessionID)
}

// TestACPSimplePrompt tests sending a simple prompt that doesn't require tools
func TestACPSimplePrompt(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	client, err := acp.NewACPClient("")
	if err != nil {
		t.Fatalf("Failed to create ACP client: %v", err)
	}
	defer client.Close()

	sessionID, err := client.NewSession("/tmp", nil)
	if err != nil {
		t.Fatalf("Failed to create session: %v", err)
	}

	// Listen for notifications in a goroutine
	messageReceived := false
	done := make(chan bool, 1)

	go func() {
		timeout := time.After(30 * time.Second)
		for {
			select {
			case notif := <-client.Notifications():
				log.Printf("📨 Received notification: %s", notif.Method)
				if notif.Method == "session/agent_message_chunk" {
					var params map[string]interface{}
					if err := json.Unmarshal(notif.Params, &params); err == nil {
						if chunk, ok := params["chunk"].(string); ok && chunk != "" {
							log.Printf("📝 Chunk: %s", chunk)
							messageReceived = true
						}
					}
				}
			case <-timeout:
				done <- messageReceived
				return
			}
		}
	}()

	// Send a simple prompt
	prompt := "Say 'Hello, test!' and nothing else."
	log.Printf("📤 Sending prompt: %s", prompt)

	if err := client.SessionPrompt(sessionID, prompt); err != nil {
		t.Fatalf("Failed to send prompt: %v", err)
	}

	log.Printf("✅ Prompt sent, waiting for response...")

	// Wait for response
	received := <-done
	if !received {
		t.Error("Did not receive any message chunks")
	} else {
		log.Printf("✅ Successfully received response chunks")
	}
}

// TestACPToolCallWithPermission tests a prompt that triggers tool calls
func TestACPToolCallWithPermission(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	client, err := acp.NewACPClient("")
	if err != nil {
		t.Fatalf("Failed to create ACP client: %v", err)
	}
	defer client.Close()

	sessionID, err := client.NewSession("/tmp", nil)
	if err != nil {
		t.Fatalf("Failed to create session: %v", err)
	}

	// Track what we receive
	receivedToolCall := false
	receivedPermissionRequest := false
	receivedToolUpdate := false
	toolCallSuccess := false

	done := make(chan bool, 1)

	go func() {
		timeout := time.After(60 * time.Second)
		for {
			select {
			case notif := <-client.Notifications():
				log.Printf("📨 Notification: %s", notif.Method)

				if notif.Method == "session/tool_call" {
					receivedToolCall = true
					log.Printf("🔧 Tool call notification received")
				}

				if notif.Method == "session/tool_call_update" {
					receivedToolUpdate = true
					var params map[string]interface{}
					if err := json.Unmarshal(notif.Params, &params); err == nil {
						if status, ok := params["status"].(string); ok {
							log.Printf("🔧 Tool update status: %s", status)
							if status == "succeeded" {
								toolCallSuccess = true
							} else if status == "failed" {
								if content, ok := params["content"].([]interface{}); ok {
									log.Printf("❌ Tool failed: %v", content)
								}
							}
						}
					}
				}

			case req := <-client.Requests():
				if req.ID == nil {
					log.Printf("⚠️  Request has no ID: %s", req.Method)
					continue
				}
				log.Printf("📨 Request: %s (ID=%d)", req.Method, *req.ID)

				if req.Method == "session/request_permission" {
					receivedPermissionRequest = true
					log.Printf("🔐 Permission request received")

					permReq, err := acp.ParsePermissionRequest(req)
					if err != nil {
						log.Printf("❌ Failed to parse permission request: %v", err)
						continue
					}

					log.Printf("📋 Tool Call ID: %s", permReq.ToolCall.ToolCallID)
					log.Printf("📋 Raw Input: %v", permReq.ToolCall.RawInput)
					log.Printf("📋 Options: %v", permReq.Options)

					// Auto-approve if safe
					if acp.ShouldAutoApprove(permReq.ToolCall) {
						log.Printf("✅ Auto-approving safe operation")
						allowOpt := acp.FindAllowOption(permReq.Options)
						if allowOpt != nil {
							response := acp.PermissionResponse{
								Outcome: acp.PermissionOutcome{
									Outcome:  "selected",
									OptionID: allowOpt.OptionID,
								},
							}
							if err := client.SendResponse(*req.ID, response); err != nil {
								log.Printf("❌ Failed to send response: %v", err)
							} else {
								log.Printf("✅ Sent approval response")
							}
						}
					} else {
						log.Printf("🚫 Operation requires manual approval, rejecting")
					}
				}

			case <-timeout:
				done <- true
				return
			}
		}
	}()

	// Send a prompt that will trigger a web search
	prompt := "What is the current weather in San Francisco? Use web search to find out."
	log.Printf("📤 Sending prompt: %s", prompt)

	if err := client.SessionPrompt(sessionID, prompt); err != nil {
		t.Fatalf("Failed to send prompt: %v", err)
	}

	log.Printf("✅ Prompt sent, waiting for tool calls and permissions...")

	// Wait for completion
	<-done

	// Check results
	log.Printf("\n📊 Test Results:")
	log.Printf("  Tool call received: %v", receivedToolCall)
	log.Printf("  Permission request received: %v", receivedPermissionRequest)
	log.Printf("  Tool update received: %v", receivedToolUpdate)
	log.Printf("  Tool execution succeeded: %v", toolCallSuccess)

	if !receivedToolCall {
		t.Error("Expected to receive tool_call notification")
	}

	if !receivedPermissionRequest {
		t.Error("Expected to receive permission request")
	}

	if !receivedToolUpdate {
		t.Error("Expected to receive tool_call_update notification")
	}

	if !toolCallSuccess {
		t.Error("Expected tool execution to succeed after auto-approval")
	}
}

// TestACPMultipleMessages tests sending multiple messages in the same session
func TestACPMultipleMessages(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	client, err := acp.NewACPClient("")
	if err != nil {
		t.Fatalf("Failed to create ACP client: %v", err)
	}
	defer client.Close()

	sessionID, err := client.NewSession("/tmp", nil)
	if err != nil {
		t.Fatalf("Failed to create session: %v", err)
	}

	// Helper to send a message and wait for response
	sendAndWait := func(prompt string) bool {
		received := false
		done := make(chan bool, 1)

		go func() {
			timeout := time.After(20 * time.Second)
			for {
				select {
				case notif := <-client.Notifications():
					if notif.Method == "session/agent_message_chunk" {
						received = true
					}
				case <-client.Requests():
					// Ignore permission requests for this test
				case <-timeout:
					done <- received
					return
				}
			}
		}()

		if err := client.SessionPrompt(sessionID, prompt); err != nil {
			log.Printf("❌ Failed to send prompt: %v", err)
			return false
		}

		time.Sleep(2 * time.Second) // Give it time to respond
		return received
	}

	// Send multiple messages
	prompts := []string{
		"Say 'First message'",
		"Say 'Second message'",
		"Say 'Third message'",
	}

	for i, prompt := range prompts {
		log.Printf("📤 Message %d: %s", i+1, prompt)
		if !sendAndWait(prompt) {
			t.Errorf("Did not receive response for message %d", i+1)
		} else {
			log.Printf("✅ Received response for message %d", i+1)
		}
	}
}

// TestMain sets up logging for integration tests
func TestMain(m *testing.M) {
	log.SetFlags(log.Ltime | log.Lmicroseconds)
	log.SetPrefix("[TEST] ")

	code := m.Run()
	os.Exit(code)
}
