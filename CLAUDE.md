# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A dbt project (`my_new_project`, profile `my_project`) targeting **BigQuery** (`my-project-111-257618.dbt_my_project`). Three unrelated subject areas live side by side: a Superstore sales star schema, the Iris dataset, and a **live USGS earthquake feed** (ingested daily to give Elementary's anomaly tests a real, growing time series — see [Live earthquake feed](#live-earthquake-feed-usgs)).

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
dbt run --select +fct_orders

# Single model, downstream tests only
dbt test --select fct_orders

# Run just the elementary volume_anomalies test on fct_orders
dbt test --select fct_orders,test_name:volume_anomalies

# Load CSVs in seeds/ (Orders.csv, returns.csv) into BigQuery
dbt seed

# Compile without executing — useful for inspecting rendered SQL in target/
dbt compile

# Wipe target/ and dbt_packages/
dbt clean

# Generate the Elementary HTML dashboard at edr_target/elementary_report.html
edr report --profiles-dir .

# Ingest the USGS earthquake feed (needs GOOGLE_APPLICATION_CREDENTIALS set)
python ingest/usgs_earthquakes.py                          # incremental: past 24h
python ingest/usgs_earthquakes.py --start 2026-04-30 --end 2026-05-29  # backfill a range

# Build the earthquake chain + run its anomaly test
dbt run  --select stg_usgs__earthquakes fct_earthquakes
dbt test --select fct_earthquakes
```

`dbt debug` validates the BigQuery connection.

## Architecture

### Layers (configured in `dbt_project.yml`)

- `models/staging/` — materialized as **views**. One subfolder per source system.
  - `super_store_analysis/` — renames BigQuery's backtick-quoted column names (`` `Row ID` ``, `` `Order Date` ``, etc.) into snake_case and casts numerics. This rename layer is the only place those quoted identifiers appear.
  - `iris/` — typed/cleaned Iris rows from `source('iris', 'raw_iris')`.
  - `usgs/` — `stg_usgs__earthquakes` reads `source('usgs', 'raw_usgs_earthquakes')`, dedups overlapping daily pulls with `QUALIFY ROW_NUMBER() OVER (PARTITION BY id ORDER BY ingested_at DESC) = 1`, casts numerics, derives `event_date = DATE(event_time)`, and builds the `earthquake_key` surrogate via `dbt_utils.generate_surrogate_key(['id'])`.
- `models/marts/` — materialized as **tables** in the `marts` schema (i.e. `dbt_my_project_marts` on BigQuery).
  - Star schema for Superstore: `dim_customers`, `dim_products`, `dim_geography`, `dim_dates`, `fct_orders`. Surrogate keys are MD5 hashes of natural keys.
  - `fct_orders` joins geography on the composite `(country, city, state, postal_code)` and joins dates by parsing the source's `%m/%d/%Y` strings. The `is_returned` flag comes from a left join against `stg_super_store_analysis__returns` filtered to `returned = 'Yes'`. Exposes both `order_date_key`/`ship_date_key` (FKs into `dim_dates`) and real `order_date`/`ship_date` DATE columns — the latter exist so Elementary's `volume_anomalies` test has a timestamp to bucket on.
  - `mart_profitability_by_region` is a downstream aggregate that reads `fct_orders` + `dim_geography` and uses `QUALIFY ROW_NUMBER()` (BigQuery-specific) to pick best/worst states per region.
  - Iris star: `dim_iris_species` + `fct_iris_measurements`.
  - `fct_earthquakes` — one row per USGS earthquake event (selects straight from `stg_usgs__earthquakes`). Currently a leaf node; nothing reads from it yet. Carries `event_time` (TIMESTAMP) which the `volume_anomalies` test buckets on.

### Sources

Defined in `models/staging/source.yml` (super_store_analysis: `Orders`, `returns`), `models/staging/iris/source.yml` (iris: `raw_iris`), and `models/staging/usgs/source.yml` (usgs: `raw_usgs_earthquakes`). All point at the same `dbt_my_project` dataset. Note `raw_usgs_earthquakes` is **not** seed-loaded — it's populated by the Python ingest script (append-only), and dbt only reads it as a source.

### Tests

Schema tests are co-located with model definitions in `models/marts/schema.yml` (and the staging `schema.yml` files). Includes `unique`/`not_null` on surrogate keys, `accepted_values` on segment/category/region, and `relationships` from `fct_orders` FKs back to each dimension. Two `elementary.volume_anomalies` tests are configured (daily buckets, 90-day window, sensitivity 3) — see [Elementary observability](#elementary-observability):

- `fct_orders` on `order_date` (static seed data — baseline doesn't grow).
- `fct_earthquakes` on `event_time`, with `where_expression: "event_time < timestamp_trunc(current_timestamp(), day)"` so the in-progress current day's partial volume isn't flagged as a false anomaly. This is the test the live feed exists to make meaningful.

The standalone `tests/` directory is empty — add singular tests there if needed.

### Macros

`macros/round.sql` defines `rounding`, `generate_profit_model`, and `generate_profit_model_1`. Note `generate_profit_model_1` references `quanity` (typo) — preserve or fix deliberately, it's not currently called.

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

### Live earthquake feed (USGS)

`ingest/usgs_earthquakes.py` fetches USGS earthquake events and **appends** them to `dbt_my_project.raw_usgs_earthquakes` (creates the table with an explicit schema on first run). Append-only by design; dedup happens downstream in `stg_usgs__earthquakes`. Two modes:

- **Incremental (default):** the static `all_day.geojson` summary feed (past 24h, all magnitudes). This is what the daily job runs.
- **Backfill (`--start`/`--end`):** tries the FDSN query API, then **falls back to the static `all_month.geojson` feed** (trailing ~30 days, filtered client-side) when the query API is unreachable. See gotcha below.

Auth uses Application Default Credentials — set `GOOGLE_APPLICATION_CREDENTIALS` to the keyfile (`requirements.txt` pins `requests` + `google-cloud-bigquery` alongside dbt). See `ingest/README.md` for the full setup including the one-time backfill.

**Daily automation** — `.github/workflows/daily_ingest.yml` runs on `ubuntu-latest` at `cron: "0 9 * * *"` (**09:00 UTC**) and on manual `workflow_dispatch`. It writes the keyfile from the `GCP_SA_KEY` repo secret, generates a CI `profiles.yml` under `ci/` at runtime (the local one is gitignored), then runs:

```
python ingest/usgs_earthquakes.py
dbt deps
dbt run  --select stg_usgs__earthquakes fct_earthquakes
dbt test --select fct_earthquakes
```

Free on this **public** repo (unlimited Actions minutes; BigQuery stays in the free tier at this volume). The `dbt run` is scoped to the earthquake chain only — `fct_earthquakes` is currently a leaf, so nothing downstream goes stale. **If a model is ever built on top of `fct_earthquakes`, change the selector to `stg_usgs__earthquakes+`** (trailing `+` = include downstream) so the new model refreshes too.

## Gotchas

- BigQuery is case- and backtick-sensitive about the source `Orders` table — only reference it via `{{ source('super_store_analysis', 'Orders') }}`, never as a raw identifier.
- `profiles.yml`, `*.json` (keyfiles), and `edr_target/` (generated dashboard) are gitignored. Don't add them back.
- **USGS FDSN query API returns HTTP 404 from some networks** (it did during this project's setup) — only the static summary-feed CDN (`earthquakes/feed/v1.0/summary/*.geojson`) is reliably reachable. The ingest script's backfill auto-falls back to the `all_month` feed, so it works in both restricted and open networks. The static feed only covers ~30 days, which is enough to seed an anomaly baseline.
- The `volume_anomalies` test will false-positive on a live feed's **in-progress current day** (partial volume reads as a drop). The `where_expression` on `fct_earthquakes` excludes it; apply the same guard to any future live anomaly test.
- GitHub Actions cron is **UTC and does not adjust for DST** — `0 9 * * *` is always 09:00 UTC regardless of local time. Scheduled runs may be delayed under load. GitHub also disables scheduled workflows in a repo after **60 days without commits** — any push (or a manual `workflow_dispatch`) resets the clock.
- A merge from `aaa_fix` recently lowercased model `ref()`s — keep new model filenames lowercase to match.
- The BigQuery project has billing linked, so Elementary's DML hooks (which INSERT into artifact/result tables) work normally. If a future error mentions *"Billing has not been enabled for this project"*, the billing link may have been removed — re-link at `console.cloud.google.com/billing/linkedaccount?project=my-project-111-257618`.
- Windows long-path support is enabled on this machine. `edr report` needs it because the elementary monitor unpacks its internal dbt packages deep inside `.venv/Lib/site-packages/elementary/monitor/dbt_project/dbt_packages/...`, which exceeds the 260-char MAX_PATH when OneDrive's path is added. If long paths gets reset (registry: `HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled`), `edr` will fail with a tarfile `FileNotFoundError`.
