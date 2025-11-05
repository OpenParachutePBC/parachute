package e2e

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"testing"
	"time"
)

const (
	baseURL = "http://localhost:8080"
)

// Helper to make HTTP requests
func makeRequest(method, path string, body interface{}) (*http.Response, []byte, error) {
	var reqBody io.Reader
	if body != nil {
		jsonData, err := json.Marshal(body)
		if err != nil {
			return nil, nil, err
		}
		reqBody = bytes.NewBuffer(jsonData)
	}

	req, err := http.NewRequest(method, baseURL+path, reqBody)
	if err != nil {
		return nil, nil, err
	}

	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, nil, err
	}

	respBody, err := io.ReadAll(resp.Body)
	resp.Body.Close()

	return resp, respBody, err
}

// TestServerHealth checks if the server is running
func TestServerHealth(t *testing.T) {
	resp, body, err := makeRequest("GET", "/health", nil)
	if err != nil {
		t.Fatalf("Health check failed: %v", err)
	}

	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status 200, got %d", resp.StatusCode)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		t.Fatalf("Failed to parse health response: %v", err)
	}

	if status, ok := result["status"].(string); !ok || status != "ok" {
		t.Errorf("Expected ok status, got: %v", result)
	}

	log.Printf("✅ Server is healthy")
}

// TestCreateSpace tests creating a new space
func TestCreateSpace(t *testing.T) {
	// Use unique name to avoid conflicts from previous test runs
	spaceName := fmt.Sprintf("E2E Test Space %d", time.Now().Unix())
	resp, body, err := makeRequest("POST", "/api/spaces", map[string]interface{}{
		"name": spaceName,
	})
	if err != nil {
		t.Fatalf("Failed to create space: %v", err)
	}

	if resp.StatusCode != http.StatusCreated {
		t.Errorf("Expected status 201, got %d. Body: %s", resp.StatusCode, string(body))
		return
	}

	var space map[string]interface{}
	if err := json.Unmarshal(body, &space); err != nil {
		t.Fatalf("Failed to parse response: %v", err)
	}

	spaceID, ok := space["id"].(string)
	if !ok || spaceID == "" {
		t.Errorf("Expected space ID in response, got: %v", space)
		return
	}

	log.Printf("✅ Created space: %s", spaceID)
}

// TestCreateConversationAndSendMessage tests the full flow
func TestCreateConversationAndSendMessage(t *testing.T) {
	// 1. Create a space
	log.Printf("📦 Creating space...")
	spaceName := fmt.Sprintf("E2E Message Test %d", time.Now().Unix())
	resp, body, err := makeRequest("POST", "/api/spaces", map[string]interface{}{
		"name": spaceName,
	})
	if err != nil {
		t.Fatalf("Failed to create space: %v", err)
	}

	var space map[string]interface{}
	if err := json.Unmarshal(body, &space); err != nil {
		t.Fatalf("Failed to parse space response: %v", err)
	}
	spaceID, ok := space["id"].(string)
	if !ok {
		t.Fatalf("Expected space ID in response, got: %v", space)
	}
	log.Printf("✅ Created space: %s", spaceID)

	// 2. Create a conversation
	log.Printf("💬 Creating conversation...")
	resp, body, err = makeRequest("POST", "/api/conversations", map[string]interface{}{
		"space_id": spaceID,
		"title":    "Test Conversation",
	})
	if err != nil {
		t.Fatalf("Failed to create conversation: %v", err)
	}

	var conversation map[string]interface{}
	if err := json.Unmarshal(body, &conversation); err != nil {
		t.Fatalf("Failed to parse conversation response: %v", err)
	}
	conversationID, ok := conversation["id"].(string)
	if !ok {
		t.Fatalf("Expected conversation ID in response, got: %v", conversation)
	}
	log.Printf("✅ Created conversation: %s", conversationID)

	// 3. Send a simple message (no tools)
	log.Printf("📤 Sending simple message...")
	resp, body, err = makeRequest("POST", "/api/messages", map[string]interface{}{
		"conversation_id": conversationID,
		"content":         "Say 'Hello from E2E test!' and nothing else.",
	})
	if err != nil {
		t.Fatalf("Failed to send message: %v", err)
	}

	if resp.StatusCode != http.StatusAccepted {
		t.Errorf("Expected status 202, got %d. Body: %s", resp.StatusCode, string(body))
	}

	log.Printf("✅ Message sent, waiting for response...")

	// 4. Poll for messages
	maxAttempts := 30
	found := false
	for i := 0; i < maxAttempts; i++ {
		time.Sleep(1 * time.Second)

		resp, body, err = makeRequest("GET", fmt.Sprintf("/api/conversations/%s/messages", conversationID), nil)
		if err != nil {
			log.Printf("⚠️  Failed to get messages: %v", err)
			continue
		}

		var msgResult map[string]interface{}
		if err := json.Unmarshal(body, &msgResult); err != nil {
			log.Printf("⚠️  Failed to parse messages: %v", err)
			continue
		}

		messages, ok := msgResult["messages"].([]interface{})
		if !ok {
			log.Printf("⚠️  No messages array in response")
			continue
		}

		log.Printf("📨 Attempt %d: Found %d messages", i+1, len(messages))

		// Look for assistant message
		for _, msg := range messages {
			m := msg.(map[string]interface{})
			if m["role"].(string) == "assistant" {
				content := m["content"].(string)
				log.Printf("✅ Got assistant response: %s", content)
				found = true
				break
			}
		}

		if found {
			break
		}
	}

	if !found {
		t.Error("Did not receive assistant response within timeout")
	}
}

// TestMessageWithToolCall tests sending a message that triggers tool usage
func TestMessageWithToolCall(t *testing.T) {
	// 1. Create a space
	log.Printf("📦 Creating space for tool test...")
	resp, body, err := makeRequest("POST", "/api/spaces", map[string]interface{}{
		"name":        "E2E Tool Test",
		"working_dir": "/tmp/e2e-tool-test",
	})
	if err != nil {
		t.Fatalf("Failed to create space: %v", err)
	}

	var spaceResult map[string]interface{}
	json.Unmarshal(body, &spaceResult)
	space := spaceResult["space"].(map[string]interface{})
	spaceID := space["id"].(string)
	log.Printf("✅ Created space: %s", spaceID)

	// 2. Create a conversation
	log.Printf("💬 Creating conversation...")
	resp, body, err = makeRequest("POST", "/api/conversations", map[string]interface{}{
		"space_id": spaceID,
		"title":    "Tool Test Conversation",
	})
	if err != nil {
		t.Fatalf("Failed to create conversation: %v", err)
	}

	var convResult map[string]interface{}
	json.Unmarshal(body, &convResult)
	conversation := convResult["conversation"].(map[string]interface{})
	conversationID := conversation["id"].(string)
	log.Printf("✅ Created conversation: %s", conversationID)

	// 3. Send a message that requires web search
	log.Printf("📤 Sending message that requires tool usage...")
	resp, body, err = makeRequest("POST", "/api/messages", map[string]interface{}{
		"conversation_id": conversationID,
		"content":         "What is the current weather in Tokyo? Please search for this information.",
	})
	if err != nil {
		t.Fatalf("Failed to send message: %v", err)
	}

	if resp.StatusCode != http.StatusAccepted {
		t.Errorf("Expected status 202, got %d. Body: %s", resp.StatusCode, string(body))
	}

	log.Printf("✅ Message sent, waiting for response with tool usage...")

	// 4. Poll for messages and check for tool usage indicators
	maxAttempts := 60 // Tools take longer
	found := false
	for i := 0; i < maxAttempts; i++ {
		time.Sleep(2 * time.Second)

		resp, body, err = makeRequest("GET", fmt.Sprintf("/api/conversations/%s/messages", conversationID), nil)
		if err != nil {
			log.Printf("⚠️  Failed to get messages: %v", err)
			continue
		}

		var msgResult map[string]interface{}
		if err := json.Unmarshal(body, &msgResult); err != nil {
			log.Printf("⚠️  Failed to parse messages: %v", err)
			continue
		}

		messages, ok := msgResult["messages"].([]interface{})
		if !ok {
			continue
		}

		log.Printf("📨 Attempt %d: Found %d messages", i+1, len(messages))

		// Look for assistant message with substantial content
		for _, msg := range messages {
			m := msg.(map[string]interface{})
			if m["role"].(string) == "assistant" {
				content := m["content"].(string)
				// Tool responses are usually longer
				if len(content) > 50 {
					log.Printf("✅ Got assistant response with tool result (%d chars)", len(content))
					log.Printf("📄 Content preview: %s...", content[:min(100, len(content))])
					found = true
					break
				}
			}
		}

		if found {
			break
		}
	}

	if !found {
		t.Error("Did not receive assistant response with tool usage within timeout")
	}
}

// TestMultipleMessagesInSameConversation tests session persistence
func TestMultipleMessagesInSameConversation(t *testing.T) {
	// 1. Create space and conversation
	_, body, _ := makeRequest("POST", "/api/spaces", map[string]interface{}{
		"name":        "E2E Session Test",
		"working_dir": "/tmp/e2e-session-test",
	})
	var spaceResult map[string]interface{}
	json.Unmarshal(body, &spaceResult)
	spaceID := spaceResult["space"].(map[string]interface{})["id"].(string)

	_, body, _ = makeRequest("POST", "/api/conversations", map[string]interface{}{
		"space_id": spaceID,
		"title":    "Session Test",
	})
	var convResult map[string]interface{}
	json.Unmarshal(body, &convResult)
	conversationID := convResult["conversation"].(map[string]interface{})["id"].(string)

	// 2. Send multiple messages
	messages := []string{
		"My name is Alice.",
		"What is my name?",
	}

	for i, content := range messages {
		log.Printf("📤 Sending message %d: %s", i+1, content)
		makeRequest("POST", "/api/messages", map[string]interface{}{
			"conversation_id": conversationID,
			"content":         content,
		})

		// Wait for response
		time.Sleep(5 * time.Second)
	}

	// 3. Check if the second response mentions "Alice"
	_, body, _ = makeRequest("GET", fmt.Sprintf("/api/conversations/%s/messages", conversationID), nil)
	var msgResult map[string]interface{}
	json.Unmarshal(body, &msgResult)
	messages_list := msgResult["messages"].([]interface{})

	log.Printf("📨 Total messages: %d", len(messages_list))

	// The last message should be the assistant's response to "What is my name?"
	if len(messages_list) >= 4 { // 2 user + 2 assistant
		lastMsg := messages_list[len(messages_list)-1].(map[string]interface{})
		content := lastMsg["content"].(string)

		log.Printf("📄 Last response: %s", content)

		// Check if it remembers the name from previous message
		if !contains(content, "Alice") {
			t.Error("Assistant did not remember the name from previous message (session may not be persisting)")
		} else {
			log.Printf("✅ Session persistence working - remembered name!")
		}
	} else {
		t.Errorf("Expected at least 4 messages, got %d", len(messages_list))
	}
}

// Helper functions
func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && contains(s[1:], substr) || len(substr) <= len(s) && s[:len(substr)] == substr)
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func TestMain(m *testing.M) {
	log.SetFlags(log.Ltime)
	log.SetPrefix("[E2E] ")

	// Check if server is running
	resp, _, err := makeRequest("GET", "/health", nil)
	if err != nil || resp.StatusCode != http.StatusOK {
		log.Fatal("❌ Server is not running on " + baseURL + ". Start it first with: ./bin/server")
	}

	log.Printf("✅ Server is running, starting E2E tests...\n")

	code := m.Run()
	os.Exit(code)
}
