#!/usr/bin/env python3
"""
Fetch Jira metrics for the EPAC project and write dashboard/data/jira.json.

Required environment variables:
  JIRA_CLOUD_ID   - Atlassian Cloud ID
  JIRA_EMAIL      - Atlassian account email
  JIRA_API_TOKEN  - Jira API token (id.atlassian.com/manage-profile/security/api-tokens)
"""
import json
import os
from datetime import datetime, timedelta, timezone

import requests

CLOUD_ID = os.environ["JIRA_CLOUD_ID"]
AUTH = (os.environ["JIRA_EMAIL"], os.environ["JIRA_API_TOKEN"])
BASE = f"https://api.atlassian.com/ex/jira/{CLOUD_ID}/rest/api/3"


def jql(query: str, fields: list[str], max_results: int = 200) -> list:
    """Run a JQL query, transparently paginating up to max_results."""
    results = []
    start = 0
    page_size = min(100, max_results)
    while len(results) < max_results:
        r = requests.get(
            f"{BASE}/search",
            auth=AUTH,
            params={
                "jql": query,
                "fields": ",".join(fields),
                "maxResults": page_size,
                "startAt": start,
            },
            timeout=30,
        )
        r.raise_for_status()
        data = r.json()
        batch = data.get("issues", [])
        results.extend(batch)
        if len(batch) < page_size or len(results) >= data.get("total", 0):
            break
        start += len(batch)
    return results[:max_results]


def main() -> None:
    print("Fetching Jira issues...")
    all_issues = jql(
        "project = EPAC AND issuetype != Epic ORDER BY updated DESC",
        ["summary", "status", "issuetype", "priority", "created", "updated", "parent"],
    )

    epics = jql(
        "project = EPAC AND issuetype = Epic ORDER BY created ASC",
        ["summary", "status"],
    )
    print(f"  {len(all_issues)} issues, {len(epics)} epics")

    # Status summary
    by_status: dict[str, int] = {}
    in_progress: list[dict] = []
    high_priority_bugs: list[dict] = []
    done_this_week: list[dict] = []

    cutoff = datetime.now(timezone.utc) - timedelta(days=7)

    for issue in all_issues:
        f = issue["fields"]
        status = f["status"]["name"]
        by_status[status] = by_status.get(status, 0) + 1

        if status == "In Progress":
            in_progress.append({
                "key": issue["key"],
                "summary": f["summary"],
                "type": f["issuetype"]["name"],
                "updated": f["updated"],
            })

        priority_name = (f.get("priority") or {}).get("name", "")
        if (
            f["issuetype"]["name"] == "Bug"
            and priority_name in ("High", "Highest")
            and status != "Done"
        ):
            high_priority_bugs.append({
                "key": issue["key"],
                "summary": f["summary"],
                "priority": priority_name,
            })

        if status == "Done":
            updated = f.get("updated", "")
            try:
                updated_dt = datetime.fromisoformat(updated.replace("Z", "+00:00"))
                if updated_dt >= cutoff:
                    done_this_week.append({
                        "key": issue["key"],
                        "summary": f["summary"],
                        "type": f["issuetype"]["name"],
                        "updated": updated,
                    })
            except (ValueError, AttributeError):
                pass

    # Epic progress (one JQL per epic — batched)
    print(f"  Computing epic progress for {len(epics)} epics...")
    epic_progress: list[dict] = []
    for epic in epics:
        children = jql(
            f"project = EPAC AND parent = {epic['key']}",
            ["status"],
            max_results=500,
        )
        total = len(children)
        done = sum(1 for i in children if i["fields"]["status"]["name"] == "Done")
        epic_progress.append({
            "key": epic["key"],
            "summary": epic["fields"]["summary"],
            "status": epic["fields"]["status"]["name"],
            "total": total,
            "done": done,
            "pct": round(done / total * 100) if total > 0 else 0,
        })

    output = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "summary": by_status,
        "total_issues": len(all_issues),
        "in_progress": sorted(in_progress, key=lambda x: x["updated"], reverse=True),
        "done_this_week": sorted(done_this_week, key=lambda x: x["updated"], reverse=True),
        "high_priority_bugs": high_priority_bugs,
        "epic_progress": sorted(epic_progress, key=lambda x: x["pct"], reverse=True),
    }

    os.makedirs("dashboard/data", exist_ok=True)
    path = "dashboard/data/jira.json"
    with open(path, "w") as f:
        json.dump(output, f, indent=2)
    print(f"  Wrote {path} ({len(all_issues)} issues, {len(epics)} epics)")


if __name__ == "__main__":
    main()
