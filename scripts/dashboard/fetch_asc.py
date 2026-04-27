#!/usr/bin/env python3
"""
Fetch App Store Connect metrics and write dashboard/data/asc.json.

Usage:
  python scripts/dashboard/fetch_asc.py \
    --key-id     <10-char ASC key ID> \
    --issuer-id  <ASC issuer UUID> \
    --private-key /path/to/AuthKey_KEYID.p8
"""
import argparse
import json
import os
import time
from datetime import datetime, timezone

import jwt
import requests

APP_ID = "1224459142"
ASC_BASE = "https://api.appstoreconnect.apple.com/v1"


def get_token(key_id: str, issuer_id: str, key_path: str) -> str:
    with open(key_path) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": key_id},
    )


def asc_get(url: str, headers: dict, params: dict | None = None) -> dict:
    r = requests.get(url, headers=headers, params=params, timeout=30)
    if not r.ok:
        print(f"  ASC {r.status_code} {url}: {r.text[:200]}")
        return {}
    return r.json()


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--key-id", required=True)
    p.add_argument("--issuer-id", required=True)
    p.add_argument("--private-key", required=True, metavar="PATH")
    args = p.parse_args()

    token = get_token(args.key_id, args.issuer_id, args.private_key)
    headers = {"Authorization": f"Bearer {token}"}

    print("Fetching ASC customer reviews...")
    reviews_data = asc_get(
        f"{ASC_BASE}/apps/{APP_ID}/customerReviews",
        headers,
        params={
            "limit": 10,
            "sort": "-createdDate",
            "fields[customerReviews]": "rating,title,body,createdDate",
        },
    )
    reviews = [
        {
            "rating": rev["attributes"]["rating"],
            "title": rev["attributes"].get("title", ""),
            "body": (rev["attributes"].get("body") or "")[:200],
            "date": rev["attributes"]["createdDate"],
        }
        for rev in reviews_data.get("data", [])
    ]

    # Rating breakdown (v1 uses customerReviewSummary on the app resource)
    print("Fetching ASC app rating summary...")
    app_data = asc_get(
        f"{ASC_BASE}/apps/{APP_ID}",
        headers,
        params={"fields[apps]": "name,bundleId"},
    )
    app_name = (app_data.get("data", {}).get("attributes", {}) or {}).get("name", "epac")

    output = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "app_id": APP_ID,
        "app_name": app_name,
        "recent_reviews": reviews,
    }

    os.makedirs("dashboard/data", exist_ok=True)
    path = "dashboard/data/asc.json"
    with open(path, "w") as f:
        json.dump(output, f, indent=2)
    print(f"  Wrote {path} ({len(reviews)} reviews)")


if __name__ == "__main__":
    main()
