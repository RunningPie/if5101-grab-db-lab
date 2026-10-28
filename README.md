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
- Comparison of database technology candidates before selecting the primary RDBMS

**Current status:** Initial repository scaffold. The relational schema, data generators, queries, and benchmark runner are planned work, not included in this starter.

## Database options

The team is currently evaluating two RDBMS alternatives. The Docker Compose configurations are independent, and either database can be used without installing its server directly on the host.

| RDBMS | Docker image | Default host port | Compose file |
| --- | --- | --- | --- |
| PostgreSQL | `postgres:17` | `5432` | `docker/compose.postgres.yaml` |
| Firebird SQL | `firebirdsql/firebird:5.0.4` | `3050` | `docker/compose.firebird.yaml` |

The images are pinned to named release tags for consistency. For fully immutable builds, pin an image digest after validation. Docker standardizes the database runtime, but performance still depends on host hardware and resource limits.

## Prerequisites

- [Git](https://git-scm.com/)
- [Docker Engine](https://docs.docker.com/engine/) or [Docker Desktop](https://www.docker.com/products/docker-desktop/) with Docker Compose v2
- **Recommended:** [DBeaver Community](https://dbeaver.io/) as a GUI SQL client for both PostgreSQL and Firebird

DBeaver is optional. It provides a shared graphical workflow without requiring every contributor to learn Firebird's command-line tools. DBeaver may request a JDBC driver download when the connection is first created.

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

3. Start your preferred database:

   **PostgreSQL**

   ```bash
   docker compose --env-file .env -f docker/compose.postgres.yaml up -d
   docker compose -f docker/compose.postgres.yaml ps
   ```

   **Firebird**

   ```bash
   docker compose --env-file .env -f docker/compose.firebird.yaml up -d
   docker compose -f docker/compose.firebird.yaml ps
   ```

4. Open DBeaver and select **Database → New Database Connection**. Select the relevant driver, enter the connection parameters below, and choose **Test Connection**.

### DBeaver connection settings

| Setting | PostgreSQL | Firebird |
| --- | --- | --- |
| Driver | PostgreSQL | Firebird |
| Host | `127.0.0.1` | `127.0.0.1` |
| Port | `POSTGRES_PORT` (default `5432`) | `FIREBIRD_PORT` (default `3050`) |
| Database | `POSTGRES_DB` (default `grab_lab`) | `/var/lib/firebird/data/grab_lab.fdb`* |
| Username | `POSTGRES_USER` | `SYSDBA` |
| Password | `POSTGRES_PASSWORD` | `FIREBIRD_ROOT_PASSWORD` |

*For Firebird, the database is a **path inside the container**, not a file path on your host computer. If `FIREBIRD_DATABASE` was changed, replace `grab_lab.fdb` with that filename. In DBeaver select a **server/remote** Firebird connection (not embedded/local-file mode). The exact field name depends on the JDBC driver.

These databases are initially empty: running the Compose file does **not** create the project's relational tables or populate sample data.

## Container lifecycle

Replace the Compose path with `docker/compose.firebird.yaml` for Firebird.

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

Each RDBMS uses its own Compose project name and persistent Docker volume. Both can run simultaneously when their mapped host ports are available. Changes to SQL files do not automatically migrate an existing database: apply migrations explicitly or reset your local database when appropriate.

## Repository layout

```text
grab-db-lab/
├── README.md
├── .env.example
├── .gitignore
├── docker/
│   ├── compose.postgres.yaml
│   └── compose.firebird.yaml
├── docs/
│   └── team-setup.md          # Contributor guide
├── sql/                        # Planned: schema and queries by DBMS
├── scripts/                    # Planned: generator, orchestration, benchmarks
├── config/                     # Planned: dataset profiles
└── results/                    # Planned: summarized experiment outputs
```

## Reproducibility and collaboration

The Git repository synchronizes source code and configuration **not live database state**. Each contributor runs a local database with its own persistent volume.

Synthetic data generation will use versioned dataset profiles and fixed random seeds. Benchmark results should be collected on a designated host and documented with hardware specifications, dataset sizes, query settings, and repetitions.

For contributor conventions and troubleshooting, see [Team setup guide](docs/team-setup.md).

## References

- [PostgreSQL Docker image](https://hub.docker.com/_/postgres)
- [Firebird official Docker images](https://github.com/FirebirdSQL/firebird-docker)
- [DBeaver documentation: Creating connections](https://dbeaver.com/docs/dbeaver/Create-Connection/)
