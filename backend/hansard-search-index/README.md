# hansard-search-index

`hansard-search-index` is a manually-invoked Go Lambda that builds the v1
SQLite FTS5 search index for the current House of Commons Hansard session. It
downloads English Hansard XML from ourcommons.ca, parses interventions and
paragraphs, writes `/tmp/index.sqlite`, uploads it to S3, then writes a manifest
after the SQLite object exists.

## Invocation

Staging:

```bash
aws lambda invoke \
  --function-name epac-hansard-search-index-staging \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/hansard-search-index.out.json
```

Production:

```bash
aws lambda invoke \
  --function-name epac-hansard-search-index-production \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/hansard-search-index.out.json
```

The manual dispatch workflow is:

```text
https://github.com/RiddimSoftware/epac/actions/workflows/hansard-search-reindex.yml
```

The workflow accepts `environment`, plus optional `parliament_number` and
`session_number` overrides. The Lambda reads `PARLIAMENT_NUMBER` and
`SESSION_NUMBER` from its environment; when workflow overrides are supplied, the
workflow temporarily updates those environment variables before invoking the
function, then restores the prior configuration.

## Configuration

Required:

- `EPAC_ARTIFACT_BUCKET` - destination artifact bucket.

Optional:

- `EPAC_HANSARD_SEARCH_PREFIX` - destination prefix, default
  `hansard-search/v1`.
- `PARLIAMENT_NUMBER` - parliament to index, default `45`.
- `SESSION_NUMBER` - session to index, default `1`.

The default session values match the current 45th Parliament, 1st Session at the
time this Lambda was added. Operators should pass workflow overrides or update
the Lambda environment when a future session starts.

## Source URL

The downloader uses the existing `backend/download_hansard.py` convention, which
was verified against ourcommons.ca:

```text
https://www.ourcommons.ca/Content/House/{parliament}{session}/Debates/{sitting:03d}/HAN{sitting:03d}-E.XML
```

For example:

```text
https://www.ourcommons.ca/Content/House/451/Debates/001/HAN001-E.XML
```

Raw XML is cached for one invocation under `/tmp/raw/45-1-HAN001-E.XML` style
filenames.

## S3 Layout

With the default prefix, the Lambda writes:

```text
s3://${EPAC_ARTIFACT_BUCKET}/hansard-search/v1/index.sqlite
s3://${EPAC_ARTIFACT_BUCKET}/hansard-search/v1/manifest.json
```

The manifest shape is:

```json
{
  "version": "v1",
  "built_at": "2026-05-25T17:30:00Z",
  "parliament_number": 45,
  "session_number": 1,
  "sitting_count": 47,
  "intervention_count": 12345,
  "message_count": 56789,
  "sqlite_key": "hansard-search/v1/index.sqlite",
  "sqlite_size_bytes": 31415926,
  "sqlite_sha256": "<hex>"
}
```

## SQLite Schema

The builder recreates the database on every run:

```sql
CREATE TABLE meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE interventions (
    rowid INTEGER PRIMARY KEY,
    parliament_number INTEGER NOT NULL,
    session_number INTEGER NOT NULL,
    sitting_date TEXT NOT NULL,
    intervention_id TEXT NOT NULL UNIQUE,
    speaker_name TEXT NOT NULL,
    party_abbreviation TEXT NOT NULL DEFAULT '',
    riding_name TEXT NOT NULL DEFAULT '',
    topic TEXT NOT NULL DEFAULT ''
);
CREATE INDEX idx_interventions_sitting_date ON interventions(sitting_date);
CREATE TABLE messages (
    rowid INTEGER PRIMARY KEY,
    intervention_rowid INTEGER NOT NULL REFERENCES interventions(rowid),
    message_id TEXT NOT NULL UNIQUE,
    position INTEGER NOT NULL,
    content TEXT NOT NULL
);
CREATE VIRTUAL TABLE messages_fts USING fts5(
    content,
    content='messages',
    content_rowid='rowid',
    tokenize='porter unicode61 remove_diacritics 1'
);
```

Triggers keep `messages_fts` synchronized with `messages`. Dates are stored as
`YYYY-MM-DD`.
