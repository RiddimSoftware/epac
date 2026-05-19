---
name: Bug report
about: Report a bug with reproduction details
title: 'Bug: '
labels: bug
---
## App version
* **iOS app version:** [e.g. 1.2.3]
* **iOS version:** [e.g. 17.4]
* **Device:** [e.g. iPhone 15 Pro]

## Repro steps
1. 

## Expected behavior

## Actual behavior

## Screenshot
[Add screenshot here if applicable]

## Factory-ready SPEC
If this bug should be picked up by an LLM or autonomous developer session, run:

```bash
python3 scripts/intake/bugfix_spec.py new
python3 scripts/intake/bugfix_spec.py validate .factory/intake/<generated>/SPEC.md
python3 scripts/intake/bugfix_spec.py issue-body .factory/intake/<generated>/SPEC.md
```

Paste the generated issue body here or attach the validated `SPEC.md`.
