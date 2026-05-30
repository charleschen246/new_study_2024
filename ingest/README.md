# USGS earthquake ingest → Elementary anomaly detection

A live, free, no-auth data source that grows every day so Elementary's
`volume_anomalies` test has a real time series to learn a baseline from and flag
deviations. Daily earthquake counts vary naturally and occasionally spike, which
is exactly the signal volume anomaly detection looks for.

```
USGS GeoJSON feed
  → ingest/usgs_earthquakes.py        (append rows to BigQuery)
  → dbt_my_project.raw_usgs_earthquakes
  → stg_usgs__earthquakes             (view: dedup by id, cast, derive event_date)
  → fct_earthquakes                   (table in the marts schema)
  → elementary.volume_anomalies on event_time
```

## One-time setup

### 1. Backfill history (so the anomaly baseline exists from day one)

`volume_anomalies` is configured with `days_back: 90`, so it needs ~3 months of
history before it can score the latest day. Run the backfill once locally:

```powershell
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\Users\cchen\OneDrive\Desktop\Work & Data\dbt_projects\my-project-111-257618-5a62b346093d.json"

# ~3.5 months of M2.5+ events
python ingest/usgs_earthquakes.py --start 2026-01-15 --end 2026-05-30

# then one incremental pull to confirm the daily path works
python ingest/usgs_earthquakes.py
```

Build and test:

```powershell
$env:DBT_PROFILES_DIR = "."
dbt run  --select stg_usgs__earthquakes fct_earthquakes
dbt test --select fct_earthquakes
edr report --profiles-dir .   # fct_earthquakes appears with a volume time series
```

### 2. Add the GitHub secret (enables the daily cron)

The CI workflow (`.github/workflows/daily_ingest.yml`) authenticates with a
service-account key stored as a repo secret. **This must be done manually** in the
GitHub UI:

1. Open the keyfile
   `C:\Users\cchen\OneDrive\Desktop\Work & Data\dbt_projects\my-project-111-257618-5a62b346093d.json`
   and copy its **entire** JSON contents.
2. In the repo: **Settings → Secrets and variables → Actions → New repository secret**.
3. Name it `GCP_SA_KEY`, paste the JSON, save.
4. Trigger the workflow once manually (**Actions → Daily USGS ingest → Run workflow**)
   to confirm a green run before relying on the 09:00 UTC cron.

## How it stays correct

- The script is **append-only**; the daily "past 24h" feed overlaps with previous
  pulls. `stg_usgs__earthquakes` collapses duplicates with
  `qualify row_number() over (partition by id order by ingested_at desc) = 1`,
  so re-ingesting the same quake is harmless.
- The raw table is created on first run with an explicit schema, so the very first
  ingest works against an empty dataset.

## Modes

| Command | What it does |
| --- | --- |
| `python ingest/usgs_earthquakes.py` | Incremental: past 24h, all magnitudes (daily cron). |
| `python ingest/usgs_earthquakes.py --start YYYY-MM-DD --end YYYY-MM-DD` | Backfill: historical M2.5+ events, paged by 30-day windows. |
