# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A dbt project (`my_new_project`, profile `my_project`) targeting **BigQuery** (`my-project-111-257618.dbt_my_project`). The project is a single live-data showcase: a USGS earthquake feed, ingested daily and monitored with Elementary anomaly tests. (Earlier static Superstore and Iris subject areas were removed — the project deliberately keeps only the live-fed pipeline.)

`profiles.yml` lives in the repo root (gitignored) and points at a local service-account keyfile at `C:\Users\cchen\OneDrive\Desktop\Work & Data\dbt_projects\my-project-111-257618-5a62b346093d.json` — dbt commands run from the repo root pick it up via `DBT_PROFILES_DIR=.` or by being launched from this directory. The venv is at `.venv/`. `profiles.yml` defines two profiles: `my_project` (the dbt project) and `elementary` (the `edr` CLI, pointing at the `dbt_my_project_elementary` dataset).

## Common commands

```bash
# Activate venv first (PowerShell)
.venv\Scripts\Activate.ps1

# Install dbt packages declared in packages.yml (elementary, dbt_utils)
dbt deps

# Full build (seeds → models → tests)
dbt build

# Run all models
dbt run

# Single model + its upstream dependencies
dbt run --select +fct_earthquakes

# Single model, downstream tests only
dbt test --select fct_earthquakes

# Run just the elementary volume_anomalies test on fct_earthquakes
dbt test --select fct_earthquakes,test_name:volume_anomalies

# Pull the latest USGS feed into raw_usgs_earthquakes (also run daily by CI)
python ingest/usgs_earthquakes.py

# Compile without executing — useful for inspecting rendered SQL in target/
dbt compile

# Wipe target/ and dbt_packages/
dbt clean

# Generate the Elementary HTML dashboard at edr_target/elementary_report.html
edr report --profiles-dir .
```

`dbt debug` validates the BigQuery connection.

## Architecture

### Layers (configured in `dbt_project.yml`)

- `models/staging/` — materialized as **views**. One subfolder per source system.
  - `usgs/` — `stg_usgs__earthquakes` typed/cleaned from `source('usgs', 'raw_usgs_earthquakes')`. Casts `event_time`/`magnitude`/`depth_km`/`lat`/`lon`, and dedupes the overlapping daily pulls with `qualify row_number() over (partition by id order by ingested_at desc) = 1`.
- `models/marts/` — materialized as **tables** in the `marts` schema (i.e. `dbt_my_project_marts` on BigQuery).
  - `fct_earthquakes` — one row per USGS event (MD5 surrogate key on the event `id`). Exposes `event_time` (TIMESTAMP) and `event_date` (DATE) so Elementary's `volume_anomalies` test has a column to bucket on.

### Sources

Defined in `models/staging/usgs/source.yml` (usgs: `raw_usgs_earthquakes`), pointing at the `dbt_my_project` dataset. `raw_usgs_earthquakes` is **append-only**, written by `ingest/usgs_earthquakes.py` (one row per event-id per ingestion; deduped in staging).

### Tests

Schema tests are co-located with model definitions in `models/marts/schema.yml`. Includes `unique`/`not_null` on the surrogate/natural keys. `fct_earthquakes` also has `elementary.volume_anomalies` configured on `event_time` (daily buckets, 90-day window, sensitivity 3, with a `where_expression` that excludes the still-ingesting current day) — see [Elementary observability](#elementary-observability). The standalone `tests/` directory is empty — add singular tests there if needed.

### Elementary observability

`packages.yml` pins `elementary-data/elementary` (>=0.24.0, <0.25.0). It contributes ~30 models materialized as tables into `dbt_my_project_elementary`. The `dbt_project.yml` block:

```yaml
elementary:
  +schema: elementary
  +materialized: table
```

resolves to the `dbt_my_project_elementary` dataset on BigQuery.

Workflow:
1. `dbt deps` — installs Elementary + dbt_utils into `dbt_packages/`.
2. `dbt run --select elementary` — builds Elementary's internal artifact/metrics tables.
3. `dbt test` — runs your tests; Elementary's `on-run-end` hook persists results to `elementary_test_results`, `dbt_run_results`, etc.
4. `edr report --profiles-dir .` — reads from `dbt_my_project_elementary` and writes the static HTML dashboard to `edr_target/elementary_report.html`.

The `edr` CLI (separate Python package `elementary-data[bigquery]`, already installed in `.venv`) requires a profile named `elementary` in `profiles.yml` pointing at the same BigQuery project + the `dbt_my_project_elementary` dataset. Both profiles share the same service-account keyfile.

## Gotchas

- `raw_usgs_earthquakes` is append-only — the daily ingest never truncates it, so every model that reads it must dedupe by event `id` (staging already does). Don't assume one row per quake in the raw table.
- `profiles.yml` and `*.json` (keyfiles) are gitignored. Don't add them back.
- Keep new model filenames lowercase to match the existing convention.
- The BigQuery project has billing linked, so Elementary's DML hooks (which INSERT into artifact/result tables) work normally. If a future error mentions *"Billing has not been enabled for this project"*, the billing link may have been removed — re-link at `console.cloud.google.com/billing/linkedaccount?project=my-project-111-257618`.
- Windows long-path support is enabled on this machine. `edr report` needs it because the elementary monitor unpacks its internal dbt packages deep inside `.venv/Lib/site-packages/elementary/monitor/dbt_project/dbt_packages/...`, which exceeds the 260-char MAX_PATH when OneDrive's path is added. If long paths gets reset (registry: `HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled`), `edr` will fail with a tarfile `FileNotFoundError`.
