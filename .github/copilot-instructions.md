# Repository Instructions

For bug fixes, do not start implementation until a valid bugfix SPEC exists.

Run the repo-local intake harness first:

```bash
python3 scripts/intake/bugfix_spec.py new
python3 scripts/intake/bugfix_spec.py validate .factory/intake/<generated>/SPEC.md
```

Use `.factory/prompts/bugfix-intake.md` to guide the intake session. The SPEC must capture observed behavior, expected behavior, reproduction steps, acceptance criteria, evidence plan, validation plan, non-goals, and provenance metadata.

After the SPEC validates, link it from the GitHub or Linear issue and from the implementation PR.

