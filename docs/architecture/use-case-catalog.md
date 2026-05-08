# epac Use-Case Catalog

> Initial catalog slice generated as part of EPAC-1766. Expand as additional use cases are extracted.

## FollowTopic

- **Intent:** Persist followed parliamentary topic IDs and notification granularity without changing existing stored preference semantics.
- **Inputs:** Topic ID, follow/unfollow intent, optional notification granularity.
- **Outputs:** Updated local follow state, backend device registration payload with stable `topic_ids` and `granularity` keys.
- **Domain contract:** Topic IDs come from `shared/topic-taxonomy/parliamentary_topics.json`.

## MatchParliamentaryTopics

- **Intent:** Match Hansard subject titles and related text against the canonical parliamentary topic taxonomy.
- **Inputs:** Free-form debate or speech title text.
- **Outputs:** Zero or more canonical topic IDs in taxonomy order.
- **Policy notes:** Keywords are product policy, shared across iOS and backend adapters. Retain the existing `naturalresources` topic as canonical. Its stable ID is already stored in iOS user preferences and used by natural-resource context features, so the backend must adopt that same ID and keyword set instead of dropping it.

## NotifyTopicFollowers

- **Intent:** Notify subscribed users when a matched parliamentary topic is debated.
- **Inputs:** Sitting date, debate subject title, canonical topic IDs, subscriber preferences.
- **Outputs:** Backward-compatible APNs payloads with `topic_id` and `hansard_date` keys unchanged.
- **Dependency:** Uses `MatchParliamentaryTopics` and the canonical taxonomy rather than an adapter-local copy.
