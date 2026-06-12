# GitHub Environment Protection: app-store-release

## Configuration (set 2026-05-09, DEL-310)

The `app-store-release` environment in `RiddimSoftware/epac` has required reviewer protection enabled to gate App Store releases behind explicit human approval.

### Active settings

| Setting | Value |
|---|---|
| `can_admins_bypass` | `false` |
| `prevent_self_review` | `true` |
| Required reviewers | `@sunnypurewal` |

### Purpose

`release-app-store.yml` dispatches to this environment via `approval_environment: ${{ vars.APPROVAL_ENVIRONMENT \|\| 'app-store-release' }}`. With protection rules in place, every workflow run that reaches the approval step pauses and shows **"Waiting for required approval"** until a listed reviewer approves — the developer who triggered the run cannot approve their own release.

### Changing the reviewer list

```bash
gh api --method PUT repos/RiddimSoftware/epac/environments/app-store-release --input - <<'EOF'
{
  "prevent_self_review": true,
  "reviewers": [{"type": "User", "id": <USER_ID>}],
  "can_admins_bypass": false
}
EOF
```

Get a user's numeric ID: `gh api users/<login> --jq '.id'`
