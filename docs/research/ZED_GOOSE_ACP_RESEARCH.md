# Zed, Goose, and ACP Multi-Agent Integration Research

**Date**: November 3, 2025  
**Research Question**: How does Zed handle CLAUDE.md/system prompts with ACP, and how can we integrate Goose as an alternative agent alongside Claude in Parachute?

---

## Executive Summary

**Key Findings**:

1. **Zed uses Claude Agent SDK wrapped in ACP** - Your intuition was correct!
2. **ACP is an abstraction layer** - It standardizes communication between editors and multiple agents
3. **Each agent implements ACP differently** - Claude uses SDK, Goose uses native implementation
4. **Parachute's architecture is well-positioned** - ACP support enables easy multi-agent integration
5. **Goose integration is straightforward** - Uses same `goose acp` command as Zed

---

## 1. How Zed Handles Claude Code + ACP

### Architecture Discovery

**You were RIGHT!** ✅ Zed's Claude implementation uses Claude Agent SDK behind the scenes.

**The Architecture**:
```
Zed Editor (ACP Client)
    ↓ (JSON-RPC over ACP)
@zed-industries/claude-code-acp (Adapter)
    ↓ (SDK calls)
Claude Agent SDK (Official Anthropic SDK)
    ↓
Claude API
```

### The Adapter Package

**Repository**: https://github.com/zed-industries/claude-code-acp  
**NPM Package**: `@zed-industries/claude-code-acp`  
**License**: Apache 2.0 (Open Source)

**What It Does**:
> "Implements an ACP agent by using the official Claude Code SDK"

> "The adapter wraps Claude Code's SDK and translates its interactions into ACP's JSON RPC format"

**Technology**:
- TypeScript (98.3% of codebase)
- Wraps official Claude Agent SDK
- Translates SDK API → ACP JSON-RPC protocol
- Includes vendored Claude Code CLI

### How System Prompts Work in Zed

**In the Adapter** (claude-code-acp):
1. Receives ACP `session/new` request from Zed
2. Calls Claude Agent SDK with `ClaudeAgentOptions`
3. SDK parameter: `system_prompt` (programmatic)
4. SDK parameter: `setting_sources: ['project']` (enables CLAUDE.md)
5. SDK merges system_prompt + CLAUDE.md content
6. Sends combined prompt to Claude API

**Flow Diagram**:
```
User types in Zed
    ↓
Zed sends ACP request (no system prompt in ACP protocol)
    ↓
claude-code-acp adapter receives request
    ↓
Adapter calls Claude SDK:
    ClaudeAgentOptions(
        system_prompt: "You are Claude Code...",
        setting_sources: ['project']  // Load CLAUDE.md
    )
    ↓
SDK loads CLAUDE.md from ~/.claude/CLAUDE.md or project/.claude/CLAUDE.md
    ↓
SDK merges: [system_prompt] + [CLAUDE.md content]
    ↓
Final system prompt sent to Claude API
    ↓
Response → SDK → Adapter → ACP → Zed
```

**Key Insight**: Zed doesn't handle system prompts - the adapter does via Claude SDK.

### What This Means

**For Zed Users**:
- CLAUDE.md files work because the SDK loads them
- System prompt is controlled by the SDK, not ACP
- Different behavior per agent (Claude vs Goose vs others)

**For Parachute**:
- We're currently building prompts at the message level (correct for direct ACP)
- If we wanted SDK-style behavior, we'd need our own adapter
- OR we could just use the official adapters!

---

## 2. Goose and ACP Integration

### What is Goose?

**Created By**: Block (formerly Square)  
**Repository**: https://github.com/block/goose  
**Description**: Open source, extensible AI agent that goes beyond code suggestions

**Key Features**:
- Multi-LLM support (OpenAI, Anthropic, Google, etc.)
- Extensible via plugins/toolkits
- Native ACP implementation (since v1.8.0)
- MCP server support
- Terminal integration

### Goose's ACP Implementation

**Unlike Claude**, Goose has **native ACP support** built into the CLI:

**Command**: `goose acp`

**Architecture**:
```
Zed Editor (or any ACP client)
    ↓ (JSON-RPC over ACP)
Goose CLI (native ACP implementation)
    ↓
Goose Core (Python agent)
    ↓
Selected LLM API (OpenAI/Anthropic/etc)
```

**No adapter needed** - Goose speaks ACP directly!

### Configuration in Zed

**Basic Setup** (from Zed settings):
```json
{
  "agent_servers": {
    "Goose 🪿": {
      "command": "goose",
      "args": ["acp"],
      "env": {}
    }
  }
}
```

**With Custom Model**:
```json
{
  "agent_servers": {
    "Goose (GPT-4o)": {
      "command": "goose",
      "args": ["acp"],
      "env": {
        "GOOSE_PROVIDER": "openai",
        "GOOSE_MODEL": "gpt-4o"
      }
    },
    "Goose (Claude Sonnet)": {
      "command": "goose",
      "args": ["acp"],
      "env": {
        "GOOSE_PROVIDER": "anthropic",
        "GOOSE_MODEL": "claude-sonnet-4.5-20250514"
      }
    }
  }
}
```

**Supported Providers**:
- OpenAI (gpt-4o, gpt-4-turbo, etc.)
- Anthropic (claude-3.5-sonnet, claude-4, etc.)
- Google (gemini-pro, etc.)
- Local models via Ollama
- And more...

### Goose System Prompts

**System Prompt Files**:
```
crates/goose/src/prompts/
├── system_gpt_4.1.md
├── system_sonnet.md
└── ... (various prompts)
```

**Prompt Manager**: `crates/goose/src/agents/prompt_manager.rs`

**How It Works**:
1. Goose has built-in system prompts per model
2. Users can customize via configuration
3. Extensions can modify prompts
4. No CLAUDE.md file - uses Goose's own configuration

**Key Difference from Claude**:
- Claude: Uses CLAUDE.md files for project context
- Goose: Uses `.goosehints` and configuration files

### ACP Capabilities

**From Goose ACP Implementation**:
- ✅ Session management (multiple concurrent sessions)
- ✅ JSON-RPC over stdio
- ✅ Tool execution
- ✅ File operations
- ✅ Terminal integration
- ✅ Extension support
- ❌ Session persistence across restarts (limitation)

---

## 3. ACP as Multi-Agent Protocol

### Why ACP is Valuable

**The Vision**: One protocol, multiple agents

**ACP-Compatible Agents** (confirmed):
1. **Claude Code** (via @zed-industries/claude-code-acp)
2. **Goose** (via `goose acp`)
3. **Gemini** (Google's AI agent)
4. **Codex CLI** (OpenAI)
5. **StackPack** (and growing...)

**ACP-Compatible Editors**:
1. **Zed** (created the protocol)
2. **Neovim** (via CodeCompanion plugin)
3. **Emacs** (via acp.el)
4. **Marimo** (notebook editor)

### The Abstraction Model

**ACP's Design Philosophy**:

> "ACP and MCP complement each other perfectly: MCP handles the *what* (what data and tools can agents access), while ACP handles the *where* (where the agent lives in your workflow)."

**What This Means**:
- **ACP**: Standardizes editor ↔ agent communication
- **MCP**: Standardizes agent ↔ tools/data communication
- **Together**: Complete agent ecosystem

**For Parachute**:
```
Parachute (ACP Client)
    ↓
ACP Protocol
    ↓
┌────────────┬──────────────┬────────────┐
│ Claude     │ Goose        │ Future     │
│ (via SDK)  │ (native)     │ Agents     │
└────────────┴──────────────┴────────────┘
    ↓              ↓              ↓
Claude API    OpenAI/etc     Other LLMs
```

---

## 4. Parachute Integration Strategy

### Current State

**What Parachute Has**:
- ✅ ACP client implementation (`backend/internal/acp/client.go`)
- ✅ Session management per conversation
- ✅ JSON-RPC communication
- ✅ CLAUDE.md resolution and prepending
- ✅ WebSocket streaming to frontend
- ✅ Space-specific context

**What Parachute Uses**:
- Direct ACP connection to Claude's ACP agent
- System prompt via CLAUDE.md prepended to messages (correct pattern)

### Integration Options

#### Option 1: Direct Agent Integration (Recommended) 🎯

**Approach**: Spawn agent processes directly, like Zed does

**For Claude**:
```go
// Use official adapter
cmd := exec.Command("npx", "@zed-industries/claude-code-acp")
cmd.Env = append(os.Environ(), "ANTHROPIC_API_KEY="+apiKey)
// Stdin/Stdout for JSON-RPC
```

**For Goose**:
```go
cmd := exec.Command("goose", "acp")
cmd.Env = append(os.Environ(), 
    "GOOSE_PROVIDER=anthropic",
    "GOOSE_MODEL=claude-sonnet-4.5-20250514",
)
// Stdin/Stdout for JSON-RPC
```

**Advantages**:
- Uses official implementations
- Automatic updates when agents improve
- Standardized ACP interface
- No SDK coupling

**Implementation**:
```go
type AgentConfig struct {
    Name     string
    Command  string
    Args     []string
    Env      map[string]string
}

var agentConfigs = map[string]AgentConfig{
    "claude": {
        Name:    "Claude Code",
        Command: "npx",
        Args:    []string{"@zed-industries/claude-code-acp"},
        Env: map[string]string{
            "ANTHROPIC_API_KEY": getAnthropicKey(),
        },
    },
    "goose-claude": {
        Name:    "Goose (Claude)",
        Command: "goose",
        Args:    []string{"acp"},
        Env: map[string]string{
            "GOOSE_PROVIDER": "anthropic",
            "GOOSE_MODEL":    "claude-sonnet-4.5-20250514",
        },
    },
    "goose-gpt4": {
        Name:    "Goose (GPT-4o)",
        Command: "goose",
        Args:    []string{"acp"},
        Env: map[string]string{
            "GOOSE_PROVIDER": "openai",
            "GOOSE_MODEL":    "gpt-4o",
            "OPENAI_API_KEY": getOpenAIKey(),
        },
    },
}
```

#### Option 2: Keep Current Direct Connection

**Approach**: Continue using current ACP client, just spawn different agents

**Current**:
```go
acpClient, err := acp.NewACPClient(apiKey)
// This spawns Claude's ACP agent
```

**Modified**:
```go
type ACPClient struct {
    agentType string  // "claude" | "goose" | etc
    // ... existing fields
}

func NewACPClient(agentType string, config map[string]string) (*ACPClient, error) {
    switch agentType {
    case "claude":
        process = SpawnClaudeACP(config["api_key"])
    case "goose":
        process = SpawnGooseACP(config)
    }
    // ... rest of implementation
}
```

**Advantages**:
- Minimal code changes
- Reuses existing ACP infrastructure
- Easy to add new agents

#### Option 3: Agent Abstraction Layer

**Approach**: Create an interface for different agent types

```go
type Agent interface {
    Initialize() error
    CreateSession(workingDir string) (string, error)
    SendPrompt(sessionID, prompt string) error
    RegisterSession(sessionID string) (<-chan Request, <-chan Notification)
    Close() error
}

type ClaudeAgent struct {
    client *ACPClient
    // Claude-specific
}

type GooseAgent struct {
    client *ACPClient
    // Goose-specific
}

func NewAgent(agentType string, config AgentConfig) (Agent, error) {
    switch agentType {
    case "claude":
        return &ClaudeAgent{...}, nil
    case "goose":
        return &GooseAgent{...}, nil
    }
}
```

**Advantages**:
- Clean architecture
- Easy testing
- Future-proof
- Per-agent customization

---

## 5. CLAUDE.md Handling Across Agents

### Claude Agent SDK (via claude-code-acp)

**System Prompt Strategy**:
```typescript
// Inside the adapter
const options: ClaudeAgentOptions = {
    systemPrompt: "You are Claude Code, an AI coding assistant...",
    settingSources: ['project'],  // Load CLAUDE.md
}
```

**CLAUDE.md Locations**:
- Project: `.claude/CLAUDE.md` or `CLAUDE.md`
- User: `~/.claude/CLAUDE.md`

**Behavior**: SDK merges both

### Goose (Native ACP)

**System Prompt Strategy**:
- Built-in prompts per model (in source code)
- Customizable via Goose configuration
- Extensions can modify prompts
- Uses `.goosehints` for project context

**No CLAUDE.md** - uses Goose's own configuration system

### For Parachute: Unified Approach

**Challenge**: Different agents handle context differently

**Solution**: Space-specific configuration per agent

**Proposed Structure**:
```
~/Parachute/spaces/my-space/
├── CLAUDE.md              # For Claude-based agents
├── .goosehints           # For Goose
├── agent-config.json     # Agent-specific settings
└── space.sqlite          # Knowledge graph
```

**agent-config.json**:
```json
{
  "claude": {
    "model": "claude-sonnet-4.5-20250514",
    "system_prompt_file": "CLAUDE.md",
    "use_space_knowledge": true
  },
  "goose": {
    "provider": "anthropic",
    "model": "claude-sonnet-4.5-20250514",
    "context_file": ".goosehints",
    "use_space_knowledge": true
  }
}
```

**Backend Implementation**:
```go
func (h *MessageHandler) buildPromptWithContext(
    agent string,
    spaceObj *space.Space,
    currentPrompt string,
) string {
    switch agent {
    case "claude":
        // Read CLAUDE.md, resolve variables
        claudeMD := h.readAndResolveClaudeMD(spaceObj)
        return claudeMD + "\n\n---\n\n" + currentPrompt
        
    case "goose":
        // Goose handles context via .goosehints automatically
        // Just send the prompt
        return currentPrompt
        
    default:
        return currentPrompt
    }
}
```

---

## 6. Implementation Roadmap

### Phase 1: Add Agent Selection (Week 1)

**Backend Changes**:
1. Add `agent_type` field to Conversation model
2. Modify ACP client to spawn different agents
3. Environment variable configuration for agent settings

**Frontend Changes**:
1. Add agent selector when creating conversation
2. Display current agent in conversation header
3. Agent-specific icons/branding

**Database Migration**:
```sql
ALTER TABLE conversations ADD COLUMN agent_type TEXT DEFAULT 'claude';
ALTER TABLE conversations ADD COLUMN agent_config TEXT DEFAULT '{}';
```

### Phase 2: Goose Integration (Week 2)

**Requirements**:
1. User has Goose CLI installed (`brew install goose` or similar)
2. API keys configured (OpenAI, Anthropic, etc.)

**Backend Implementation**:
```go
// internal/acp/goose.go
func SpawnGooseACP(provider, model, apiKey string) (*ACPProcess, error) {
    cmd := exec.Command("goose", "acp")
    cmd.Env = append(os.Environ(),
        fmt.Sprintf("GOOSE_PROVIDER=%s", provider),
        fmt.Sprintf("GOOSE_MODEL=%s", model),
        fmt.Sprintf("%s_API_KEY=%s", strings.ToUpper(provider), apiKey),
    )
    // ... spawn process
}
```

**Settings UI**:
```
┌─ Agent Settings ────────────────────────┐
│                                         │
│ Available Agents:                       │
│ ○ Claude (Anthropic)                    │
│ ○ Goose - Claude Sonnet                 │
│ ○ Goose - GPT-4o                        │
│ ○ Goose - Gemini Pro                    │
│                                         │
│ Claude Settings:                        │
│ API Key: ●●●●●●●●●● [Change]            │
│                                         │
│ Goose Settings:                         │
│ OpenAI API Key: ●●●●●●●● [Add]          │
│ Anthropic API Key: ●●●●●● [Add]         │
│                                         │
│ Default Agent: [Claude ▼]               │
│                                         │
└─────────────────────────────────────────┘
```

### Phase 3: Multi-Agent Support (Week 3)

**Features**:
1. Switch agents mid-conversation
2. Compare responses from different agents
3. Agent-specific conversation history
4. Cost tracking per agent

**UI Concept**:
```
┌─ Conversation: "Fix bug in API" ────────┐
│                                         │
│ Agent: [Claude ▼] [Switch]             │
│                                         │
│ 👤 You: The /api/users endpoint is...  │
│                                         │
│ 🤖 Claude: I see the issue. The...     │
│                                         │
│ [Compare with Goose]                    │
│                                         │
└─────────────────────────────────────────┘
```

### Phase 4: Space-Aware Agent Config (Week 4)

**Concept**: Different default agents per space

**Example**:
- **Work Projects** space → Goose (GPT-4o) for coding
- **Learning Journal** space → Claude (Sonnet) for reflection
- **Quick Notes** space → Gemini for speed

**Configuration**:
```json
// ~/Parachute/spaces/work-projects/space-config.json
{
  "name": "Work Projects",
  "default_agent": "goose-gpt4",
  "agent_settings": {
    "goose-gpt4": {
      "provider": "openai",
      "model": "gpt-4o",
      "context_file": ".goosehints"
    }
  }
}
```

---

## 7. Key Insights & Recommendations

### Your Intuition Was Right ✅

> "I believe Zed's Claude ACP is using Claude Agent SDK behind the scenes"

**Confirmed**: Zed uses `@zed-industries/claude-code-acp` which wraps Claude Agent SDK.

### ACP is the Right Choice ✅

**Why keeping ACP is smart**:

1. **Multi-Agent Support**: One protocol, many agents
2. **Future-Proof**: Standard protocol with growing ecosystem
3. **Goose Integration**: Simple as `goose acp` command
4. **No Lock-In**: Can switch agents without architecture changes
5. **Open Source**: Community-driven, not vendor-specific

**Compared to switching to Claude SDK directly**:
- ❌ Lock-in to Anthropic
- ❌ Can't use Goose or other agents
- ❌ Lose protocol abstraction
- ❌ More coupling, less flexibility

### System Prompt Strategy ✅

**Current approach (CLAUDE.md prepended to messages)** is correct for direct ACP.

**If using official adapters** (recommended):
- Claude adapter will handle CLAUDE.md via SDK
- Goose will handle .goosehints automatically
- Parachute just sends the user's message
- Much cleaner!

### Recommended Architecture

**Best Approach**:
```
Parachute Backend (ACP Client)
    ↓
Agent Manager (spawn processes)
    ↓
┌──────────────────────┬───────────────────────┐
│ claude-code-acp      │ goose acp            │
│ (handles CLAUDE.md)  │ (handles .goosehints)│
└──────────────────────┴───────────────────────┘
```

**Benefits**:
- Leverage official implementations
- Automatic context handling per agent
- Minimal Parachute code
- Easy to add new agents

---

## 8. Next Steps

### Immediate Actions

1. **Validate ACP spawning**: Test spawning `goose acp` from Go
2. **Environment config**: Add agent selection to settings
3. **Database migration**: Add `agent_type` to conversations
4. **Frontend dropdown**: Agent selector in new conversation UI

### Week 1 Goals

- [ ] Add agent type to conversation model
- [ ] Implement agent spawning for Claude and Goose
- [ ] Basic UI for agent selection
- [ ] Test both agents work with current ACP client

### Documentation Needed

1. User guide: How to install Goose
2. User guide: Configuring API keys for different agents
3. Developer guide: Adding new ACP agents
4. Architecture doc: Multi-agent system design

---

## Conclusion

**Your ACP choice was prescient** - it positions Parachute perfectly for the multi-agent future.

**Key Takeaways**:
1. ✅ Zed uses Claude SDK wrapped in ACP (you were right!)
2. ✅ ACP enables easy multi-agent support
3. ✅ Goose integration is straightforward
4. ✅ Current CLAUDE.md strategy works
5. ✅ Using official adapters is the best path forward

**The Path Forward**:
- Keep ACP architecture
- Spawn official agent implementations
- Let each agent handle its own context (CLAUDE.md, .goosehints, etc.)
- Add UI for agent selection
- Profit from growing ACP ecosystem 🚀

---

**Researched by**: Claude Code Agent  
**Sources**:
- Zed Industries GitHub repos
- Goose documentation and GitHub
- ACP protocol specification
- Agent adapter implementations

**Status**: Research complete - Multi-agent strategy validated ✅
