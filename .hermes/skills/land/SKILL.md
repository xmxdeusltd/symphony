---
name: land
description: Land a PR by resolving conflicts, waiting for CI, and squash-merging when green.
version: 1.0.0
author: Conductor
license: Apache-2.0
prerequisites:
  commands: [gh, git]
metadata:
  hermes:
    tags: [git, merge, pull-request, ci, workflow]
---
# Land

## When to Use

When asked to land, merge, or shepherd a PR to completion.

## Goals

- Ensure the PR is conflict-free with main.
- Keep CI green and fix failures when they occur.
- Squash-merge the PR once checks pass.
- Don't yield until the PR is merged — keep the loop running unless blocked.

## Steps

1. Locate the PR for the current branch:
   ```bash
   gh pr view --json number,title,mergeable,statusCheckRollup
   ```
2. If uncommitted changes exist, use `commit` skill then `push` skill.
3. Check mergeability and conflicts against main.
4. If conflicts exist, use `pull` skill to merge origin/main, then `push` skill.
5. Check for review comments — address outstanding feedback before merging.
6. Watch CI checks until complete:
   ```bash
   gh pr checks --watch
   ```
   - If no CI checks configured, skip.
7. If checks fail:
   - Pull logs, fix the issue.
   - Commit with `commit` skill, push with `push` skill.
   - Re-watch checks.
8. When all checks green and review addressed, squash-merge:
   ```bash
   gh pr merge --squash --auto
   ```

## Pitfalls

- Don't merge with failing CI unless explicitly told to.
- Don't delete remote branches manually — most repos auto-delete after merge.
- If blocked by required reviews, surface it instead of bypassing.
