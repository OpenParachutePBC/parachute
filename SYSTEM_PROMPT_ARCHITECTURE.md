# System Prompt Architecture

**Date**: November 3, 2025
**Status**: 🚧 Design Phase
**Goal**: Create a layered, flexible system prompt system for Parachute

---

## Philosophy

Parachute is a **thinking companion**, not just a coding assistant. The system prompt should:

- ✅ Be warm, supportive, and focused on augmenting thinking
- ✅ Understand the vault structure and second brain paradigm
- ✅ Support user customization at multiple levels
- ✅ Dynamically incorporate space-specific context
- ✅ Load relevant notes intelligently

**Core Principle**: "Help users think better, not just execute commands"

---

## Multi-Layer Prompt Architecture

### Layer 1: Base Parachute Prompt (Hardcoded Default)

**Purpose**: Core identity and capabilities that apply to ALL Parachute sessions

**Location**: `backend/internal/acp/prompts/base_prompt.go` (or similar)

**Sent via**: `_meta.systemPrompt` in `session/new`

**Content**:

```markdown
You are Parachute, a thoughtful AI companion designed to augment human thinking.

## Your Purpose

You help users build their second brain - a personal knowledge system where:

- Ideas are captured and connected
- Thoughts cross-pollinate across different contexts
- Knowledge grows organically over time

## Your Approach

- **Listen deeply**: Understand context before suggesting actions
- **Think out loud**: Share your reasoning process
- **Connect ideas**: Help users see patterns and relationships
- **Preserve agency**: The user owns their data and decisions
- **Be curious**: Ask clarifying questions when needed

## Environment

- Vault location: ~/Parachute/ (configurable, may vary by user)
- Structure:
  - captures/: Voice recordings and notes (source of truth)
  - spaces/: Contextual work areas with their own focus
- Current working directory: Vault root
- All data is local-first and user-owned

## Capabilities

- Read and analyze notes from captures/
- Access space-specific context via CLAUDE.md files
- Link notes to spaces for contextualized retrieval
- Use tools to help organize and explore knowledge
- Track note metadata in space.sqlite databases

## Guidelines

- Respect the vault structure - it's designed for portability
- Notes can belong to multiple spaces (cross-pollination)
- Each space has its own perspective on the same underlying notes
- File operations should align with the user's organization system
- When uncertain, ask rather than assume
```

**Decision**: Should this live in code or in a file?

**Option A**: Hardcoded in Go

- Pro: Always available, versioned with code
- Con: Requires rebuild to change

**Option B**: Embedded as `assets/default_prompt.md`

- Pro: Can update without rebuild
- Con: Need to handle missing file

**Recommendation**: Start with **Option A** (hardcoded), add **Option B** later for flexibility

---

### Layer 2: User Global Customization (PARACHUTE.md)

**Purpose**: User's personal additions/modifications to base behavior

**Location**: `~/Parachute/PARACHUTE.md` (optional)

**Sent via**: `_meta.systemPrompt.append` in `session/new`

**Behavior**:

- If exists: Append to base prompt
- If missing: Skip (use base only)
- User-editable for personal preferences

**Example content**:

```markdown
# My Personal Preferences

## Communication Style

- Keep responses concise unless I ask for detail
- Use analogies from systems thinking when explaining concepts
- Don't use emojis unless I specifically request them

## Domain Context

I'm a researcher focusing on:

- Regenerative agriculture
- Complex systems
- Community organizing

When I mention these topics, you can assume familiarity with core concepts.

## Workflow Preferences

- When I'm brainstorming, prioritize connecting ideas over organization
- When I'm in "review" mode, focus on finding patterns and gaps
- Suggest tags based on my existing taxonomy (see tags below)

## Common Tags

#regeneration #farming #systems-thinking #community #research #personal
```

**This allows**: Users to "teach" Parachute their preferences over time

---

### Layer 3: Space Context (SPACE.md)

**Purpose**: Context specific to the current space/conversation

**Location**: `~/Parachute/spaces/{space-name}/SPACE.md`

**Sent via**: Prepended to user message (NOT via \_meta.systemPrompt)

**Why user message instead of system**:

- Allows dynamic variable resolution: `{{note_count}}`, `{{recent_tags}}`
- Can be different per conversation even in same session
- User can edit mid-conversation and see changes immediately
- **Agent-agnostic**: Works with any AI assistant, not just Claude

**Naming rationale**:

- `SPACE.md` is more generic and descriptive than `CLAUDE.md`
- Better compatibility with other AI agents/tools
- Clearer purpose: "This file defines the space's context"

**Current behavior**: ✅ Already implemented (as CLAUDE.md, needs renaming)

**Example content**:

```markdown
# Research Projects Space

This space tracks active research projects and related notes.

## Current Projects

- {{active_projects}}

## Linked Notes

This space has {{note_count}} linked notes.

Recent topics: {{recent_tags}}

## Guidelines for this Space

- Connect new insights to existing projects
- Tag with relevant research themes
- Suggest relationships between ideas
- Help identify gaps in current research
```

---

### Layer 4: Dynamic Context Injection (Relevant Notes)

**Purpose**: Automatically include relevant notes based on conversation context

**Status**: 🚧 Planned (related to space.sqlite work)

**Sent via**: Prepended to user message, before Space CLAUDE.md

**Triggered by**:

- User mentions a tag: `#regeneration` → Load notes tagged with regeneration
- User asks about a topic: "What did I say about farming?" → Semantic search
- Conversation context: Ongoing discussion → Related notes

**Example injection**:

```markdown
## Relevant Notes from this Space

### Note: 2025-10-26_00-00-17.md

**Tags**: #regeneration #farming
**Linked**: 2 weeks ago
**Context**: "Ideas about soil health in urban environments"

[First 200 chars of note content...]

---

### Note: 2025-10-15_14-30-22.md

**Tags**: #systems-thinking #farming
**Linked**: 1 month ago
**Context**: "How feedback loops work in agricultural systems"

[First 200 chars of note content...]

---
```

**Implementation notes**:

- Keep under token budget (e.g., max 3-5 notes)
- Prioritize by recency + relevance
- Include space-specific context (tags, linked date)
- Allow user to disable per-space

---

## Full Prompt Assembly Flow

### At Session Creation (`session/new`)

```
1. Load base Parachute prompt (hardcoded or from assets)
2. Check for ~/Parachute/PARACHUTE.md
3. If exists, read and append
4. Send to ACP via _meta.systemPrompt
```

**Result**: Claude gets foundational Parachute identity + user preferences

**Go implementation**:

```go
func (c *ACPClient) NewSession(workingDir string, mcpServers []MCPServer) (string, error) {
    // Build system prompt
    systemPrompt := buildSystemPrompt(workingDir)

    params := NewSessionParams{
        Cwd:        workingDir,
        McpServers: mcpServers,
        Meta: &SessionMeta{
            SystemPrompt: systemPrompt,
        },
    }

    result, err := c.jsonrpc.Call("session/new", params)
    // ...
}

func buildSystemPrompt(vaultRoot string) interface{} {
    // Start with base prompt
    prompt := BASE_PARACHUTE_PROMPT

    // Check for user's PARACHUTE.md
    parachuteMDPath := filepath.Join(vaultRoot, "PARACHUTE.md")
    if content, err := os.ReadFile(parachuteMDPath); err == nil {
        // Append user's customization
        return map[string]string{
            "append": prompt + "\n\n---\n\n# User Customization\n\n" + string(content),
        }
    }

    // No user customization, use base only
    return prompt
}
```

---

### At Each Message (`session/prompt`)

```
1. Get space from conversation
2. Check for relevant notes (Layer 4) - if enabled
3. Read space's CLAUDE.md (Layer 3)
4. Resolve variables: {{note_count}}, {{recent_tags}}, etc.
5. Assemble context message:
   [Relevant Notes]
   ---
   [Space CLAUDE.md with resolved variables]
   ---
   [User's actual message]
6. Send to ACP
```

**Current implementation**: ✅ Parts of this exist in `buildPromptWithContext()`

**Needs enhancement**: Dynamic note loading (Layer 4)

---

## Token Budget Management

With multiple layers, we need to be mindful of token usage:

### Budget Allocation (Example for ~4K context)

- Base Parachute prompt: ~500 tokens
- User PARACHUTE.md: ~300 tokens (max)
- Space CLAUDE.md: ~400 tokens (with variables)
- Relevant notes: ~800 tokens (3-5 notes)
- Conversation history: ~1000 tokens
- User message: ~200 tokens
- **Total input**: ~3200 tokens
- **Reserve for response**: ~2000 tokens

### Strategies

1. **Truncation**: Limit PARACHUTE.md to first N chars
2. **Summarization**: Summarize old conversation history
3. **Smart note selection**: Only load highly relevant notes
4. **User control**: Allow disabling layers per-space

---

## User Experience Considerations

### Discoverability

**How users learn about customization**:

1. **First-time setup**: Onboarding explains PARACHUTE.md
2. **Settings UI**: "Customize Parachute behavior" → Opens PARACHUTE.md
3. **In-app help**: "How to customize Parachute's responses"
4. **Default template**: Create PARACHUTE.md with commented examples

### Mental Model

**Users should understand**:

- PARACHUTE.md = "How Parachute should behave everywhere"
- Space CLAUDE.md = "What Parachute should know about THIS space"
- Both are plain text files they can edit
- Changes take effect on next message (PARACHUTE.md) or immediately (CLAUDE.md)

### Feedback Loop

**Show users what context is being used**:

- Settings → "View current system prompt" (debugging)
- Message metadata: "Using X notes, Y tokens of context"
- Conversation panel: "Context from: PARACHUTE.md + SPACE.md + 3 notes"

---

## Implementation Phases

### Phase 1: Foundation (Current Sprint)

- [x] Fix double-loading issue (DONE)
- [ ] Implement base Parachute prompt (hardcoded)
- [ ] Add PARACHUTE.md loading
- [ ] Update `session/new` to send custom system prompt
- [ ] Test multi-layer prompt assembly

### Phase 2: Dynamic Context (Next Sprint)

- [ ] Implement relevant note detection
- [ ] Add note injection to `buildPromptWithContext()`
- [ ] Create token budget manager
- [ ] Add user controls for context layers

### Phase 3: UX Polish

- [ ] Onboarding for PARACHUTE.md
- [ ] Settings UI for editing PARACHUTE.md
- [ ] Context visibility in UI
- [ ] Default PARACHUTE.md template

### Phase 4: Advanced Features

- [ ] Semantic search for relevant notes
- [ ] Conversation context tracking
- [ ] Auto-suggest tags based on space patterns
- [ ] Export/import prompt templates

---

## Open Questions

1. **Should base prompt mention Claude Code at all?**
   - Pro: Accurate (we use Claude Code SDK)
   - Con: Confusing for users who don't know what that is
   - Recommendation: Don't mention, focus on Parachute identity

2. **How do we handle prompt updates?**
   - Versioning in PARACHUTE.md?
   - Migration guide when base prompt changes?

3. **Should spaces be able to OVERRIDE base prompt?**
   - Currently: Only append/add context
   - Future: Allow spaces to say "ignore global preferences in this space"?

4. **How much of Layer 4 should be automatic vs. user-triggered?**
   - Auto-load based on tags mentioned?
   - Or require explicit: "Load notes about X"?

---

## Next Steps

1. **Design base Parachute prompt** (draft the actual content)
2. **Implement PARACHUTE.md loading** in backend
3. **Update NewSession to send custom system prompt**
4. **Create default PARACHUTE.md template** for users
5. **Document the system in user-facing docs**

---

**Status**: Ready for implementation
**Blocking**: None - can proceed immediately
**Impact**: High - defines core UX of Parachute
