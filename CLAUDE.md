# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A dbt project (`my_new_project`, profile `my_project`) targeting **BigQuery** (`my-project-111-257618.dbt_my_project`). Two unrelated subject areas live side by side: a Superstore sales star schema and the Iris dataset.

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
```

`dbt debug` validates the BigQuery connection.

## Architecture

### Layers (configured in `dbt_project.yml`)

- `models/staging/` — materialized as **views**. One subfolder per source system.
  - `super_store_analysis/` — renames BigQuery's backtick-quoted column names (`` `Row ID` ``, `` `Order Date` ``, etc.) into snake_case and casts numerics. This rename layer is the only place those quoted identifiers appear.
  - `iris/` — typed/cleaned Iris rows from `source('iris', 'raw_iris')`.
- `models/marts/` — materialized as **tables** in the `marts` schema (i.e. `dbt_my_project_marts` on BigQuery).
  - Star schema for Superstore: `dim_customers`, `dim_products`, `dim_geography`, `dim_dates`, `fct_orders`. Surrogate keys are MD5 hashes of natural keys.
  - `fct_orders` joins geography on the composite `(country, city, state, postal_code)` and joins dates by parsing the source's `%m/%d/%Y` strings. The `is_returned` flag comes from a left join against `stg_super_store_analysis__returns` filtered to `returned = 'Yes'`. Exposes both `order_date_key`/`ship_date_key` (FKs into `dim_dates`) and real `order_date`/`ship_date` DATE columns — the latter exist so Elementary's `volume_anomalies` test has a timestamp to bucket on.
  - `mart_profitability_by_region` is a downstream aggregate that reads `fct_orders` + `dim_geography` and uses `QUALIFY ROW_NUMBER()` (BigQuery-specific) to pick best/worst states per region.
  - Iris star: `dim_iris_species` + `fct_iris_measurements`.

### Sources

Defined in `models/staging/source.yml` (super_store_analysis: `Orders`, `returns`) and `models/staging/iris/source.yml` (iris: `raw_iris`). Both point at the same `dbt_my_project` dataset that holds the raw seed-loaded tables.

### Tests

Schema tests are co-located with model definitions in `models/marts/schema.yml` (and the staging `schema.yml` files). Includes `unique`/`not_null` on surrogate keys, `accepted_values` on segment/category/region, and `relationships` from `fct_orders` FKs back to each dimension. `fct_orders` also has `elementary.volume_anomalies` configured on `order_date` (daily buckets, 90-day window, sensitivity 3) — see [Elementary observability](#elementary-observability). The standalone `tests/` directory is empty — add singular tests there if needed.

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

## Gotchas

- BigQuery is case- and backtick-sensitive about the source `Orders` table — only reference it via `{{ source('super_store_analysis', 'Orders') }}`, never as a raw identifier.
- `profiles.yml` and `*.json` (keyfiles) are gitignored. Don't add them back.
- A merge from `aaa_fix` recently lowercased model `ref()`s — keep new model filenames lowercase to match.
- The BigQuery project has billing linked, so Elementary's DML hooks (which INSERT into artifact/result tables) work normally. If a future error mentions *"Billing has not been enabled for this project"*, the billing link may have been removed — re-link at `console.cloud.google.com/billing/linkedaccount?project=my-project-111-257618`.
- Windows long-path support is enabled on this machine. `edr report` needs it because the elementary monitor unpacks its internal dbt packages deep inside `.venv/Lib/site-packages/elementary/monitor/dbt_project/dbt_packages/...`, which exceeds the 260-char MAX_PATH when OneDrive's path is added. If long paths gets reset (registry: `HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled`), `edr` will fail with a tarfile `FileNotFoundError`.
