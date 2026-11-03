# Scripts

Run these from the repository root with `uv run`, after `uv sync --locked`.

- `orchestrator.py init` creates the schema from `sql/DDL`.
- `orchestrator.py seed --profile <name>` generates the profile's data and loads it.
- Both commands run in one transaction. Each fails without changing anything if the database already has the schema or the data.
- `orchestrator.py benchmark` and `run` are placeholders. To benchmark, use `benchmark.py` (see [Benchmark](#benchmark)).
- `generate_data.py` is the data generator that `seed` uses.

## One database per profile

| Profile | Database | Service orders | Size | Seed time |
| --- | --- | --- | --- | --- |
| `small` | `grab_lab_small` | 10,000 | 16 MB | a few seconds |
| `medium` | `grab_lab_medium` | 100,000 | 90 MB | about 20 seconds |
| `large` | `grab_lab_large` | 1,000,000 | 0.8 GB | about 3 minutes |

Create the database, then initialize and seed it. `POSTGRES_DB` overrides `.env` for that command only:

```bash
docker compose --env-file .env -f docker/compose.postgres.yaml exec postgres \
  sh -c 'createdb -U "$POSTGRES_USER" grab_lab_small'
POSTGRES_DB=grab_lab_small uv run python scripts/orchestrator.py init
POSTGRES_DB=grab_lab_small uv run python scripts/orchestrator.py seed --profile small
```

On Windows PowerShell:

```powershell
docker compose --env-file .env -f docker/compose.postgres.yaml exec postgres sh -c 'createdb -U "$POSTGRES_USER" grab_lab_small'
$env:POSTGRES_DB = 'grab_lab_small'
uv run python scripts/orchestrator.py init
uv run python scripts/orchestrator.py seed --profile small
Remove-Item Env:POSTGRES_DB
```

Repeat for `medium` and `large`. To see every database in DBeaver, enable **Show all databases** under **Edit Connection → Main**.

To rebuild a profile, recreate its database, then run `init` and `seed` again:

```bash
docker compose --env-file .env -f docker/compose.postgres.yaml exec postgres \
  sh -c 'dropdb -U "$POSTGRES_USER" --if-exists --force grab_lab_small && createdb -U "$POSTGRES_USER" grab_lab_small'
```

## The generated data

- **Configuration:** `config/dataset_profile.yaml` sets the seed, the order period, and the row counts of each profile.
- **Snapshot:** each order is simulated from being placed until it is completed or cancelled, then recorded as it stands at the end of the period. Orders from the final hour are still in progress.
- **Realism beyond the DDL:**
  - Trips stay within one city, and each vehicle fits its service.
  - No driver or customer is in two trips at once.
  - Orders from the final day use only active areas, open outlets and active drivers.
- **Reproducibility:** the same config, generator and `uv.lock` give identical data on any machine. Each profile is generated independently.
- **CSV export:** to inspect the data without a database, run `uv run python scripts/generate_data.py --profile small --output-dir /tmp/grab_small`.
- **Changing the generator:** keep it in line with `docs/data-dictionary.md`, and rebuild at least `small` afterwards to check it against the constraints.

## Benchmark

`benchmark.py` runs the queries in `sql/DML/01_read_queries.sql` and `sql/DML/02_write_queries.sql` exactly as written, following [docs/benchmarking.md](../docs/benchmarking.md). A query starts at its header comment, such as `-- R1: Title`, and ends at the next one. To add a query, give it such a header.

```bash
POSTGRES_DB=grab_lab_small uv run python scripts/benchmark.py --profile small
```

On Windows PowerShell:

```powershell
$env:POSTGRES_DB = 'grab_lab_small'
uv run python scripts/benchmark.py --profile small
Remove-Item Env:POSTGRES_DB
```

- **Disconnect DBeaver first.** The write benchmark copies the database, and PostgreSQL copies a database only when no one else is connected to it. The script stops early if someone is.
- **Read queries:** each one runs in its own session. A warm-up run with `EXPLAIN (ANALYZE, BUFFERS)` records its plan, then 5 timed runs follow.
- **Write queries:** they change data and depend on each other, for example W2 needs W1 and W8 needs W7. So every run, including one warm-up run that records the plans, runs W1–W10 in order on a fresh copy of the database, named `<database>_bench`. The copy is dropped at the end, so the profile's database never changes.
- **Measurements:** a query's time is the sum of its statements' psql `\timing`, including `BEGIN` and `COMMIT`. Rows are the rows a read returns, or the rows a write's statements change.
- **Options:** `--runs <n>` changes the number of timed runs. `--only reads` or `--only writes` runs one workload, and `--only reads` doesn't need DBeaver disconnected.
- **Checks:** the script stops if the database doesn't have the profile's number of service orders, so results are never labelled with the wrong profile.
- **Results:** `results/<profile>_<timestamp>.csv` has one row per timed run. The `.json` file has the summary, the plans, the PostgreSQL version and the host. Git ignores both.
