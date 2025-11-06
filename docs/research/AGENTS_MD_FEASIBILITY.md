# AGENTS.md Feasibility Research: Custom System Prompts

**Date**: November 3, 2025  
**Question**: Can we use AGENTS.md instead of CLAUDE.md and have more control over system prompts, or is that too messy given the Claude Agent SDK setup?

---

## Executive Summary

**Short Answer**: ✅ **Yes, it's feasible** - but requires custom implementation in Parachute

**Key Findings**:

1. **Claude SDK filename is hardcoded** - Only recognizes `CLAUDE.md`, not custom names
2. **Multiple system prompt methods exist** - 4 different approaches with different tradeoffs
3. **Parachute has control** - We spawn the ACP process, can pass custom prompts
4. **Best approach**: Read `AGENTS.md` ourselves, pass via `systemPrompt` parameter
5. **Complexity**: Medium - requires custom logic but achieves desired flexibility

---

## 1. Claude Agent SDK System Prompt Methods

### Method 1: CLAUDE.md Files (File-Based, Auto-Discovery)

**How It Works**:
```typescript
query({
  prompt: "Your prompt",
  options: {
    systemPrompt: { type: "preset", preset: "claude_code" },
    settingSources: ["project"]  // Tells SDK to load CLAUDE.md
  }
})
```

**SDK Behavior**:
- Automatically searches for `CLAUDE.md` in specific locations:
  - `.claude/CLAUDE.md` (project)
  - `CLAUDE.md` (project root)
  - `~/.claude/CLAUDE.md` (user global)
- **Filename is hardcoded** - cannot use `AGENTS.md` or custom name
- Requires `settingSources: ["project"]` to enable

**Limitations**:
- ❌ Cannot use custom filename (requested feature, not implemented)
- ❌ Hardcoded to "CLAUDE.md"
- ❌ Not configurable via API

**Source**: GitHub Issue #5292 - "Custom Context File Name" requested but not implemented

### Method 2: Output Styles (Reusable Presets)

**How It Works**:
```typescript
// Create a style file
await writeFile(
  join(homedir(), ".claude", "output-styles", "code-reviewer.md"),
  `---
name: Code Reviewer
description: Thorough code review
---

You are an expert code reviewer...`
);

// Use it
query({
  prompt: "Review this code",
  options: {
    systemPrompt: {
      type: "output_style",
      outputStyle: "code-reviewer"
    }
  }
})
```

**Characteristics**:
- ✅ Reusable across projects
- ✅ Centralized in `~/.claude/output-styles/`
- ✅ Can have multiple styles
- ❌ Still in a predefined location
- ❌ Not per-space customizable

### Method 3: Append to Preset (Hybrid)

**How It Works**:
```typescript
query({
  prompt: "Help with Python",
  options: {
    systemPrompt: {
      type: "preset",
      preset: "claude_code",
      append: "Always include type hints and docstrings."
    }
  }
})
```

**Characteristics**:
- ✅ Keeps Claude Code's built-in tools
- ✅ Adds custom instructions
- ✅ Per-session customization
- ❌ Not file-based (must be in code)
- ❌ Can't replace base prompt

### Method 4: Custom System Prompt (Full Control)

**How It Works**:
```typescript
const customPrompt = `You are a Python specialist.

Guidelines:
- Write clean, documented code
- Use type hints
- Follow PEP 8`;

query({
  prompt: "Create a data pipeline",
  options: { systemPrompt: customPrompt }
})
```

**Characteristics**:
- ✅ Complete control
- ✅ Any content you want
- ✅ Can load from any file
- ❌ Loses Claude Code's built-in tools
- ❌ Must manage yourself

**This is the key method for AGENTS.md!**

---

## 2. Can We Use AGENTS.md? Analysis

### The Problem with Claude SDK

**Hardcoded Filename**:
```typescript
// Inside Claude Agent SDK (hypothetical)
function findClaudeMD(cwd: string): string | null {
  const paths = [
    join(cwd, '.claude', 'CLAUDE.md'),
    join(cwd, 'CLAUDE.md'),
    join(homedir(), '.claude', 'CLAUDE.md')
  ];
  // ... searches these exact paths
}
```

**What This Means**:
- SDK will never automatically load `AGENTS.md`
- Filename "CLAUDE.md" is baked into the SDK
- Community has requested custom filenames, not implemented yet

### Parachute's Current Architecture

**How Parachute Spawns ACP**:
```go
// backend/internal/acp/process.go
func SpawnACP(apiKey string) (*ACPProcess, error) {
    cmd := exec.Command("npx", "@zed-industries/claude-code-acp")
    cmd.Env = append(os.Environ(), "ANTHROPIC_API_KEY="+apiKey)
    // Start process, connect stdin/stdout for JSON-RPC
}
```

**Current System Prompt Approach**:
```go
// backend/internal/api/handlers/message_handler.go
func (h *MessageHandler) buildPromptWithContext(...) string {
    // Read CLAUDE.md
    claudeMD, _ := h.spaceService.ReadClaudeMD(spaceObj)
    
    // Resolve variables
    resolvedClaudeMD, _ := h.contextService.ResolveVariables(claudeMD, spaceObj.Path)
    
    // Prepend to user message
    prompt := resolvedClaudeMD + "\n\n---\n\n" + userMessage
    
    return prompt
}
```

**Key Insight**: Parachute **already reads and processes files manually**!

### The Solution: Keep Control in Parachute ✅

**Instead of relying on SDK's auto-discovery**, do what we're already doing:

```go
// Read ANY filename we want
agentsMD, err := h.spaceService.ReadAgentsMD(spaceObj)  // AGENTS.md instead

// Resolve variables
resolved, _ := h.contextService.ResolveVariables(agentsMD, spaceObj.Path)

// Pass to user message OR pass as systemPrompt if using SDK directly
```

**Why This Works**:
- ✅ We control the file reading
- ✅ Can use any filename (AGENTS.md, SYSTEM.md, etc.)
- ✅ Works with current architecture
- ✅ No dependency on SDK's file discovery

---

## 3. Implementation Options

### Option A: Keep Current Architecture (Prepend to Message) ✅

**Current Approach**:
```go
// Read AGENTS.md instead of CLAUDE.md
agentsMD := readFile(spaceObj.Path + "/AGENTS.md")
resolved := resolveVariables(agentsMD)

// Prepend to message
prompt := resolved + "\n\n---\n\n" + userMessage

// Send via ACP
acpClient.SessionPrompt(sessionID, prompt)
```

**Advantages**:
- ✅ No architecture changes
- ✅ Works with current ACP setup
- ✅ Simple rename: CLAUDE.md → AGENTS.md
- ✅ Variable resolution still works
- ✅ Cross-agent compatible (works with Goose too)

**Disadvantages**:
- ❌ Not a "true" system prompt (part of user message)
- ❌ Uses token budget from user messages
- ❌ Less clean than SDK's systemPrompt

**Verdict**: **Easiest, works perfectly, minimal changes**

### Option B: Use Claude SDK's Custom SystemPrompt 🎯

**If we use claude-code-acp adapter directly**:

The adapter would call Claude SDK internally. We can't control its `systemPrompt` parameter from outside without modifying the adapter.

**BUT** - we could create our own adapter:

```typescript
// parachute-claude-acp (custom adapter)
import { query, ClaudeAgentOptions } from 'claude-agent-sdk';

// Read AGENTS.md from the space
const agentsMD = fs.readFileSync(`${spacePath}/AGENTS.md`, 'utf8');

// Resolve variables (implement in TypeScript or call Go service)
const resolved = resolveVariables(agentsMD);

// Use SDK's systemPrompt parameter
for await (const message of query({
  prompt: userMessage,
  options: {
    systemPrompt: resolved  // Our custom content!
  }
})) {
  // Stream to ACP
}
```

**Advantages**:
- ✅ True system prompt (cached separately by Anthropic)
- ✅ Cleaner architecture
- ✅ Uses SDK properly
- ✅ Can still use any filename

**Disadvantages**:
- ❌ Need to maintain custom TypeScript adapter
- ❌ More complex than current approach
- ❌ Adds TypeScript dependency to project
- ❌ Need to reimplement variable resolution in TS

**Verdict**: **Clean but complex - only if we want SDK features**

### Option C: Hybrid - Read AGENTS.md, Set via Environment 🤔

**Idea**: Pass system prompt via environment variable

```go
// Read AGENTS.md
agentsMD := readFile(spaceObj.Path + "/AGENTS.md")
resolved := resolveVariables(agentsMD)

// Spawn ACP with custom env
cmd := exec.Command("npx", "@zed-industries/claude-code-acp")
cmd.Env = append(os.Environ(),
    "ANTHROPIC_API_KEY="+apiKey,
    "CUSTOM_SYSTEM_PROMPT="+resolved,  // Pass our content
)
```

**Then modify adapter** to read this env var... but we don't control the adapter source.

**Verdict**: ❌ **Not feasible - can't modify official adapter**

### Option D: Fork claude-code-acp Adapter ⚠️

**Create**: `@parachute/claude-code-acp`

**Modify** to:
1. Accept system prompt via environment variable
2. Read `AGENTS.md` instead of `CLAUDE.md`
3. Custom variable resolution

**Advantages**:
- ✅ Full control
- ✅ True system prompts
- ✅ Custom filename support

**Disadvantages**:
- ❌ Maintain a fork forever
- ❌ Miss upstream updates
- ❌ Complex setup for users
- ❌ Not worth it for this feature

**Verdict**: ❌ **Overkill - not recommended**

---

## 4. Multi-Agent Considerations

### Different Agents, Different Approaches

**Claude Code** (via claude-code-acp):
- Expects `CLAUDE.md` (if using SDK's settingSources)
- Can use custom systemPrompt (if we modify approach)

**Goose** (native ACP):
- Uses `.goosehints` for context
- No CLAUDE.md support
- Different configuration system

**Future Agents**:
- May have their own context files
- Different conventions

### Universal Solution: AGENTS.md ✅

**Proposed Architecture**:
```
~/Parachute/spaces/my-space/
├── AGENTS.md              # Universal, all agents
├── .goosehints           # Goose-specific (optional)
├── CLAUDE.md             # Deprecated, but supported
└── space.sqlite
```

**Backend Logic**:
```go
func (h *MessageHandler) getSpaceContext(spaceObj *space.Space) string {
    // Priority: AGENTS.md > CLAUDE.md
    if fileExists(spaceObj.Path + "/AGENTS.md") {
        content := readFile("AGENTS.md")
        return h.contextService.ResolveVariables(content, spaceObj.Path)
    }
    
    // Fallback to CLAUDE.md for backwards compatibility
    if fileExists(spaceObj.Path + "/CLAUDE.md") {
        content := readFile("CLAUDE.md")
        return h.contextService.ResolveVariables(content, spaceObj.Path)
    }
    
    return ""
}
```

**Agent-Specific Handling**:
```go
func (h *MessageHandler) buildPrompt(agent, spaceContext, userMessage string) string {
    switch agent {
    case "claude":
        // Claude gets space context prepended
        return spaceContext + "\n\n---\n\n" + userMessage
        
    case "goose":
        // Goose handles .goosehints automatically
        // Just send the user message
        return userMessage
        
    default:
        // Other agents: prepend context
        return spaceContext + "\n\n---\n\n" + userMessage
    }
}
```

**Why This Works**:
- ✅ One file for all agents
- ✅ Agent-specific handling where needed
- ✅ Backwards compatible with CLAUDE.md
- ✅ Future-proof for new agents

---

## 5. Recommended Implementation

### Phase 1: Rename Support (Immediate) ✅

**Changes**:
1. Update `space.Service` to read `AGENTS.md` (with CLAUDE.md fallback)
2. Update variable resolution to work with both
3. No architecture changes needed

**Code**:
```go
// backend/internal/domain/space/service.go
func (s *Service) ReadAgentsMD(space *Space) (string, error) {
    // Try AGENTS.md first
    agentsPath := filepath.Join(space.Path, "AGENTS.md")
    if content, err := os.ReadFile(agentsPath); err == nil {
        return string(content), nil
    }
    
    // Fallback to CLAUDE.md
    claudePath := filepath.Join(space.Path, "CLAUDE.md")
    if content, err := os.ReadFile(claudePath); err == nil {
        return string(content), nil
    }
    
    return "", fmt.Errorf("no AGENTS.md or CLAUDE.md found")
}
```

**Migration Strategy**:
```go
// Auto-migrate on space load
func (s *Service) MigrateToAgentsMD(space *Space) error {
    claudePath := filepath.Join(space.Path, "CLAUDE.md")
    agentsPath := filepath.Join(space.Path, "AGENTS.md")
    
    // If CLAUDE.md exists but AGENTS.md doesn't, copy
    if fileExists(claudePath) && !fileExists(agentsPath) {
        return os.Rename(claudePath, agentsPath)  // or copy
    }
    
    return nil
}
```

### Phase 2: Enhanced System Prompt Control (Future) 🎯

**Once we support multiple agents**, add agent-specific configuration:

```go
// AGENTS.md with agent-specific sections
/*
---
agents:
  claude:
    model: claude-sonnet-4.5-20250514
    mode: code
  goose:
    provider: openai
    model: gpt-4o
---

# Universal Instructions (all agents)

You are helping manage a software engineering project.

## Available Knowledge
- Linked Notes: {{note_count}}
- Recent Topics: {{recent_tags}}

---

# Claude-Specific

When using Claude:
- Prioritize code quality
- Use tools proactively

---

# Goose-Specific

When using Goose:
- Focus on quick iterations
- Prefer concise explanations
*/
```

**Parser**:
```go
type AgentsMDContent struct {
    UniversalPrompt string
    AgentPrompts    map[string]string  // agent -> prompt
    AgentConfig     map[string]map[string]interface{}
}

func ParseAgentsMD(content string) (*AgentsMDContent, error) {
    // Parse frontmatter for config
    // Split by "---" sections for agent-specific
    // Return structured content
}
```

### Phase 3: UI for Editing AGENTS.md ✨

**Feature**: In-app editor for space prompts

```
┌─ Edit Space Prompt ─────────────────────┐
│ Space: Work Projects                    │
│                                         │
│ File: [AGENTS.md ▼]                    │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │ # Work Projects Management          │ │
│ │                                     │ │
│ │ You are a technical PM...           │ │
│ │                                     │ │
│ │ ## Available Knowledge              │ │
│ │ - Notes: {{note_count}}            │ │
│ │ - Topics: {{recent_tags}}          │ │
│ │                                     │ │
│ │ ## Guidelines                       │ │
│ │ - Prioritize by customer impact     │ │
│ │ - Reference past discussions        │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ [Preview Variables] [Save] [Cancel]    │
└─────────────────────────────────────────┘
```

**Benefits**:
- No filesystem access needed
- Live variable preview
- Syntax highlighting
- Template library

---

## 6. Complexity vs. Benefit Analysis

### Complexity Score (1-10)

**Option A: Simple Rename (CLAUDE.md → AGENTS.md)**
- **Complexity**: 2/10
- **Code Changes**: ~50 lines
- **Testing**: Minimal
- **Risk**: Very low
- **Benefit**: High (better naming, multi-agent ready)

**Option B: Custom Adapter**
- **Complexity**: 8/10
- **Code Changes**: ~1000+ lines (new TypeScript project)
- **Testing**: Extensive
- **Risk**: High (maintain fork)
- **Benefit**: Medium (true system prompts)

**Option C: Enhanced Parser (Frontmatter + Sections)**
- **Complexity**: 5/10
- **Code Changes**: ~200 lines
- **Testing**: Moderate
- **Risk**: Medium
- **Benefit**: Very High (agent-specific config)

### Recommended Progression

1. **Week 1**: Simple rename to AGENTS.md ✅
   - Update file reading logic
   - Add CLAUDE.md fallback
   - Test with existing spaces
   
2. **Week 2-3**: Multi-agent support 🎯
   - Add agent selection to conversations
   - Agent-specific prompt handling
   - Test with Claude + Goose

3. **Week 4+**: Enhanced parsing ✨
   - Frontmatter for config
   - Agent-specific sections
   - UI editor for AGENTS.md

---

## 7. Answers to Your Questions

### Q: "Can we use AGENTS.md for everything?"

**A: ✅ YES, absolutely!**

- Claude SDK limitation doesn't affect us
- We already read files manually
- Simple rename of current approach
- Better naming for multi-agent future

### Q: "Being more customizable in system prompts?"

**A: ✅ YES, multiple options:**

1. **Current architecture** (prepend to message)
   - Works perfectly
   - Already customizable (any content, variables)
   - Just use different filename

2. **Enhanced parsing** (frontmatter + sections)
   - Per-agent configuration
   - Universal + agent-specific prompts
   - Medium complexity, high value

3. **Custom adapter** (true system prompts)
   - Maximum control
   - High complexity
   - Only needed for SDK features

### Q: "Would that be too messy given Claude Agent SDK setup?"

**A: ❌ NOT MESSY AT ALL!**

**Key Realization**: We don't use Claude Agent SDK directly - we use the **ACP protocol**.

**What Parachute Does**:
```
Parachute → Spawn claude-code-acp → (adapter uses SDK internally)
```

**What claude-code-acp Does**:
```
ACP Protocol ← adapter → Claude SDK → Claude API
```

**We control**:
- ✅ What we send via ACP
- ✅ What files we read
- ✅ How we build prompts

**We DON'T control**:
- ❌ How adapter calls SDK (unless we fork it)
- ❌ SDK's CLAUDE.md discovery

**But that's fine!** We're not using SDK's file discovery anyway.

---

## 8. Final Recommendation

### ✅ YES, Switch to AGENTS.md

**Reasoning**:
1. **Better naming** - Makes sense for multi-agent future
2. **Zero complexity** - Just rename file reading logic
3. **No SDK conflicts** - We control the reading
4. **Backwards compatible** - Keep CLAUDE.md as fallback
5. **Future-proof** - Foundation for agent-specific config

### Implementation Plan

**Immediate (This Week)**:
```go
// 1. Update service to read AGENTS.md
func (s *Service) ReadSpacePrompt(space *Space) (string, error) {
    // Try AGENTS.md first
    if content, err := os.ReadFile(space.Path + "/AGENTS.md"); err == nil {
        return string(content), nil
    }
    // Fallback to CLAUDE.md
    if content, err := os.ReadFile(space.Path + "/CLAUDE.md"); err == nil {
        return string(content), nil
    }
    return "", nil  // No prompt file
}

// 2. Update message handler
func (h *MessageHandler) buildPromptWithContext(...) string {
    promptFile := h.spaceService.ReadSpacePrompt(spaceObj)
    resolved := h.contextService.ResolveVariables(promptFile, spaceObj.Path)
    return resolved + "\n\n---\n\n" + userMessage
}

// 3. Migration helper
func (s *Service) MigrateToAgentsMD(space *Space) error {
    claudePath := space.Path + "/CLAUDE.md"
    agentsPath := space.Path + "/AGENTS.md"
    
    if fileExists(claudePath) && !fileExists(agentsPath) {
        return os.Rename(claudePath, agentsPath)
    }
    return nil
}
```

**Documentation Updates**:
1. Update CLAUDE.md in docs to AGENTS.md
2. Add migration guide for existing users
3. Update example templates

**Testing**:
- Existing CLAUDE.md files still work
- New AGENTS.md files work
- Variable resolution works with both
- No breaking changes

### Don't Do (Unless Really Needed)

❌ **Don't fork claude-code-acp**
❌ **Don't create custom TypeScript adapter**
❌ **Don't try to configure SDK's settingSources**

**Why**: We don't need SDK features. Our current approach (reading files + prepending to messages) works perfectly and gives us full control.

---

## Conclusion

**Your instinct is correct** - AGENTS.md is better naming and more flexible.

**Implementation is straightforward**:
- Current architecture already gives us control
- Simple file rename logic
- No conflicts with Claude SDK
- Foundation for future agent-specific config

**Recommendation**: ✅ **Do it!**

Benefits far outweigh complexity. We can implement in a few hours and have better naming, multi-agent support, and full customization without fighting against SDK limitations.

---

**Researched by**: Claude Code Agent  
**Sources**:
- Claude Agent SDK documentation
- GitHub issues about custom filenames
- Parachute codebase analysis
- ACP protocol understanding

**Status**: Research complete - AGENTS.md recommended ✅
