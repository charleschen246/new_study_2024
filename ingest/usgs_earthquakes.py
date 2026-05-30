"""Ingest USGS earthquake events into BigQuery (append-only).

Two modes:

  Incremental (default) -- pull the public "past 24 hours, all magnitudes" feed.
  Used by the daily GitHub Actions cron.

      python ingest/usgs_earthquakes.py

  Backfill -- pull a historical date range from the FDSN query API so the
  Elementary volume_anomalies test has a baseline from day one. Run once locally.

      python ingest/usgs_earthquakes.py --start 2026-01-15 --end 2026-05-30

Rows are appended to:
    my-project-111-257618.dbt_my_project.raw_usgs_earthquakes

Dedup is handled downstream in stg_usgs__earthquakes (overlapping pulls of the
same quake id collapse to the latest ingested_at). Auth uses Application Default
Credentials -- set GOOGLE_APPLICATION_CREDENTIALS to the service-account keyfile.
"""

from __future__ import annotations

import argparse
import datetime as dt
import sys
from typing import Iterable

import requests
from google.cloud import bigquery

PROJECT = "my-project-111-257618"
DATASET = "dbt_my_project"
TABLE = "raw_usgs_earthquakes"
TABLE_REF = f"{PROJECT}.{DATASET}.{TABLE}"

ALL_DAY_FEED = (
    "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_day.geojson"
)
ALL_MONTH_FEED = (
    "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_month.geojson"
)
QUERY_API = "https://earthquake.usgs.gov/fdsnws/event/1.0/query"

# Keep backfill volume manageable (low thousands of rows over a few months) while
# leaving daily counts variable enough to be interesting to anomaly detection.
BACKFILL_MIN_MAGNITUDE = 2.5

# The FDSN query API caps a single response at 20,000 events. Page the backfill
# by a window small enough to stay well under that even during busy periods.
BACKFILL_WINDOW_DAYS = 30

SCHEMA = [
    bigquery.SchemaField("id", "STRING", mode="REQUIRED"),
    bigquery.SchemaField("magnitude", "FLOAT"),
    bigquery.SchemaField("magnitude_type", "STRING"),
    bigquery.SchemaField("place", "STRING"),
    bigquery.SchemaField("event_type", "STRING"),
    bigquery.SchemaField("event_time", "TIMESTAMP"),
    bigquery.SchemaField("longitude", "FLOAT"),
    bigquery.SchemaField("latitude", "FLOAT"),
    bigquery.SchemaField("depth_km", "FLOAT"),
    bigquery.SchemaField("ingested_at", "TIMESTAMP", mode="REQUIRED"),
]


def _epoch_ms_to_iso(epoch_ms: int | None) -> str | None:
    """USGS reports event time as epoch milliseconds (UTC)."""
    if epoch_ms is None:
        return None
    return dt.datetime.fromtimestamp(epoch_ms / 1000, tz=dt.timezone.utc).isoformat()


def _flatten(features: Iterable[dict], ingested_at: str) -> list[dict]:
    rows: list[dict] = []
    for feature in features:
        props = feature.get("properties") or {}
        geom = feature.get("geometry") or {}
        coords = geom.get("coordinates") or [None, None, None]
        event_id = feature.get("id")
        if not event_id:
            continue  # cannot dedup without a stable id; skip
        rows.append(
            {
                "id": event_id,
                "magnitude": props.get("mag"),
                "magnitude_type": props.get("magType"),
                "place": props.get("place"),
                "event_type": props.get("type"),
                "event_time": _epoch_ms_to_iso(props.get("time")),
                "longitude": coords[0] if len(coords) > 0 else None,
                "latitude": coords[1] if len(coords) > 1 else None,
                "depth_km": coords[2] if len(coords) > 2 else None,
                "ingested_at": ingested_at,
            }
        )
    return rows


def _fetch_json(url: str, params: dict | None = None) -> dict:
    resp = requests.get(url, params=params, timeout=120)
    # The FDSN query API returns 404 ("no data") for windows that match no
    # events (e.g. a future-dated or quiet range). Treat that as empty, not an error.
    if resp.status_code == 404:
        return {"features": []}
    resp.raise_for_status()
    return resp.json()


def fetch_incremental() -> list[dict]:
    """Past 24 hours, all magnitudes."""
    payload = _fetch_json(ALL_DAY_FEED)
    return payload.get("features", [])


def fetch_backfill(start: dt.date, end: dt.date) -> list[dict]:
    """Historical range from the FDSN query API, paged by window.

    Falls back to the static all_month summary feed when the FDSN query service
    is unreachable (it returns 404 from some networks / egress-restricted CI).
    The static feed covers the trailing ~30 days, which is enough to seed an
    anomaly baseline; events are filtered client-side to [start, end].
    """
    features: list[dict] = []
    window_start = start
    one_day = dt.timedelta(days=1)
    used_query_api = False
    while window_start <= end:
        window_end = min(window_start + dt.timedelta(days=BACKFILL_WINDOW_DAYS), end)
        params = {
            "format": "geojson",
            "starttime": window_start.isoformat(),
            # endtime is exclusive at the instant; add a day to include window_end
            "endtime": (window_end + one_day).isoformat(),
            "minmagnitude": BACKFILL_MIN_MAGNITUDE,
            "orderby": "time-asc",
        }
        resp = requests.get(QUERY_API, params=params, timeout=120)
        if resp.status_code != 200:
            # FDSN query service is unavailable from this network (commonly 404).
            print(
                f"  FDSN query API returned {resp.status_code}; using all_month feed",
                file=sys.stderr,
            )
            break
        payload = resp.json()
        used_query_api = True
        batch = payload.get("features", [])
        print(f"  {window_start} -> {window_end}: {len(batch)} events", file=sys.stderr)
        features.extend(batch)
        window_start = window_end + one_day

    if used_query_api:
        return features

    # Fallback: pull the trailing-month static feed and filter to the range.
    payload = _fetch_json(ALL_MONTH_FEED)
    all_feats = payload.get("features", [])
    start_ms = int(dt.datetime(start.year, start.month, start.day, tzinfo=dt.timezone.utc).timestamp() * 1000)
    # end is inclusive of the whole day
    end_dt = dt.datetime(end.year, end.month, end.day, tzinfo=dt.timezone.utc) + one_day
    end_ms = int(end_dt.timestamp() * 1000)
    filtered = [
        f for f in all_feats
        if (f.get("properties") or {}).get("time") is not None
        and start_ms <= f["properties"]["time"] < end_ms
    ]
    print(f"  all_month feed: {len(all_feats)} events, {len(filtered)} within {start}..{end}", file=sys.stderr)
    return filtered


def load_rows(rows: list[dict]) -> int:
    if not rows:
        print("No rows to load.", file=sys.stderr)
        return 0

    client = bigquery.Client(project=PROJECT)

    # Ensure the dataset/table exist; create the table with our schema on first run.
    table = bigquery.Table(TABLE_REF, schema=SCHEMA)
    table = client.create_table(table, exists_ok=True)

    job_config = bigquery.LoadJobConfig(
        schema=SCHEMA,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
    )
    job = client.load_table_from_json(rows, TABLE_REF, job_config=job_config)
    job.result()  # wait for completion; raises on failure
    print(f"Appended {len(rows)} rows to {TABLE_REF}", file=sys.stderr)
    return len(rows)


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--start",
        type=lambda s: dt.date.fromisoformat(s),
        help="Backfill start date (YYYY-MM-DD). Triggers backfill mode.",
    )
    parser.add_argument(
        "--end",
        type=lambda s: dt.date.fromisoformat(s),
        help="Backfill end date (YYYY-MM-DD, inclusive). Triggers backfill mode.",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = _parse_args(argv)
    ingested_at = dt.datetime.now(tz=dt.timezone.utc).isoformat()

    if args.start or args.end:
        if not (args.start and args.end):
            print("Backfill requires both --start and --end.", file=sys.stderr)
            return 2
        if args.start > args.end:
            print("--start must be on or before --end.", file=sys.stderr)
            return 2
        print(f"Backfilling {args.start} .. {args.end} (M>={BACKFILL_MIN_MAGNITUDE})", file=sys.stderr)
        features = fetch_backfill(args.start, args.end)
    else:
        print("Incremental pull: past 24 hours, all magnitudes", file=sys.stderr)
        features = fetch_incremental()

    rows = _flatten(features, ingested_at)
    load_rows(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
