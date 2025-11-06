# Research: System Prompts, CLAUDE.md, and ACP

**Date**: November 3, 2025  
**Research Question**: How does Claude Agent SDK handle system prompts, what is the role of CLAUDE.md, and can we manually customize system prompts instead of relying on CLAUDE.md?

---

## Executive Summary

**Key Findings**:

1. **Claude Agent SDK** (Python/TypeScript) allows **programmatic system prompt configuration** via `system_prompt` parameter in `ClaudeAgentOptions`
2. **CLAUDE.md files** are **optional supplements** to system prompts, not replacements
3. **Parachute currently uses ACP (Agent Client Protocol)** which is a **different protocol** from Claude Agent SDK
4. **ACP does NOT support custom system prompts** - it relies on the agent's built-in behavior
5. **Parachute's current approach** (CLAUDE.md + variable resolution) is the **correct architecture** for ACP-based systems

---

## 1. Claude Agent SDK (Python/TypeScript)

### What It Is
The Claude Agent SDK is Anthropic's official SDK for building AI agents with Claude. It provides:
- File system access and bash command execution
- MCP (Model Context Protocol) integrations
- Subagents, Agent Skills, Hooks, Slash Commands
- **Programmatic system prompt configuration**

### System Prompt Configuration

**Python Example**:
```python
from claude_agent_sdk import ClaudeAgentOptions, query

options = ClaudeAgentOptions(
    system_prompt="You are a helpful coding assistant specialized in Go backend development"
)

async for message in query(prompt="Review this code", options=options):
    print(message)
```

**TypeScript Example**:
```typescript
import { ClaudeAgentOptions } from 'claude-agent-sdk';

const options: ClaudeAgentOptions = {
  systemPrompt: "You are a database expert focusing on SQLite optimization"
};
```

### CLAUDE.md in Agent SDK

**Purpose**: CLAUDE.md files maintain **project context** that **supplements** the system prompt

**Location Options**:
- `CLAUDE.md` or `.claude/CLAUDE.md` in project directory
- `~/.claude/CLAUDE.md` for user-level instructions

**Enabling CLAUDE.md**:
```python
# Python
options = ClaudeAgentOptions(
    system_prompt="You are a helpful assistant",
    setting_sources=["project"]  # Enable CLAUDE.md loading
)
```

```typescript
// TypeScript
const options: ClaudeAgentOptions = {
  systemPrompt: "You are a helpful assistant",
  settingSources: ['project']  // Enable CLAUDE.md loading
};
```

**Key Point**: CLAUDE.md is **additive**, not a replacement. The SDK will:
1. Use the `system_prompt` parameter as the base
2. Load CLAUDE.md if `setting_sources` includes 'project'
3. Merge both into the final system prompt sent to Claude

**Override Behavior**:
```python
# To use ONLY your custom system prompt (ignore CLAUDE.md):
options = ClaudeAgentOptions(
    system_prompt="Your custom prompt",
    setting_sources=[]  # Don't load CLAUDE.md
)

# To use an empty system prompt:
options = ClaudeAgentOptions(
    custom_system_prompt=""  # Explicit empty string
)
```

---

## 2. Agent Client Protocol (ACP)

### What It Is
ACP (Agent Client Protocol) is a **different protocol** from Claude Agent SDK. It's a JSON-RPC 2.0 based standard for communication between **code editors** and **AI coding agents**.

**Created By**: Zed Industries  
**Purpose**: Standardize editor ↔ agent communication (like LSP but for AI)  
**Used By**: Zed editor, Claude Code, Cursor (potentially), and **Parachute**

### ACP Protocol Flow

```
Editor/Client (Parachute Backend)
    ↓ (JSON-RPC 2.0)
ACP Agent (Anthropic's Claude)
    ↓
Claude API
```

### ACP Methods

**Core Methods**:
1. `initialize` - Handshake between client and agent
2. `session/new` - Create a new chat session
3. `session/prompt` - Send a user message to the session
4. `session/update` - Receive streaming responses (notifications)

**Session Creation (`session/new`)**:
```json
{
  "method": "session/new",
  "params": {
    "cwd": "/Users/you/Parachute",
    "mcpServers": []
  }
}
```

**Notable Absence**: **NO `system_prompt` parameter**

### System Prompts in ACP

ACP uses **Session Modes** instead of direct system prompt parameters:

**Session Modes**:
- `ask` - Question answering mode
- `architect` - Design and planning mode  
- `code` - Implementation mode

**How Modes Work**:
- Each mode has a different built-in system prompt
- Modes affect tool availability and permission behaviors
- Clients can switch modes via `session/set_mode`
- Agents can autonomously change modes

**Example**:
```json
{
  "method": "session/set_mode",
  "params": {
    "sessionId": "abc123",
    "modeId": "code"
  }
}
```

**Critical Limitation**: **You cannot inject a custom system prompt** into ACP. The agent (Claude) controls its own system prompts based on the selected mode.

---

## 3. How Parachute Currently Works

### Architecture

Parachute uses **ACP (Agent Client Protocol)**, NOT Claude Agent SDK:

**Code Evidence** (`backend/internal/acp/client.go`):
```go
// NewACPClient creates a new ACP client with the given API key
func NewACPClient(apiKey string) (*ACPClient, error) {
    process, err := SpawnACP(apiKey)
    // ...
}

// NewSession creates a new ACP session
func (c *ACPClient) NewSession(workingDir string, mcpServers []MCPServer) (string, error) {
    params := NewSessionParams{
        Cwd:        workingDir,
        McpServers: mcpServers,  // NO system_prompt parameter
    }
    // ...
}
```

### Current CLAUDE.md Strategy

**Implementation** (`backend/internal/api/handlers/message_handler.go:420-445`):

```go
func (h *MessageHandler) buildPromptWithContext(
    spaceObj *space.Space,
    messages []*conversation.Message,
    currentPrompt string,
) string {
    prompt := ""

    // Include CLAUDE.md context if it exists
    claudeMD, err := h.spaceService.ReadClaudeMD(spaceObj)
    if err == nil && claudeMD != "" {
        // Resolve dynamic variables in CLAUDE.md
        resolvedClaudeMD, err := h.contextService.ResolveVariables(claudeMD, spaceObj.Path)
        if err != nil {
            log.Printf("⚠️  Failed to resolve CLAUDE.md variables: %v", err)
            resolvedClaudeMD = claudeMD // Fallback to unresolved
        }

        prompt += "# Context from CLAUDE.md\n\n"
        prompt += resolvedClaudeMD
        prompt += "\n\n---\n\n"
    }

    // Include conversation history
    // ...

    // Add current user message
    prompt += currentPrompt

    return prompt
}
```

**What This Does**:
1. Read CLAUDE.md from the space folder
2. Resolve dynamic variables ({{note_count}}, {{recent_tags}}, etc.)
3. **Prepend resolved CLAUDE.md to the user's message**
4. Send the combined prompt to ACP via `session/prompt`

**Result**: The CLAUDE.md content becomes **part of the user message**, not the system prompt.

---

## 4. Why This Matters: ACP vs Agent SDK

### ACP Architecture (What Parachute Uses)

```
User: "What should I work on?"
    ↓
Backend builds prompt:
    "# Context from CLAUDE.md
     You're helping manage work projects.
     Linked Notes: 15
     Recent Topics: backend, performance, bug
     
     ---
     
     What should I work on?"
    ↓
ACP session/prompt →  Claude
    ↓
Claude sees:
  System Prompt: [ACP's built-in agent prompt]
  User Message: [CLAUDE.md context + user question]
```

**Key Point**: CLAUDE.md is **part of the conversation**, not the system prompt.

### Agent SDK Architecture (Alternative)

```
User: "What should I work on?"
    ↓
SDK builds request:
  System Prompt: [Contents of CLAUDE.md + base instructions]
  User Message: "What should I work on?"
    ↓
Claude API
```

**Key Point**: CLAUDE.md is **merged into the system prompt** before sending to Claude.

---

## 5. Can We Customize System Prompts in Parachute?

### Short Answer: **Partially, through user messages**

### Current Capabilities

**What We CAN Do** (Already Implemented):
1. ✅ Create per-space CLAUDE.md files
2. ✅ Include dynamic variables ({{note_count}}, {{recent_tags}})
3. ✅ Prepend CLAUDE.md to every user message
4. ✅ Create different "personalities" per space via CLAUDE.md
5. ✅ Cross-pollinate notes with different contexts per space

**What We CANNOT Do** (ACP Limitation):
1. ❌ Set a true system prompt (ACP doesn't support it)
2. ❌ Override ACP's built-in agent behavior
3. ❌ Control tool permissions programmatically
4. ❌ Change the fundamental agent mode beyond ACP's modes

### Workarounds & Alternatives

#### Option 1: Enhanced CLAUDE.md (Current Approach) ✅

**Advantages**:
- Already implemented
- Works within ACP constraints
- Per-space customization
- Dynamic context from space.sqlite

**Best Practice**:
```markdown
# [Space Name]

You are [role description].

## Your Behavior
- [Instruction 1]
- [Instruction 2]
- [Instruction 3]

## Available Knowledge
- Linked Notes: {{note_count}}
- Recent Topics: {{recent_tags}}

## Guidelines
When responding:
1. [Guideline 1]
2. [Guideline 2]

## Context
[Space-specific context...]
```

**Example** (Work Projects space):
```markdown
# Work Projects Management

You are a technical project manager helping me organize engineering work.

## Your Behavior
- Prioritize by urgency and customer impact
- Reference past discussions from linked notes
- Suggest actionable next steps
- Track progress on ongoing features

## Available Knowledge
- Linked Notes: {{note_count}} work discussions
- Active Topics: {{recent_tags}}
- Meeting Notes: {{notes_tagged:meeting}}
- Bug Reports: {{notes_tagged:bug}}

## Guidelines
When I ask what to work on:
1. Review recent meeting notes for commitments
2. Check bug reports for urgent issues  
3. Consider customer feedback
4. Suggest a prioritized list with reasoning

## Context
This space tracks all my software engineering projects at work.
Focus on backend API development, database optimization, and
customer-facing features.
```

**Result**: Claude behaves as a project manager **within that space** because every message starts with these instructions.

#### Option 2: Switch to Claude Agent SDK (Major Refactor) ⚠️

**What This Would Involve**:
1. Remove ACP client entirely
2. Integrate Claude Agent SDK (Python or Go wrapper)
3. Rewrite message handling to use SDK's query/agent APIs
4. Configure `system_prompt` parameter per space
5. Optionally still use CLAUDE.md as supplementary context

**Advantages**:
- True system prompt control
- Better integration with Anthropic's tools
- More predictable agent behavior
- Future-proof (official Anthropic SDK)

**Disadvantages**:
- Major architectural change (~2-3 days work)
- Loss of ACP's streaming protocol benefits
- Need to reimplement WebSocket notifications
- Breaks compatibility with ACP-based tools

**Code Changes Required**:
```go
// OLD (ACP):
result := acpClient.SessionPrompt(sessionID, prompt)

// NEW (Agent SDK):
import "github.com/anthropics/claude-agent-sdk-go"

options := sdk.ClaudeAgentOptions{
    SystemPrompt: resolvedClaudeMD,  // Use CLAUDE.md as system prompt
}

for message := range sdk.Query(userPrompt, options) {
    // Stream to WebSocket
}
```

#### Option 3: Hybrid Approach (Best of Both) 🎯

**Idea**: Use ACP for streaming but enhance prompting strategy

**Implementation**:
1. Keep current ACP architecture
2. Add a "meta-prompt" that instructs Claude to follow CLAUDE.md religiously
3. Include explicit role reinforcement in every message

**Enhanced buildPromptWithContext**:
```go
func (h *MessageHandler) buildPromptWithContext(...) string {
    prompt := ""

    // Meta-instruction
    prompt += "SYSTEM CONTEXT (follow these instructions strictly):\n\n"

    // Include CLAUDE.md with emphasis
    if claudeMD != "" {
        resolvedClaudeMD, _ := h.contextService.ResolveVariables(claudeMD, spaceObj.Path)
        prompt += resolvedClaudeMD
        prompt += "\n\n"
    }

    // Reinforce role
    prompt += "IMPORTANT: You must behave according to the system context above.\n"
    prompt += "Your responses should reflect the role, guidelines, and knowledge described.\n\n"
    prompt += "---\n\n"

    // Conversation history
    // ...

    // Current user message
    prompt += "USER QUESTION:\n"
    prompt += currentPrompt

    return prompt
}
```

**Result**: Stronger adherence to CLAUDE.md instructions without changing ACP architecture.

---

## 6. Recommendations for Parachute

### Immediate (No Code Changes) ✅

1. **Document CLAUDE.md best practices** for users
2. **Create example templates** for common space types:
   - Work Projects
   - Learning Journal
   - Personal Ideas
   - Meeting Notes
   - Customer Feedback
3. **Add CLAUDE.md editor in UI** so users can customize without file system access

### Short-Term (Minor Enhancement) 🎯

1. **Implement Option 3 (Hybrid Approach)**:
   - Add meta-instructions to reinforce CLAUDE.md adherence
   - Test with different Claude models (3.5 vs 4.0)
   - Measure improvement in instruction-following

2. **Add system prompt templates**:
   - Pre-built CLAUDE.md files for common use cases
   - Users can pick a template when creating a space
   - Variables still resolve dynamically

3. **Expose mode switching**:
   - Add UI to switch between ACP modes (ask/architect/code)
   - Different modes for different conversation types
   - Mode indicator in conversation UI

### Long-Term (If Needed) ⚠️

1. **Evaluate migration to Claude Agent SDK**:
   - If ACP limitations become blocking
   - If true system prompt control is critical
   - If Anthropic deprecates ACP in favor of SDK

2. **Build abstraction layer**:
   - Create interface for both ACP and Agent SDK
   - Allow switching between backends
   - Test both approaches with users

---

## 7. Conclusion

### CLAUDE.md in Parachute

**Current Implementation is Correct** ✅

Parachute's use of CLAUDE.md is the **optimal approach** for an ACP-based system:

1. **Per-space context**: Each space has its own personality
2. **Dynamic variables**: Real-time knowledge integration
3. **Cross-pollination**: Same note, different interpretations
4. **Works within ACP**: No protocol violations

**CLAUDE.md is NOT a workaround** - it's the **correct architecture** for providing space-specific context to Claude when using ACP.

### System Prompt Customization

**Answer to Original Question**:

> "Can we manually adjust the system prompt instead of defaulting to CLAUDE.md behavior?"

**In ACP**: No direct system prompt parameter exists. CLAUDE.md prepended to user messages is the **correct pattern**.

**Alternative**: Switch to Claude Agent SDK for true system prompt control, but this is a major refactor that may not be necessary.

### Recommended Path Forward

1. **Keep current architecture** (ACP + CLAUDE.md)
2. **Enhance prompting strategy** (Option 3: Hybrid Approach)
3. **Add UI for CLAUDE.md editing**
4. **Document best practices for users**
5. **Monitor ACP development** for future capabilities
6. **Evaluate Agent SDK** only if ACP becomes limiting

**Bottom Line**: The current system works as designed. CLAUDE.md provides the customization we need within ACP's constraints.

---

**Researched by**: Claude Code Agent  
**Sources**: 
- Anthropic Claude Agent SDK docs
- Agent Client Protocol specification
- Parachute codebase analysis
- ACP protocol schema

**Status**: Research complete - Current architecture validated ✅
