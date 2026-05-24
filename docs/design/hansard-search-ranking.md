# Hansard Search Ranking

**Status:** Implemented for v1
**Ticket:** EPAC-467
**Last updated:** 2026-04-29

## Goal

Hansard speech search should rank source records by textual relevance first, then prefer recent speeches, then add a small boost for user-controlled follows. Ranking must stay transparent, tunable, and traceable to canonical `speeches` rows.

## API

```text
GET /search/speeches?q=...&user_id=...&from_date=...&to_date=...
```

`q` is required. `from_date` and `to_date` are optional `YYYY-MM-DD` filters on `speeches.sitting_date`.

`user_id` is optional. For v1 it maps to the anonymous device subscription token stored by `device-register`; it is only used to load explicit follows (`my_mp_member_id`, `topic_ids`, `bill_ids`). Requests without `user_id`, or with no matching subscription row, receive the public ranking only.

The legacy `/search?query=...` route remains supported for existing clients and uses the same backend handler.

## Formula

Each matching speech receives:

```text
rank_score =
  SEARCH_TEXT_WEIGHT    * text_rank
+ SEARCH_RECENCY_WEIGHT * recency_score
+ SEARCH_FOLLOW_WEIGHT  * follow_score
```

Defaults:

| Variable | Default | Purpose |
|---|---:|---|
| `SEARCH_TEXT_WEIGHT` | `0.72` | Main relevance component from PostgreSQL `ts_rank` |
| `SEARCH_RECENCY_WEIGHT` | `0.20` | Recency decay component |
| `SEARCH_FOLLOW_WEIGHT` | `0.08` | Explicit follow boost component |
| `SEARCH_RECENCY_HALFLIFE_DAYS` | `90` | Half-life for recency decay |
| `SEARCH_LANGUAGE_HINT_BOOST` | `1.15` | Small boost to the vector matching detected query language |
| `SEARCH_MY_MP_BOOST` | `1.0` | Follow score contribution when speaker matches the user's MP |
| `SEARCH_BILL_BOOST` | `0.85` | Follow score contribution when `related_bill_ids` overlaps followed bills |
| `SEARCH_TOPIC_BOOST` | `0.65` | Follow score contribution when followed topic IDs appear in subject/content text |

All values are Lambda environment variables so ranking can be tuned without a code deploy.

## Components

`text_rank` uses the greater of English and French `ts_rank` scores from `speeches.search_vector_en` and `speeches.search_vector_fr`. The query language hint comes from accent and marker-word detection; it changes ranking slightly but never filters the other language out.

`recency_score` is:

```text
0.5 ^ (age_in_days / SEARCH_RECENCY_HALFLIFE_DAYS)
```

Rows with no `sitting_date` receive `0`. Future-dated rows are clamped to age `0`.

`follow_score` is only non-zero when `user_id` maps to a stored subscription row. It is the sum of explicit follow matches for:

- user's MP: `speeches.member_id = device_subscriptions.my_mp_member_id`
- followed bills: `speeches.related_bill_ids && device_subscriptions.bill_ids`
- followed topics: followed topic IDs matched against source speech subject/content text

No search history, inferred interest, location inference, or unauthenticated personalization is used.

## Regression Set

`backend/search/ranking_evaluation.json` contains 20 fixed queries with expected top-5 result IDs. The package test validates the fixture shape so any future ranking change has to preserve or intentionally refresh the evaluation set.

When staging has a representative speech corpus, refresh the expected IDs by running the search endpoint against staging, reviewing the top-5 results manually for source relevance, and committing the updated fixture in the same PR as the ranking change.

## Non-Goals

- No AI-generated snippets, summaries, or labels.
- No editorial weighting of political importance.
- No personalization unless the user has explicitly followed MPs, bills, or topics.
- No Meilisearch or separate truth store for v1 ranking.
