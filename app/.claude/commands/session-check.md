# Session Check

Mid-session coherence check. Make sure we're on track and verifying our work.

## Step 1: Review Session State

Read `claude-session.md` from the repo root to recall:
- What is the objective?
- What tasks were planned?
- What's the verification plan?

If `claude-session.md` doesn't exist, ask the user what they're working on and suggest running `/session-start` to establish context.

## Step 2: Progress Check

Review what's been done so far this session:
- Check git status for uncommitted changes
- Review the TodoWrite list
- Compare against the tasks in `claude-session.md`

Ask yourself:
- **Am I on track?** Am I working toward the stated objective?
- **Any scope creep?** Have I drifted into unrelated work?
- **Tasks current?** Does my todo list match reality?

## Step 3: Verification Check

**Have I been testing my changes?**

- Did I run tests after recent changes?
- Did I manually verify the feature works?
- For UI changes: Did I use Playwright MCP to verify?

If verification has been skipped, **do it now**:

```bash
cd app && flutter test
```

For UI changes, use Playwright MCP to:
1. Launch the app in web mode: `cd app && flutter run -d chrome --web-port=8090`
2. Navigate to the relevant screen
3. Test the actual user flow
4. Take screenshots if helpful

## Step 4: Update Session State

Update `claude-session.md` with:
- Tasks completed (check them off)
- Any new tasks discovered
- Notes on blockers or decisions
- Verification results

## Step 5: Course Correct if Needed

If we've drifted off track:
- Acknowledge it
- Decide whether to continue the tangent or return to the objective
- Update session state to reflect the decision

## Output

Summarize:
1. Progress against objective (X of Y tasks done)
2. Verification status (tested? what was verified?)
3. Any concerns or blockers
4. Recommendation: continue, pivot, or wrap up

## Reminders

- **It's okay to pivot** - Sometimes we discover the objective needs to change
- **Don't skip verification** - Actually test the changes
- **Small commits** - If you have working changes, consider committing
- **Ask for help** - If stuck, surface it to the user
