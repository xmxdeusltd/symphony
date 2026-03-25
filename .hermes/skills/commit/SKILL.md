---
name: commit
description: Create a well-formed git commit from current changes using session context for rationale and summary.
version: 1.0.0
author: Conductor
license: Apache-2.0
metadata:
  hermes:
    tags: [git, commit, workflow]
---
# Commit

## When to Use

When asked to commit, prepare a commit message, or finalize staged work.

## Goals

- Produce a commit that reflects the actual code changes and the session context.
- Follow common git conventions (type prefix, short subject, wrapped body).
- Include both summary and rationale in the body.

## Steps

1. Read session context to identify scope, intent, and rationale.
2. Inspect working tree and staged changes:
   ```bash
   git status
   git diff
   git diff --staged
   ```
3. Stage intended changes (`git add -A`) after confirming scope.
4. Sanity-check newly added files — flag build artifacts, logs, or temp files
   before committing.
5. Choose a conventional type and optional scope:
   `feat(scope):`, `fix(scope):`, `refactor(scope):`, `docs:`, `test:`, `chore:`
6. Write a subject line in imperative mood, <= 72 characters, no trailing period.
7. Write a body that includes:
   - Summary of key changes (what changed).
   - Rationale (why it changed).
   - Notable decisions or trade-offs.
8. Run: `git commit -m "<subject>" -m "<body>"`
9. Verify with `git log -1 --stat`.

## Pitfalls

- Don't commit unrelated changes — split into separate commits if needed.
- Don't include generated files unless they're meant to be tracked.
- If the repo has a commit message template or convention doc, follow it.
