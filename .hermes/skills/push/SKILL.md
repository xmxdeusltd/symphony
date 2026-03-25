---
name: push
description: Push current branch to origin and create or update the corresponding pull request.
version: 1.0.0
author: Conductor
license: Apache-2.0
prerequisites:
  commands: [gh, git]
metadata:
  hermes:
    tags: [git, push, pull-request, workflow]
---
# Push

## When to Use

When asked to push, publish updates, or create a pull request.

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth status`).
- On a feature branch (not main).

## Steps

1. Identify current branch and confirm remote state:
   ```bash
   git branch --show-current
   git remote -v
   ```
2. Run any local validation the repo supports before pushing:
   - Check for `Makefile` (run default/test target if available).
   - Check for `package.json` scripts (`npm test`, `npm run lint`).
   - Check for `pytest`, `mix test`, `cargo test`, etc.
   - If no validation tooling found, skip.
3. Push branch to origin with upstream tracking:
   ```bash
   git push -u origin $(git branch --show-current)
   ```
4. If push is rejected (non-fast-forward):
   - Use the `pull` skill to merge origin/main and resolve conflicts.
   - Push again. Use `--force-with-lease` only when history was rewritten.
   - If failure is auth/permissions, stop and surface the error.
5. Ensure a PR exists for the branch:
   - If no PR exists, create one with `gh pr create`.
   - If a PR exists and is open, update it.
   - Write a proper PR title describing the change.
6. Write/update PR body with:
   - Summary of changes.
   - Testing done.
   - Related issue links.

## Pitfalls

- Never force-push without `--force-with-lease`.
- Don't rewrite remote URLs or switch protocols as a workaround for auth issues.
- If the branch is tied to a closed/merged PR, create a new branch + PR.
