# Bugfix Intake Harness

The bugfix intake harness turns a contributor or LLM-session bug report into a validated `SPEC.md` before implementation starts.

It exists to preserve non-repudiation for bug fixes: every fix should have a durable receipt that says why it was requested, what behavior was observed, what behavior is expected, what evidence will prove the fix, and how the reporter can validate the result.

## Start a Bugfix Intake Session

From a fresh clone, ask the LLM session to read:

```text
.factory/prompts/bugfix-intake.md
```

Then run:

```bash
python3 scripts/intake/bugfix_spec.py new
```

For non-interactive sessions, pass the fields explicitly:

```bash
python3 scripts/intake/bugfix_spec.py new \
  --title "Home screen implies live debate data" \
  --reporter "github-user-or-email" \
  --source "llm-session" \
  --surface "Home status card" \
  --observed "The card says cached live data when only archived debates are available." \
  --expected "The card explains that epac currently shows past debates and archival data." \
  --step "Launch epac." \
  --step "Open the Home tab." \
  --evidence "Before/after screenshot of the Home status card." \
  --validation "Reporter confirms the TestFlight build no longer implies live data."
```

The command writes:

```text
.factory/intake/<timestamp-and-slug>/SPEC.md
```

## Validate a SPEC

```bash
python3 scripts/intake/bugfix_spec.py validate .factory/intake/<generated>/SPEC.md
```

The validator checks for:

- required provenance fields
- required bugfix sections
- at least one numbered reproduction step
- acceptance criteria starting with `Given`
- no obvious placeholder text

## Render an Issue Body

```bash
python3 scripts/intake/bugfix_spec.py issue-body .factory/intake/<generated>/SPEC.md
```

Use the output as the GitHub or Linear issue body. The generated issue body keeps the trace ID, affected surface, observed behavior, expected behavior, evidence plan, and reporter validation plan together.

## Boundary

Bugfix intake stops at a validated SPEC. It does not:

- implement the fix
- create a release
- enroll a tester
- dispatch the developer bot

Those steps belong to the downstream factory.

