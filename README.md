# grab-db-lab

A reproducible relational database laboratory for the **IF5101 Data Management** course at Institut Teknologi Bandung (ITB).

This academic case study models the **Mobility & Fulfillment** domain of a Grab-like platform, translating an entity–relationship model into relational schemas, implementing SQL workloads, generating synthetic datasets, and evaluating query performance.

> **Disclaimer:** This is an independent educational project. It is not affiliated with, endorsed by, or based on internal databases of Grab. All generated datasets are synthetic.

## Project scope

- ER-to-relational mapping for a 13-entity Mobility & Fulfillment model
- Relational constraints and SQL DDL
- Ten read queries and ten write queries, including complex workloads
- Synthetic data generation at multiple scales
- Repeatable query execution and performance analysis

**Current status:** The PostgreSQL schema is partially implemented. Data generators, queries, and the benchmark runner are planned.

## Database

The project uses PostgreSQL 17 via `docker/compose.postgres.yaml`, with host port `5432` by default. The Docker image uses a named release tag; pin an image digest after validation for a fully immutable build. Performance still depends on host hardware and resource limits.

## Prerequisites

- [Git](https://git-scm.com/)
- [Docker Engine](https://docs.docker.com/engine/) or [Docker Desktop](https://www.docker.com/products/docker-desktop/) with Docker Compose v2
- **Recommended:** [DBeaver Community](https://dbeaver.io/) as a GUI SQL client for PostgreSQL

DBeaver is optional and may request a JDBC driver download when the connection is first created.

## Python Environment Setup

This project uses [uv](https://docs.astral.sh/uv/) for Python dependency management and reproducible development environments.

### Prerequisites

- Python 3.13 (managed automatically by uv)
- [uv](https://docs.astral.sh/uv/getting-started/installation/)
- Docker with Docker Compose v2
- DBeaver Community (recommended SQL client)

### Initial Setup

After cloning the repository, run:

```bash
uv sync --locked
```

This command creates a local `.venv` directory and installs dependencies according to `pyproject.toml` and `uv.lock`.

If Python 3.13 is not installed, uv can install the required Python version automatically when configured to use managed Python installations.

### Running Python Scripts

Use `uv run` to execute Python commands within the project environment:

```bash
uv run python scripts/orchestrator.py --help
```

With PostgreSQL running and `.env` configured, initialize an empty database with:

```bash
uv run python scripts/orchestrator.py
```

The default command checks the connection and applies `sql/DDL` in a single transaction. It does not generate data or run benchmarks. The schema is not a migration: rerunning initialization on an existing schema will fail without replacing it. The explicit `seed`, `benchmark`, and `run` commands are reserved for future implementation and currently make no changes.

### Dependency Management

To add a runtime dependency:

```bash
uv add <package-name>
```

To add a development dependency:

```bash
uv add --dev <package-name>
```

Always commit changes to both `pyproject.toml` and `uv.lock`.

Do not commit the `.venv/` directory.

## Quick start

Run these commands **from the repository root**.

1. Copy the sample configuration:

   ```bash
   cp .env.example .env
   ```

   On Windows PowerShell:

   ```powershell
   Copy-Item .env.example .env
   ```

2. Replace all sample passwords in `.env` with private local passwords. **Never commit `.env`.**

3. Start PostgreSQL:

   ```bash
   docker compose --env-file .env -f docker/compose.postgres.yaml up -d
   docker compose -f docker/compose.postgres.yaml ps
   ```

4. Open DBeaver and select **Database → New Database Connection**. Select the PostgreSQL driver, enter the connection parameters below, and choose **Test Connection**.

### DBeaver connection settings

| Setting | Value |
| --- | --- |
| Driver | PostgreSQL |
| Host | `127.0.0.1` |
| Port | `POSTGRES_PORT` (default `5432`) |
| Database | `POSTGRES_DB` (default `grab_lab`) |
| Username | `POSTGRES_USER` |
| Password | `POSTGRES_PASSWORD` |

The database is initially empty: running Compose does **not** create the project's relational tables or populate sample data. Run `uv run python scripts/orchestrator.py` to create the currently implemented schema.

## Container lifecycle

```bash
# Show status
docker compose -f docker/compose.postgres.yaml ps

# Inspect logs
docker compose -f docker/compose.postgres.yaml logs -f

# Stop and remove containers, preserving the database volume
docker compose -f docker/compose.postgres.yaml down

# Start again using the existing volume
docker compose -f docker/compose.postgres.yaml up -d

# DANGER: delete the database volume and all local database contents
docker compose -f docker/compose.postgres.yaml down -v
```

Changes to SQL files do not automatically migrate an existing database: apply migrations explicitly or reset your local database when appropriate.

## Repository layout

```text
grab-db-lab/
├── README.md
├── .env.example
├── .gitignore
├── docker/
│   └── compose.postgres.yaml
├── docs/
│   └── team-setup.md          # Contributor guide
├── sql/                        # PostgreSQL schema and planned queries
├── scripts/                    # Schema orchestrator and planned experiment scripts
├── config/                     # Planned: dataset profiles
└── results/                    # Planned: summarized experiment outputs
```

## Reproducibility and collaboration

The Git repository synchronizes source code and configuration **not live database state**. Each contributor runs a local database with its own persistent volume.

Synthetic data generation will use versioned dataset profiles and fixed random seeds. Benchmark results should be collected on a designated host and documented with hardware specifications, dataset sizes, query settings, and repetitions.

For contributor conventions and troubleshooting, see [Team setup guide](docs/team-setup.md).

## References

- [PostgreSQL Docker image](https://hub.docker.com/_/postgres)
- [DBeaver documentation: Creating connections](https://dbeaver.com/docs/dbeaver/Create-Connection/)
