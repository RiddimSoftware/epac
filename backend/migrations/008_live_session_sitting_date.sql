-- EPAC-168: track the calendar date of the current/most-recent live sitting.
-- The poller writes this when is_sitting flips true; it is preserved on
-- subsequent non-sitting polls so iOS can transition the Home card from the
-- LIVE state to "TODAY IN PARLIAMENT" once Hansard publishes for that day.

ALTER TABLE live_session ADD COLUMN IF NOT EXISTS sitting_date DATE;
