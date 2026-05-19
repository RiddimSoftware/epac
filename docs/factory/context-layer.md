# Context Layer for Bugfix Intake

The context layer gives a fresh bugfix session a small, searchable map of the
repository before it decides which files to inspect. It is a routing aid, not a
replacement for reading source code.

Principles:

- Relevance: retrieve files whose paths, categories, headings, or code entities
  overlap the reported bug surface.
- Sufficiency: inspect enough targeted files to understand the behavior and test
  path before editing.
- Isolation: keep bugfix sessions scoped to the validated SPEC and the matching
  repository files; avoid pulling unrelated product or release context forward.
- Economy: use the map to choose a short reading list instead of dumping whole
  directories into an LLM prompt.
- Provenance: prefer generated, reproducible context from tracked files so later
  agents can verify why a file was considered relevant.

For bugfix intake, generate the map after cloning:

```bash
python3 scripts/context/context_map.py build --out .factory/context/repo-map.json
```

Then search with terms from the SPEC:

```bash
python3 scripts/context/context_map.py search \
  --map .factory/context/repo-map.json \
  --query "home status card live data"
```

Use the top matches to decide which files to inspect manually. The search output
should point the session toward likely views, services, tests, docs, or workflow
files; it should not be pasted wholesale into the bugfix prompt.

