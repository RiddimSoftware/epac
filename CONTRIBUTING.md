# Contributing to epac

Thanks for your interest in helping improve epac. We welcome clear bug reports, thoughtful suggestions, and well-scoped pull requests.

## How to report an issue

Before opening a pull request, start by filing an issue with:

- a short, descriptive title
- what you expected to happen
- what actually happened
- reproducible steps (if applicable)
- logs or screenshots when helpful

For bug fixes that should be ready for an LLM or autonomous developer session,
create a bugfix SPEC first:

```bash
python3 scripts/intake/bugfix_spec.py new
python3 scripts/intake/bugfix_spec.py validate .factory/intake/<generated>/SPEC.md
```

The guide lives at [`docs/factory/bugfix-intake.md`](docs/factory/bugfix-intake.md).
Attach the validated `SPEC.md` contents or rendered issue body to the issue.

If this is a question or clarification request, reach out via email at [sunny@riddimsoftware.com](mailto:sunny@riddimsoftware.com).

## How to propose a change

1. Open an issue to discuss the change (especially for behavior changes or new features).
2. Link related issues and docs.
3. Keep the change focused and include rationale plus trade-offs.
4. Ask for feedback if you are unsure of scope.

## Branching and pull requests

- Create a branch from `main`.
- Keep PRs small and scoped to one purpose.
- Include a clear title and summary of what changed and why.
- PRs may receive automated first-pass review; humans review and merge.
- Reference the issue(s) you are addressing and include test evidence in the PR description.

## Local development expectations

- iOS work: Xcode and the project toolchain required by `ios/README.md`/`README.md`.
- Backend work: Ruby/Go/Python tooling for your service plus any repository-specific dependencies (for example, `go test`, `swiftlint --strict`, or database/local pipeline prerequisites).
- Add/update tests where practical and run the relevant checks before opening a PR.
- Keep file and API changes small and easy to review.

## Community behavior

By contributing, you agree to follow our [Code of Conduct](CODE_OF_CONDUCT.md).

## Support and contact

For non-security community questions, use issues. For other help requests, email [sunny@riddimsoftware.com](mailto:sunny@riddimsoftware.com).
