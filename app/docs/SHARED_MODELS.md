# Shared Data Models Specification

**Data model contracts between parachute-app (Flutter) and parachute-agent (Node.js)**

This document defines the shared data structures used for communication between the Flutter app and the agent backend. Both implementations must conform to these specifications.

---

## Recording

A voice recording with transcription.

```typescript
interface Recording {
  // Identity
  id: string;                    // Timestamp-based ID: "2025-12-12_14-30-22"

  // Content
  title: string;                 // User-editable or AI-generated title
  transcript: string;            // Full transcription text
  context?: string;              // User-provided context/notes
  summary?: string;              // AI-generated summary

  // File references
  filePath: string;              // Path to markdown file (relative to vault)
  audioPath?: string;            // Path to audio file (.opus or .wav)

  // Metadata
  timestamp: string;             // ISO 8601 datetime
  durationSeconds: number;       // Recording duration
  fileSizeKB: number;            // File size in KB

  // Source info
  source: "phone" | "omiDevice"; // Recording source
  deviceId?: string;             // Omi device ID (if source is omiDevice)

  // Processing status
  transcriptionStatus: ProcessingStatus;
  titleGenerationStatus: ProcessingStatus;
  summaryStatus: ProcessingStatus;

  // Tags
  tags: string[];
}

type ProcessingStatus = "pending" | "processing" | "completed" | "failed";
```

### Markdown Format

Recordings are stored as markdown files with YAML frontmatter:

```markdown
---
title: "Meeting with team"
duration: 1847
source: phone
transcription_status: completed
context: "Weekly standup meeting"
summary: "Discussed project timeline..."
tags:
  - work
  - meetings
---

The actual transcript content goes here...
```

---

## Agent

An AI agent definition.

```typescript
interface Agent {
  // Identity
  name: string;                  // Display name
  path: string;                  // File path: "agents/my-agent.md"
  description?: string;          // What this agent does

  // Configuration
  type: "chatbot" | "doc" | "standalone";
  model?: string;                // Claude model to use

  // Capabilities
  tools?: string[];              // Available tools
  triggers?: AgentTriggers;      // Auto-trigger configuration

  // Permissions (backend only)
  permissions?: {
    read?: string[];             // Glob patterns for read access
    write?: string[];            // Glob patterns for write access
    tools?: string[];            // Allowed tools
  };
}

interface AgentTriggers {
  on_create?: { pattern: string };   // Run when file created
  on_modify?: { pattern: string };   // Run when file modified
  on_schedule?: { cron: string };    // Run on schedule
  on_invoke?: { enabled: boolean };  // Allow manual invocation
}
```

---

## Chat Session

A conversation session with an agent.

```typescript
interface ChatSession {
  // Identity
  id: string;                    // UUID
  agentPath?: string;            // Path to agent definition
  agentName?: string;            // Derived agent name

  // Content
  title?: string;                // Session title (AI-generated)
  messages: ChatMessage[];       // Conversation history

  // Timestamps
  createdAt: string;             // ISO 8601
  lastAccessed: string;          // ISO 8601 (backend uses this name)
  // Note: App may use "updatedAt" - should handle both

  // Status
  archived: boolean;             // Whether session is archived
  messageCount: number;          // Number of messages
}
```

---

## Chat Message

A single message in a conversation.

```typescript
interface ChatMessage {
  // Identity
  id: string;                    // Message ID
  sessionId: string;             // Parent session ID

  // Content
  role: "user" | "assistant";
  content: MessageContent[];     // Array of content blocks

  // Metadata
  timestamp: string;             // ISO 8601
  isStreaming?: boolean;         // Whether message is still streaming
}

type MessageContent = TextContent | ToolUseContent;

interface TextContent {
  type: "text";
  text: string;
}

interface ToolUseContent {
  type: "tool_use";
  tool: ToolCall;
}

interface ToolCall {
  name: string;                  // Tool name
  input: Record<string, any>;    // Tool input parameters
  result?: string;               // Tool output (after execution)
}
```

---

## SSE Stream Events

Events sent during streaming chat responses.

```typescript
// Session info at stream start
interface SessionEvent {
  type: "session";
  sessionId: string;
  title?: string;
  resumeInfo?: SessionResumeInfo;
}

// Tools initialized
interface InitEvent {
  type: "init";
  tools: string[];
}

// Text content (accumulated)
interface TextEvent {
  type: "text";
  content: string;               // Full accumulated text so far
}

// Tool execution
interface ToolUseEvent {
  type: "tool_use";
  tool: {
    name: string;
    input: Record<string, any>;
  };
}

// Stream complete
interface DoneEvent {
  type: "done";
  durationMs: number;
  title?: string;                // Final session title
  toolCalls?: ToolCall[];
  sessionResume?: SessionResumeInfo;
}

// Error occurred
interface ErrorEvent {
  type: "error";
  error: string;
}

// Resume information (for debugging)
interface SessionResumeInfo {
  method: "sdk_resume" | "context_injection" | "new";
  sdkSessionValid: boolean;
  contextInjected: boolean;
  messagesInjected: number;
  tokensEstimate: number;
}
```

---

## API Response Formats

### GET /api/agents

```typescript
interface AgentsResponse {
  // Returns array directly (not wrapped)
  Agent[]
}
```

### GET /api/chat/sessions

```typescript
interface SessionsResponse {
  // Returns array directly (not wrapped)
  ChatSession[]
}
```

### GET /api/chat/session/:id

```typescript
interface SessionDetailResponse {
  id: string;
  agentPath: string;
  agentName: string;
  messages: ChatMessage[];
  createdAt: string;
  lastAccessed: string;          // Note: not "updatedAt"
}
```

### POST /api/captures

Request:
```typescript
interface CaptureUploadRequest {
  filename: string;              // e.g., "2025-12-12_14-30-22.md"
  content: string;               // Full markdown content
  title?: string;
  context?: string;
  timestamp?: string;            // ISO 8601
}
```

Response:
```typescript
interface CaptureUploadResponse {
  path: string;                  // Server-side path: "captures/filename.md"
  content: string;
}
```

---

## Error Response Format

All API errors follow this structure:

```typescript
interface ApiError {
  error: string;                 // Human-readable message
  code?: string;                 // Machine-readable code
  details?: Record<string, any>; // Additional context
}
```

HTTP Status Codes:
- `400` - Bad Request (validation error)
- `401` - Unauthorized (missing/invalid API key)
- `403` - Forbidden (permission denied)
- `404` - Not Found
- `409` - Conflict (duplicate resource)
- `413` - Payload Too Large
- `429` - Rate Limited
- `500` - Internal Server Error
- `503` - Service Unavailable

---

## Vault Structure

Both app and agent operate on the same vault structure:

```
{vault}/
├── captures/                    # Voice recordings
│   ├── 2025-12-12_14-30-22.md  # Transcript
│   ├── 2025-12-12_14-30-22.opus # Audio
│   └── ...
│
├── spheres/                     # Knowledge spheres
│   └── {sphere-name}/
│       ├── CLAUDE.md           # System prompt
│       └── sphere.jsonl        # Links and metadata
│
├── agents/                      # Agent definitions (if exists)
│   └── {agent-name}.md
│
├── agent-sessions/              # Chat sessions (backend-managed)
│   └── {session-id}.md
│
└── .mcp.json                    # MCP server config (optional)
```

---

## Implementation Notes

### App (Flutter/Dart)
- Use `DateTime.parse()` for ISO 8601 strings
- Handle both `lastAccessed` and `updatedAt` for backwards compatibility
- Convert camelCase to snake_case when writing to markdown frontmatter

### Agent (Node.js)
- Use `new Date().toISOString()` for timestamps
- Return `lastAccessed` (not `updatedAt`) in API responses
- Parse markdown frontmatter with `gray-matter` library

### Compatibility
- Both must read/write the same markdown format
- Both must handle missing optional fields gracefully
- Both must validate paths to prevent traversal attacks

---

**Last Updated**: December 12, 2025
