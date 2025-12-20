# Session Start: $ARGUMENTS

Initialize a focused development session with clear objectives and context.

## Step 1: Understand the Objective

The user wants to work on: **$ARGUMENTS**

If no objective was provided, ask the user what they want to accomplish this session before proceeding.

## Step 2: Sync with Origin Main

**Ensure we're starting fresh from the latest main branch:**

1. **Check for uncommitted work** first:
   ```bash
   git --no-pager status
   ```
   If there are uncommitted changes, ask the user how to handle them (stash, commit, or discard).

2. **Fetch latest from origin:**
   ```bash
   git fetch origin
   ```

3. **Switch to main and pull latest:**
   ```bash
   git checkout main && git pull origin main
   ```

4. **Create a new feature branch** (if the objective suggests a feature name):
   ```bash
   git checkout -b feature/[descriptive-name]
   ```
   Ask the user for a branch name if the objective doesn't suggest one clearly.

## Step 3: Gather Context

**Read recent git history** to understand what's been happening:
```bash
git --no-pager log --oneline -20
```

**Check for leftover session state** - if `claude-session.md` exists at the repo root, read it to see if there was an interrupted session. If starting a new feature unrelated to the previous session, consider archiving or removing the old session file.

**Read ROADMAP.md** to understand current project focus and priorities.

## Step 4: Run Baseline Tests

Run the test suite to verify we're starting from a clean state:
```bash
cd app && flutter test
```

If tests fail, note this - we may need to fix them before proceeding, or they may be pre-existing failures.

## Step 5: Create Session State

Create or update `claude-session.md` in the repo root with:

```markdown
# Current Session

**Started**: [current date/time]
**Objective**: [the objective from $ARGUMENTS]

## Context

[Relevant context from git history and ROADMAP - what recent work relates to this objective?]

## Tasks

[Break down the objective into concrete, actionable tasks]

1. [ ] Task one
2. [ ] Task two
3. [ ] ...

## Acceptance Criteria

[How do we know this objective is complete? Be specific.]

- [ ] Criterion one
- [ ] Criterion two

## Verification Plan

[How will we verify the work actually works? Be specific about what to test.]

- [ ] Run unit tests: `cd app && flutter test`
- [ ] Manual verification: [specific steps]
- [ ] Playwright MCP: [specific UI flows to test, if applicable]

## Notes

[Space for observations, blockers, decisions made during the session]
```

## Step 6: Output the Plan

Summarize for the user:
1. What recent work is relevant
2. The breakdown of tasks
3. How we'll verify it works
4. Any concerns or blockers identified

## Reminders

- **One feature at a time** - Don't try to do everything at once
- **Test as you go** - Don't wait until the end to verify
- **Update session state** - Keep `claude-session.md` current as tasks complete
- **Use TodoWrite** - Track tasks in the todo list for visibility
- **Verify before "done"** - Use Playwright MCP or manual testing to confirm changes work
