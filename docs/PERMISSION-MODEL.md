# Permission Model Design

**Status**: Backend Complete, UI Pending
**Date**: January 4, 2026
**Implementation**: See [PERMISSION-IMPLEMENTATION.md](./PERMISSION-IMPLEMENTATION.md) for details

## Overview

This document describes a progressive permission model for Parachute Chat that allows the AI agent to work within `~/Parachute` as its default working directory while maintaining safety through just-in-time permission grants.

## Goals

1. **Natural workflow**: Start conversations without predicting what access you'll need
2. **Safe by default**: New sessions can't read/write arbitrary files
3. **Progressive trust**: Grant permissions as needed during conversation
4. **Persistent per-session**: Permissions last for the session lifetime
5. **Power user escape hatch**: Trust mode for full access

## Architecture

### Default Capabilities (No Permission Required)

| Tool | Access | Notes |
|------|--------|-------|
| **MCP: parachute** | Always | search_sessions, search_journals, get_session, etc. |
| **WebSearch** | Always | External web search |
| **WebFetch** | Always | Fetch URLs |
| **Bash: ls, pwd, tree** | Always | Read-only directory exploration |
| **Write: Chat/artifacts/** | Always | Safe sandbox for agent-created files |

### Gated Capabilities (Require Permission)

| Tool | Permission Type | Example Grant |
|------|-----------------|---------------|
| **Read** | `read: ["Blogs/**/*"]` | Read files in Blogs folder |
| **Write** | `write: ["Projects/foo/*"]` | Write to specific project |
| **Edit** | Same as write | Editing requires write permission |
| **Bash** | `bash: true` or `bash: ["git", "npm"]` | Full or allowlisted commands |
| **All** | `trust_mode: true` | Bypass all permission checks |

## Data Model

### Session Permissions (stored in SQLite metadata JSON)

```json
{
  "permissions": {
    "read": [
      "Blogs/**/*",
      "Projects/my-app/**/*"
    ],
    "write": [
      "Chat/artifacts/*",
      "Projects/my-app/src/**/*"
    ],
    "bash": ["git", "npm", "pnpm"],
    "trust_mode": false
  }
}
```

### Global Deny List (~/.parachute/.parachuteignore)

Files/patterns that are NEVER accessible, even in trust mode:

```gitignore
# Secrets
.env
.env.*
**/credentials/**
**/*.key
**/*.pem

# System
.git/
node_modules/

# Parachute internals
.parachute/
```

## User Experience

### Permission Grant Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ User: "Can you read my blog post about productivity?"           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Agent attempts: Read("Blogs/productivity.md")                   │
│ → Permission check fails (no read access to Blogs/)             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ UI: Permission Request                                          │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ 🔐 Read Access Requested                                    │ │
│ │                                                             │ │
│ │ The assistant wants to read: Blogs/productivity.md          │ │
│ │                                                             │ │
│ │ [This file only]  [Blogs/ folder]  [Full vault]  [Deny]    │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ (User clicks "Blogs/ folder")
┌─────────────────────────────────────────────────────────────────┐
│ Session permissions updated:                                    │
│   read: ["Blogs/**/*"]                                          │
│                                                                 │
│ Agent can now read any file in Blogs/                          │
│ Future reads in Blogs/ don't require new prompts               │
└─────────────────────────────────────────────────────────────────┘
```

### Permission Management UI (Settings)

```
┌─────────────────────────────────────────────────────────────────┐
│ Session Permissions                                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ Read Access:                                                    │
│   ✓ Blogs/**/*                              [Revoke]           │
│   ✓ Daily/journals/*                        [Revoke]           │
│                                                                 │
│ Write Access:                                                   │
│   ✓ Chat/artifacts/*                        [Built-in]         │
│   ✓ Projects/my-app/src/**/*                [Revoke]           │
│                                                                 │
│ Bash Commands:                                                  │
│   ✓ git, npm                                [Revoke all]       │
│                                                                 │
│ ─────────────────────────────────────────────────────────────  │
│                                                                 │
│ [ ] Trust Mode (skip all permission prompts)                   │
│     ⚠️ Gives full access to your vault                         │
│                                                                 │
│ [Grant Read: ___________]  [Grant Write: ___________]          │
└─────────────────────────────────────────────────────────────────┘
```

## Implementation Plan

### Phase 1: Foundation

1. **Add permissions field to Session model**
   - Update `base/parachute/models/session.py`
   - Add `SessionPermissions` Pydantic model
   - Store in existing `metadata` JSON field

2. **Create permission checking utility**
   - `base/parachute/lib/permissions.py`
   - `check_read(session, path) -> bool`
   - `check_write(session, path) -> bool`
   - `check_bash(session, command) -> bool`
   - Glob pattern matching with `fnmatch`

3. **Load .parachuteignore**
   - Parse on server startup
   - Always deny these patterns regardless of session permissions

### Phase 2: Tool Interception

4. **Modify orchestrator to filter tools**
   - Start with restricted tool set
   - When permission granted, dynamically add tools

5. **Permission request protocol**
   - New SSE event type: `permission_request`
   - Client responds with `permission_grant` or `permission_deny`
   - Server updates session and retries tool call

### Phase 3: Flutter UI

6. **Permission request dialog**
   - `chat/lib/features/chat/widgets/permission_dialog.dart`
   - Options: [This file] [This folder] [Full vault] [Deny]

7. **Permission management in settings**
   - View current session permissions
   - Revoke individual permissions
   - Trust mode toggle

### Phase 4: Polish

8. **Bash command allowlist**
   - Default safe commands: `ls`, `pwd`, `tree`, `cat`, `head`, `tail`
   - Grantable: `git`, `npm`, `pnpm`, etc.
   - Never allowed: `rm -rf`, `sudo`, etc.

9. **Persistence across session resume**
   - Permissions stored in SQLite, restored on resume

10. **Audit log** (optional)
    - Track what was accessed when
    - Stored in `Chat/artifacts/.access-log.jsonl`

## API Changes

### New SSE Events

```typescript
// Server → Client: Request permission
{
  "type": "permission_request",
  "id": "req-123",
  "tool": "Read",
  "path": "Blogs/productivity.md",
  "suggested_grants": [
    { "scope": "file", "pattern": "Blogs/productivity.md" },
    { "scope": "folder", "pattern": "Blogs/**/*" },
    { "scope": "vault", "pattern": "**/*" }
  ]
}

// Client → Server: Grant/Deny (via API call)
POST /api/chat/sessions/{id}/permissions
{
  "request_id": "req-123",
  "action": "grant",
  "scope": "folder",
  "pattern": "Blogs/**/*"
}
```

### New API Endpoints

```
GET  /api/chat/sessions/{id}/permissions     # Get current permissions
POST /api/chat/sessions/{id}/permissions     # Grant permission
DELETE /api/chat/sessions/{id}/permissions   # Revoke permission
POST /api/chat/sessions/{id}/trust           # Enable/disable trust mode
```

## Default Working Directory Change

As part of this work, change the default `cwd` from `~/Parachute/Chat` to `~/Parachute`:

1. Update `base/parachute/config.py` default
2. Update `base/parachute/core/orchestrator.py`
3. Existing sessions keep their `working_directory`; new sessions get `~/Parachute`

## Open Questions

1. **Should permissions persist across related sessions?**
   - If I continue a session, should it inherit permissions?
   - Proposal: Yes, continued sessions inherit parent permissions

2. **What about external working directories?**
   - When `cwd` is `/Users/me/some-project`, permissions are relative to that
   - Trust mode still respects global deny list

3. **Rate limiting permission requests?**
   - Prevent agent from spamming permission dialogs
   - Maybe: max 3 denials before agent must ask user differently

## Security Considerations

- **Deny list is absolute**: Even trust mode can't access `.env` files
- **Path traversal protection**: Normalize paths, reject `../` attempts
- **Bash sandboxing**: Consider using a restricted shell or container for bash
- **Audit logging**: Optional but recommended for enterprise use

---

## Summary

This permission model enables Parachute Chat to be a true vault assistant while maintaining user control. The key insight is that **permissions should be granted when needed, not predicted upfront**—matching how thinking actually works.
