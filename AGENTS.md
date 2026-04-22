Monorepo managed with Turborepo.

Git Workflow Instructions
Use git worktrees for all development: every feature, fix, or active task must be worked on in its own worktree (git worktree add ../podsync-<branch-name> <branch-name>), never directly in the main worktree.
Follow Gitflow strictly:

main → stable production only.
develop → continuous integration; base for all new work.
feature/<task-id>-<short-desc> → one branch per task (e.g. feature/TASK-001-monorepo-setup), branched from develop.
release/<version> → release preparation, branched from develop.
hotfix/<desc> → branched from main, merged back into both main and develop.

Never commit directly to main or develop. Open a PR to develop when a feature is complete.

## Key documentation
- `Docs/TDD_Resume.md` — dense operational summary: auth matrix, chunk protocol, rate limits, session lifecycle, data model
