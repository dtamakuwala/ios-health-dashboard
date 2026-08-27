#!/usr/bin/env python3
"""Daily refresh entrypoint for the cloud routine.

Reads DATABRICKS_HOST / DATABRICKS_TOKEN / DATABRICKS_WAREHOUSE_ID from the
environment, runs query_full_metrics.sql and query_troas_croas.sql against the
Databricks SQL Statement Execution API, and writes:
  - data/raw_full_metrics.json   (business health + points economy, by date)
  - data/raw_grand_total.json    (subset of the above, used by the primary
                                   metrics dashboard) + merged tROAS/cROAS
  - data/raw_troas_croas.json    (G1/G3/G7/G14/G30 tROAS/cROAS, by date)

This script does NOT commit/push, regenerate the dashboard HTML, or republish
the artifacts -- the routine's prompt handles those steps so the token never
needs to touch git.

Usage: python3 cloud_refresh.py
"""
import json
import os
import sys
import time
import urllib.request

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
FULL_METRICS_QUERY_PATH = os.path.join(BASE_DIR, "query_full_metrics.sql")
TROAS_QUERY_PATH = os.path.join(BASE_DIR, "query_troas_croas.sql")

GRAND_TOTAL_FIELDS = [
    "ua_cost", "new_users", "dau", "survey_revenue", "gc_cost", "pending_gc_cost",
    "game_pass_revenue", "install_revenue", "iap_install_revenue", "client_ad_revenue",
    "game_installs",
]
ROAS_WINDOWS = ["g1", "g3", "g7", "g14", "g30"]


def run_query(host, token, warehouse_id, sql, timeout_s=600):
    def api(path, method="GET", body=None):
        url = f"{host.rstrip('/')}{path}"
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method, headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        })
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())

    result = api("/api/2.0/sql/statements", "POST", {
        "warehouse_id": warehouse_id,
        "statement": sql,
        "wait_timeout": "30s",
        "on_wait_timeout": "CONTINUE",
    })
    sid = result["statement_id"]
    state = result.get("status", {}).get("state", "PENDING")
    deadline = time.time() + timeout_s

    while state not in ("SUCCEEDED", "FAILED", "CANCELED", "CLOSED"):
        if time.time() > deadline:
            raise TimeoutError(f"Query timed out after {timeout_s}s")
        time.sleep(5)
        result = api(f"/api/2.0/sql/statements/{sid}")
        state = result.get("status", {}).get("state", "RUNNING")

    if state != "SUCCEEDED":
        raise RuntimeError(f"Query failed: {json.dumps(result.get('status'))}")

    cols = [c["name"] for c in result["manifest"]["schema"]["columns"]]
    rows = result.get("result", {}).get("data_array") or []
    nxt = result.get("result", {}).get("next_chunk_index")
    while nxt is not None:
        chunk = api(f"/api/2.0/sql/statements/{sid}/result/chunks/{nxt}")
        rows.extend(chunk.get("data_array") or [])
        nxt = chunk.get("next_chunk_index")

    return [dict(zip(cols, r)) for r in rows]


def main():
    host = os.environ["DATABRICKS_HOST"]
    token = os.environ["DATABRICKS_TOKEN"]
    warehouse_id = os.environ["DATABRICKS_WAREHOUSE_ID"]

    with open(FULL_METRICS_QUERY_PATH) as f:
        full_metrics_sql = f.read()
    with open(TROAS_QUERY_PATH) as f:
        troas_sql = f.read()

    print("Running query_full_metrics.sql against Databricks...")
    full_rows = run_query(host, token, warehouse_id, full_metrics_sql)
    print(f"Got {len(full_rows)} days of business health + points data")

    print("Running query_troas_croas.sql against Databricks...")
    troas_rows = run_query(host, token, warehouse_id, troas_sql)
    print(f"Got {len(troas_rows)} days of tROAS/cROAS data")

    troas_by_date = {r["date"]: r for r in troas_rows}

    full_metrics_path = os.path.join(BASE_DIR, "data", "raw_full_metrics.json")
    with open(full_metrics_path, "w") as f:
        json.dump(full_rows, f, indent=2)
    print(f"Wrote {full_metrics_path}")

    grand_total = []
    for r in full_rows:
        rec = {"dates": r["dates"]}
        for field in GRAND_TOTAL_FIELDS:
            rec[field] = r.get(field)
        troas_src = troas_by_date.get(r["dates"], {})
        for w in ROAS_WINDOWS:
            t = troas_src.get(f"{w}_troas")
            c = troas_src.get(f"{w}_croas")
            t = float(t) if t is not None else None
            c = float(c) if c is not None else None
            rec[f"{w}_troas"] = t
            rec[f"{w}_croas"] = c
            rec[f"{w}_delivery_rate"] = (c / t) if (c is not None and t not in (None, 0)) else None
        grand_total.append(rec)

    grand_total_path = os.path.join(BASE_DIR, "data", "raw_grand_total.json")
    with open(grand_total_path, "w") as f:
        json.dump(grand_total, f, indent=2)
    print(f"Wrote {grand_total_path}")

    troas_path = os.path.join(BASE_DIR, "data", "raw_troas_croas.json")
    with open(troas_path, "w") as f:
        json.dump(troas_by_date, f, indent=2)
    print(f"Wrote {troas_path}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
