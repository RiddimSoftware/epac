-- EPAC-467: store explicit followed bills for search ranking personalization.
--
-- Search ranking only applies bill-follow boosts when a request provides a
-- user_id matching a device subscription row. This column keeps that signal
-- source-controlled by the user rather than inferred from search behavior.

ALTER TABLE device_subscriptions
    ADD COLUMN IF NOT EXISTS bill_ids TEXT[] NOT NULL DEFAULT '{}';

CREATE INDEX IF NOT EXISTS device_subs_bill_idx
    ON device_subscriptions USING gin(bill_ids);
