---
name: pull
description: Pull latest origin/main into the current branch and resolve merge conflicts.
version: 1.0.0
author: Conductor
license: Apache-2.0
prerequisites:
  commands: [git]
metadata:
  hermes:
    tags: [git, pull, merge, workflow]
---
# Pull

## When to Use

When the branch needs to sync with origin/main, or push was rejected due to
non-fast-forward.

## Steps

1. Verify git status is clean — commit or stash changes first.
2. Enable rerere for conflict memory:
   ```bash
   git config rerere.enabled true
   git config rerere.autoupdate true
   ```
3. Fetch latest refs:
   ```bash
   git fetch origin
   ```
4. Sync remote feature branch first:
   ```bash
   git pull --ff-only origin $(git branch --show-current)
   ```
5. Merge origin/main:
   ```bash
   git -c merge.conflictstyle=zdiff3 merge origin/main
   ```
6. If conflicts appear:
   - Inspect context before editing — understand both sides.
   - Prefer the feature branch's intent but incorporate main's structural changes.
   - `git add <files>` then `git merge --continue`.
7. Run project validation (tests, linting) after merge.
8. Summarize: which files conflicted, how resolved, any assumptions made.

## Pitfalls

- Never blindly accept "ours" or "theirs" for all conflicts.
- Don't rebase shared branches — use merge.
- If merge is too complex, ask for guidance before proceeding.
