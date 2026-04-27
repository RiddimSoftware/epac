-- Device subscription table for APNs topic-debate notifications.
-- One row per device token. `topic_ids` holds followed topic slugs.
-- `granularity` is a JSON map of {topic_id: "everyDebate"|"onlyMyMP"|"off"}.
-- `my_mp_member_id` is the Hansard Affiliation DbId of the user's MP,
-- used to filter "onlyMyMP" notifications.

CREATE TABLE IF NOT EXISTS device_subscriptions (
    token            TEXT        PRIMARY KEY,
    topic_ids        TEXT[]      NOT NULL DEFAULT '{}',
    granularity      JSONB       NOT NULL DEFAULT '{}',
    my_mp_member_id  TEXT,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Fast look-up of all devices subscribed to a given topic.
CREATE INDEX IF NOT EXISTS device_subs_topic_idx
    ON device_subscriptions USING gin(topic_ids);
