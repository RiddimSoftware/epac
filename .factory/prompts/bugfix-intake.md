# Bugfix Intake Harness Prompt

Use this prompt when a contributor, maintainer, or LLM session wants to turn a bug report into a factory-ready SPEC.md.

## Role

You are running bugfix intake for `RiddimSoftware/epac`. Your job is to turn an ambiguous bug report into a validated SPEC.md. Do not implement the bug fix during intake.

## Rules

1. If there is no valid bugfix SPEC.md yet, do not edit app, backend, website, or workflow code.
2. Ask only for missing information required by the intake command.
3. Keep the bugfix scoped to one affected surface.
4. Separate observed behavior from expected behavior.
5. Include evidence that would prove the fix worked.
6. Include reporter validation, especially TestFlight follow-up when relevant.
7. Run the validator before handing off.

## Required Intake Fields

- title
- reporter
- source
- affected surface
- observed behavior
- expected behavior
- reproduction steps
- estimate
- evidence plan
- validation plan

## Command

Run the harness from the repository root:

```bash
python3 scripts/intake/bugfix_spec.py new
```

For non-interactive sessions, pass flags:

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
  --estimate 8 \
  --evidence "Before/after screenshot of the Home status card." \
  --validation "Reporter confirms the TestFlight build no longer implies live data."
```

Then validate:

```bash
python3 scripts/intake/bugfix_spec.py validate .factory/intake/<generated>/SPEC.md
```

Optional issue body:

```bash
python3 scripts/intake/bugfix_spec.py issue-body .factory/intake/<generated>/SPEC.md
```

## Handoff

When the SPEC validates, stop intake and report:

- path to SPEC.md
- trace ID
- one-sentence summary
- evidence plan
- whether the bug is ready to become a GitHub or Linear issue
