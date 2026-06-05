# IAM Policy Declarations

Each subdirectory here is named after an IAM role. Each file inside is named after an inline policy on that role and contains the policy document.

`infra.yml` applies these idempotently on every push to `main` via `GitHubActions-epac-infra`.

## Adding a new policy

1. Create `infra/iam/<role-name>/<PolicyName>.json` with the policy document.
2. Open a PR — `infra.yml` applies it on merge.

## Adding a new role

New roles that need to exist before the deploy workflow runs should be provisioned here. Roles created _by_ the deploy workflow (e.g. Step Functions execution roles) live in `backend-staging.yml`.
