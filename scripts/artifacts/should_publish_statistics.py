#!/usr/bin/env python3
"""Return success when a statistics pipeline should publish in this workflow run."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import os


QUARTER_START_MONTHS = {1, 4, 7, 10}
PUBLISH_DAY = 22
PUBLISH_HOUR_UTC = 0


def should_publish(cadence: str, now: datetime, event_name: str) -> bool:
    if event_name == "workflow_dispatch":
        return True
    if now.day != PUBLISH_DAY or now.hour != PUBLISH_HOUR_UTC:
        return False
    if cadence == "monthly":
        return True
    if cadence == "quarterly":
        return now.month in QUARTER_START_MONTHS
    raise ValueError(f"unsupported cadence: {cadence}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cadence", choices=("monthly", "quarterly"))
    args = parser.parse_args()

    now = datetime.now(timezone.utc)
    event_name = os.getenv("GITHUB_EVENT_NAME", "")
    return 0 if should_publish(args.cadence, now, event_name) else 1


if __name__ == "__main__":
    raise SystemExit(main())
