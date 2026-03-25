---
name: linear
description: Interact with Linear issue tracker — read issues, update status, post comments.
version: 1.0.0
author: Conductor
license: Apache-2.0
metadata:
  hermes:
    tags: [linear, issue-tracker, workflow]
---
# Linear

## When to Use

When you need to read Linear issue details, update issue status, or post
progress comments (workpad updates).

## API Access

Use `curl` with the Linear GraphQL API:

```bash
curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ viewer { id name } }"}' | python3 -m json.tool
```

## Common Operations

### Get issue details
```bash
curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ issue(id: \"ENG-123\") { id identifier title description state { name } } }"}'
```

### Update issue status
First get the target state UUID, then:
```bash
curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "mutation { issueUpdate(id: \"ENG-123\", input: { stateId: \"STATE_UUID\" }) { success } }"}'
```

### Add/update a comment (workpad)
```bash
curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "mutation { commentCreate(input: { issueId: \"ISSUE_UUID\", body: \"Progress update...\" }) { success } }"}'
```

## Workpad Protocol

Maintain a single persistent comment as the workpad for each issue:
- Check if a workpad comment exists (search for "## Workpad" in comments).
- If not, create one. If exists, update it.
- Include: plan, acceptance criteria, validation status, notes, blockers.

## Pitfalls

- LINEAR_API_KEY must be set in the environment.
- Always check the `errors` array in GraphQL responses — HTTP 200 can still have errors.
- Use `python3 -m json.tool` or `jq` to format JSON for readability.
