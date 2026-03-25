---
name: review
description: Self-review checklist before marking work as complete.
version: 1.0.0
author: Conductor
license: Apache-2.0
metadata:
  hermes:
    tags: [review, quality, workflow]
---
# Review

## When to Use

Before transitioning an issue to Human Review or marking work as complete.
Run through this checklist to catch common issues.

## Checklist

### Code Quality
- [ ] Changes are minimal and focused — no scope creep.
- [ ] No debug code, console.log, or TODO comments left behind.
- [ ] Error handling is appropriate — no bare except/catch.
- [ ] Variable/function names are clear and descriptive.

### Testing
- [ ] New code has tests (or existing tests still pass).
- [ ] Edge cases are considered.
- [ ] Run the project's test suite and confirm green:
  ```bash
  # Auto-detect and run
  [ -f Makefile ] && make test
  [ -f package.json ] && npm test
  [ -f pytest.ini ] || [ -f setup.py ] && pytest
  [ -f mix.exs ] && mix test
  ```

### Git Hygiene
- [ ] Commits are logical and well-messaged (use `commit` skill).
- [ ] Branch is up to date with main (use `pull` skill if needed).
- [ ] No merge conflicts.

### Documentation
- [ ] README updated if public API/behavior changed.
- [ ] Code comments explain non-obvious decisions.
- [ ] PR description summarizes changes clearly.

### Security
- [ ] No secrets or API keys in code or commits.
- [ ] User input is validated/sanitized where applicable.
- [ ] File paths are validated to prevent traversal.

## After Review

If all checks pass, proceed with:
1. `push` skill to publish and create/update PR.
2. Update Linear issue status to Human Review.
3. Update workpad comment with completion summary.
