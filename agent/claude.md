# Parachute Agent - Development Guide

## Project Overview

Parachute Agent is the backend for Parachute - an AI agent system that uses markdown files as both configuration and execution environment. Agents are defined in markdown files with YAML frontmatter, and conversations are persisted as readable markdown.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐
│ Parachute App   │     │ Obsidian Plugin │
└────────┬────────┘     └────────┬────────┘
         │                       │
         └───────────┬───────────┘
                     ▼
         ┌───────────────────────┐
         │   Express Server      │
         │   (port 3333)         │
         └───────────┬───────────┘
                     │
          ┌──────────┴──────────┐
          ▼                     ▼
   ┌──────────────┐      ┌──────────────┐
   │ Session Mgr  │      │ Orchestrator │
   │ (markdown)   │      │ (Claude SDK) │
   └──────────────┘      └──────────────┘
```

## Key Files

| File | Purpose |
|------|---------|
| `server.js` | Express API server |
| `lib/orchestrator.js` | Agent execution via Claude SDK |
| `lib/session-manager.js` | Session persistence as markdown |
| `lib/agent-loader.js` | Load agent definitions from markdown |
| `lib/vault-utils.js` | Shared file utilities |
| `lib/mcp-loader.js` | MCP server configuration management |
| `lib/skills-loader.js` | Agent skills discovery and management |
| `lib/path-validator.js` | Path traversal prevention utilities |
| `lib/logger.js` | Structured logging with in-memory buffer |
| `lib/errors.js` | Custom error classes with HTTP status codes |
| `obsidian-plugin/main.ts` | Optional Obsidian plugin |

## Commands

```bash
npm start                        # Start server
npm run dev                      # Start with auto-reload
npm test                         # Run tests
VAULT_PATH=/path/to/vault npm start  # Custom vault
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/health` | GET | Health check (returns `{status: "ok", timestamp}`) |
| `/api/agents` | GET | List agents |
| `/api/chat` | POST | Send message (body: `{message, agentPath?, sessionId?, initialContext?, workingDirectory?}`) |
| `/api/chat/stream` | POST | Streaming chat via SSE (same body as `/api/chat`) |
| `/api/directories` | GET | List available working directories for chat sessions |
| `/api/chat/sessions` | GET | List all sessions |
| `/api/chat/session/:id` | GET | Get session by ID with messages |
| `/api/chat/session/:id/archive` | POST | Archive a session |
| `/api/chat/session/:id/unarchive` | POST | Unarchive a session |
| `/api/chat/session/:id` | DELETE | Delete session permanently |
| `/api/chat/session` | DELETE | Clear session (legacy) |
| `/api/stats` | GET | Get session stats and memory usage |
| `/api/permissions/stream` | GET | SSE stream for permission requests |
| `/api/permissions/:id/grant` | POST | Grant a pending permission |
| `/api/permissions/:id/deny` | POST | Deny a pending permission |
| `/api/captures` | GET | List all captures |
| `/api/captures` | POST | Upload a document (body: `{filename, content, title?, context?, timestamp?}`) |
| `/api/captures/:filename` | GET | Get a capture file's content |
| `/api/captures/:filename` | HEAD | Check if a capture file exists (200/404) |
| `/api/mcp` | GET | List all MCP server configurations |
| `/api/mcp/:name` | POST | Add or update an MCP server |
| `/api/mcp/:name` | DELETE | Remove an MCP server |
| `/api/skills` | GET | List all available skills |
| `/api/skills/:name` | GET | Get full skill content |
| `/api/skills/:name` | POST | Create or update a skill |
| `/api/skills/:name` | DELETE | Delete a skill |
| `/api/agents-md` | GET | Get AGENTS.md content |
| `/api/agents-md` | PUT | Update AGENTS.md content |
| `/api/analytics` | GET | Get session and agent analytics |
| `/api/logs` | GET | Query recent logs (params: `level`, `component`, `since`, `limit`) |
| `/api/logs/stats` | GET | Get log statistics |

## Agent Definition Format

```markdown
---
name: Agent Name
description: What this agent does
model: claude-sonnet-4-20250514
system_prompt: |
  You are a helpful assistant...
---

# Agent Name

Additional context for the agent.
```

## Session Storage

Sessions stored as markdown in `agent-sessions/`:
- Human-readable format
- YAML frontmatter with session metadata
- Conversation as H3 headers with timestamps
- Legacy paths (`agent-chats/`, `agent-logs/`) still indexed for migration

## Key Patterns

### Session Architecture (Lazy Loading)
Sessions use a two-tier architecture:
- **Index** (`sessionIndex`): Lightweight, loaded at startup. Contains metadata only.
- **Loaded Sessions** (`loadedSessions`): Full content loaded on-demand from markdown.
- **Active SDK Sessions** (`activeSessions`): Ephemeral, may expire.

### SDK Session Resumption
The `sdk_session_id` in frontmatter enables conversation resumption:
- Try SDK resume first (fastest, if session still alive on Anthropic's servers)
- If unavailable/expired, inject context from markdown history
- Context injection: Last N messages that fit in ~50k tokens
- New SDK session ID captured and saved to markdown

### Session Resume Debug Info
Every chat response includes `sessionResume` with:
```json
{
  "method": "sdk_resume | context_injection | new",
  "sdkSessionValid": true,
  "sdkResumeAttempted": true,
  "contextInjected": false,
  "messagesInjected": 0,
  "tokensEstimate": 0,
  "previousMessageCount": 10,
  "loadedFromDisk": true,
  "cacheHit": false
}
```

### Session Management
- Each chat gets a unique `sessionId` for isolation
- Sessions track `archived` status (persisted in YAML)
- Plugin uses `serverId` for history fetch vs `id` for API routing
- Stale sessions evicted from memory after 30 min

### Permission System
- Agents define `write_permissions` as glob patterns in frontmatter
- Writes outside allowed paths trigger permission requests via SSE
- Plugin shows inline permission dialogs for user approval

### Streaming Chat
The `/api/chat/stream` endpoint returns SSE events for real-time UI updates:
- `session`: Session ID and resume info at start
- `init`: SDK initialized with available tools
- `text`: Text content (full content, updated incrementally)
- `tool_use`: Tool being executed with name and input
- `done`: Final result with toolCalls, durationMs, spawned, sessionResume
- `error`: Error message if something went wrong

### Initial Context
Pass `initialContext` in the chat request body to provide context for new sessions:
- Only used on first message (when `session.messages.length === 0`)
- If `message` is empty, `initialContext` becomes the entire message (for passing transcripts/docs directly)
- If both provided, formatted as: `## Context\n\n{initialContext}\n\n---\n\n## Request\n\n{message}`

### Working Directory
Pass `workingDirectory` in the chat request body to run a session against a different directory:
- The SDK's `cwd` will be set to this directory instead of the vault
- Sessions are still stored in the home vault, but Claude operates in the specified directory
- Useful for chatting with external codebases while keeping sessions in your vault
- The `GET /api/directories` endpoint lists available directories (home vault + recently used)
- Sessions track their working directory in metadata and return it in responses

### Error Handling
- Agent execution errors returned in response
- Session manager logs errors but doesn't throw on save failures

### Skills (Claude Agent SDK Skills)
Skills extend agents with specialized capabilities. They're loaded from `{vault}/.claude/skills/`.

Skills are filesystem-based packages of instructions that Claude uses automatically when relevant to the task. Claude reads the skill's SKILL.md and follows its instructions, executing any scripts or code via bash.

**How skills work:**
1. Skills are discovered at startup from `.claude/skills/*/SKILL.md`
2. Only the skill description is loaded initially (~100 tokens per skill)
3. When triggered by a relevant request, Claude reads the full SKILL.md
4. Claude follows the instructions, running scripts via bash

**To use skills:**
1. Install skill into `{vault}/.claude/skills/{skill-name}/SKILL.md`
2. Include `"Skill"` in agent's `tools` array (or use default tools)
3. Claude automatically invokes relevant skills based on user requests

**Example: dev-browser skill (browser automation)**
```bash
# Install dev-browser skill
git clone --depth 1 https://github.com/SawyerHood/dev-browser.git /tmp/dev-browser
mkdir -p {vault}/.claude/skills
cp -r /tmp/dev-browser/skills/dev-browser {vault}/.claude/skills/
cd {vault}/.claude/skills/dev-browser && bun install
```

**Agent with skills:**
```markdown
---
agent:
  name: web-researcher
  permissions:
    tools: [Read, Write, Glob, Grep, Bash, Skill]
---
```

**Note:** Skills handle their own server processes. For example, dev-browser's SKILL.md tells Claude to run `./server.sh &` before executing browser scripts. The SDK doesn't automatically manage skill servers.

### MCP Servers (Browser Automation)
Agents can connect to MCP (Model Context Protocol) servers for extended capabilities like browser automation.

**Global MCP Configuration (`.mcp.json`):**
MCP servers can be defined globally at your vault root in `.mcp.json`. This allows multiple agents to reference the same servers without duplication.

```json
{
  "browser": {
    "command": "npx",
    "args": ["@browsermcp/mcp@latest"]
  },
  "filesystem": {
    "command": "npx",
    "args": ["@modelcontextprotocol/server-filesystem", "/path/to/allowed"]
  }
}
```

**Managing MCP Servers:**
- **Via Plugin:** Settings → MCP Servers section (recommended for Obsidian users)
- **Via API:** `GET/POST/DELETE /api/mcp/:name`
- **Via File:** Edit `.mcp.json` directly

**Agent MCP Configuration:**
Agents can reference global servers by name, define inline configs, or mix both:

```markdown
---
agent:
  name: web-browser
  description: Agent with browser access
  mcpServers: [browser]  # Reference by name from .mcp.json
---
```

Or with inline config:
```markdown
---
agent:
  name: web-browser
  mcpServers:
    browser:
      command: npx
      args: ["@browsermcp/mcp@latest"]
---
```

**BrowserMCP Setup:**
1. Install the BrowserMCP browser extension from [browsermcp.io](https://browsermcp.io)
2. Add the browser server via plugin settings or `.mcp.json`
3. Reference it in your agent: `mcpServers: [browser]`

**MCP Server Configuration Formats:**

| Transport | Config | Description |
|-----------|--------|-------------|
| Stdio (recommended) | `{command: "npx", args: [...]}` | Auto-starts via npx |
| SSE | `{type: "sse", url: "..."}` | Connect to running server |
| HTTP | `{type: "http", url: "..."}` | HTTP streaming |

**BrowserMCP Tools:**
- `mcp__browser__navigate` - Go to a URL
- `mcp__browser__click` - Click an element
- `mcp__browser__type_text` - Type into a field
- `mcp__browser__take_screenshot` - Capture page screenshot
- `mcp__browser__wait` - Wait for duration
- `mcp__browser__press_key` - Press keyboard key

**Advantages:**
- Uses your real browser with existing logins
- Avoids bot detection (real fingerprint)
- Runs locally for privacy

## Authentication

This project uses **Claude Agent SDK authentication** via `claude login`. No API keys are needed!

```bash
# One-time setup
npm install -g @anthropic-ai/claude-code
claude login
```

The SDK automatically uses the credentials stored by `claude login`.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VAULT_PATH` | `./sample-vault` | Path to markdown folder |
| `PORT` | `3333` | Server port |
| `HOST` | `0.0.0.0` | Server bind address |
| `CORS_ORIGINS` | `*` | Comma-separated allowed origins, or `*` for all |
| `API_KEY` | (none) | Optional API key for client authentication |
| `MAX_MESSAGE_LENGTH` | `102400` | Max chat message length in bytes (100KB) |
| `LOG_LEVEL` | `INFO` | Logging level: `DEBUG`, `INFO`, `WARN`, `ERROR` |

### Security Configuration

For production deployments:

```bash
# Restrict CORS to specific origins
CORS_ORIGINS=http://localhost:3000,https://myapp.com

# Enable API key authentication
API_KEY=your-secret-key-here

# Clients must include header: X-API-Key: your-secret-key-here
# Or: Authorization: Bearer your-secret-key-here
```
