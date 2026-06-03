# Lobbyist subject-matter ingestion (EPAC-2149)

`subject_matters_ingest.py` fetches the Office of the Commissioner of Lobbying
(OCL) controlled subject-matter vocabulary from `lobbycanada.gc.ca` and emits a
JSON array on stdout for the Go loader (`backend/loader`) to upsert into the
`lobbyist_subject_matter_codes` table (migration
`013_lobbyist_subject_matter_codes.sql`). EPAC-2150 already owns
`lobbyist_subject_matters` (per-record subject assignments); this canonical
code list joins against `lobbyist_subject_matters.ocl_code` to translate raw
codes into bilingual labels.

## Run

```bash
cd /path/to/epac

# Emit JSON (53 codes today, growing as the OCL adds vocabulary).
python3 backend/lobbying/subject_matters_ingest.py > /tmp/ocl.json

# Same fetch, plus refresh backend/lobbying/mapping_report.md from the
# Monthly Communication Reports subject-matter view (cmmLgSms).
python3 backend/lobbying/subject_matters_ingest.py --report > /tmp/ocl.json

# Loader (writes to Postgres via DATABASE_URL).
cd backend/loader && go run . -lobbying /tmp/ocl.json
```

## Sources

- Subject-matter list (EN): https://lobbycanada.gc.ca/app/secure/ocl/lrs/do/regSms?lang=eng
- Subject-matter list (FR): https://lobbycanada.gc.ca/app/secure/ocl/lrs/do/regSms?lang=fra
- Communications by subject matter: https://lobbycanada.gc.ca/app/secure/ocl/lrs/do/cmmLgSms?lang=eng

## Mapping report

`mapping_report.md` lists every active OCL code with its recent communications
volume and a `mapped` / `unmapped` flag. The current report ships every code
as `unmapped` because EPAC-2150's `backend/lobbying/ocl_topic_map.json` keys
its mapping by synthetic `SMT-N` strings, not the integer OCL codes the live
registry uses. Wiring the two together (so EPAC-2149's report can reflect the
real mapping state) is follow-up work for sub-issue B's owner. Until that
reconciliation happens, the report doubles as a backlog of codes that still
need an EPAC topic assignment.

## Tests

```bash
cd backend/lobbying && python3 -m unittest
```

# Lobbying cohort averages

`cohort_averages.py` precomputes the comparison rows used by the MP lobbying
dashboard:

- one national row per parliament with `party = NULL`
- one row per current-party caucus
- `avg_communications = NULL` when fewer than five MPs in a party have at
  least one communication

Run this job after the quarterly OCL ingestion has refreshed the per-MP
aggregate table:

```bash
DATABASE_URL=postgres://... \
LOBBYING_MEMBER_TOTALS_TABLE=lobbying_member_communication_totals \
python3 cohort_averages.py --parliament 45
```

The source table is expected to expose `parliament`, `member_id`, and
`total_communications` columns. The job writes `lobbying_cohort_averages`.

Install the optional runtime dependency before running against Postgres:

```bash
python3 -m pip install -r requirements.txt
```
