# Session End

Clean up the session and prepare for handoff to the next session.

## Step 1: Review What Was Done

Read `claude-session.md` and compare against what was actually accomplished:
- Which tasks were completed?
- Which acceptance criteria were met?
- What remains unfinished?

Check git status and recent commits to see what changed.

## Step 2: Final Verification

**Run the test suite** to ensure we're leaving things in a good state:

```bash
cd app && flutter test
```

If tests fail:
- Are these new failures from this session's work? Fix them.
- Are these pre-existing failures? Note them.

**Verify the feature works** if applicable:
- Use Playwright MCP for UI changes
- Manual testing for other changes
- Don't skip this step!

## Step 3: Commit Uncommitted Work

Check for uncommitted changes:
```bash
git status
```

If there are changes:
1. Review what's staged/unstaged
2. Ask the user for permission to commit
3. Write a descriptive commit message that captures what was done

**Do not auto-commit without asking.**

## Step 4: Update ROADMAP.md if Needed

If this session completed something significant:
- Mark it as done in ROADMAP.md
- Update the "Current Focus" section if priorities have shifted
- Add to the Decision Log if architectural decisions were made

Only update if there's something meaningful to record - don't update just for the sake of it.

## Step 5: Update Session State

Update `claude-session.md` with final status:
- Mark completed tasks
- Note what remains
- Document any blockers for next session
- Record key decisions or learnings

Example final state:

```markdown
# Session Completed

**Started**: [time]
**Ended**: [time]
**Objective**: [objective]

## Outcome

[Brief summary of what was accomplished]

## Completed
- [x] Task one
- [x] Task two

## Remaining
- [ ] Task three (blocked by X)

## For Next Session
- [specific next steps]
- [any context the next session needs]

## Commits
- abc1234: [commit message]
- def5678: [commit message]
```

## Step 6: Summary for User

Provide a clear summary:
1. **What was done** - List of accomplishments
2. **What's verified** - Confirmation that it works
3. **What remains** - Unfinished work, if any
4. **Blockers** - Anything preventing progress
5. **Next steps** - What the next session should tackle

## Reminders

- **Don't rush the ending** - A clean handoff saves time next session
- **Commit descriptively** - Future sessions will read these commits
- **Be honest about status** - If something isn't done, say so
- **Verification matters** - "It compiles" is not the same as "it works"
