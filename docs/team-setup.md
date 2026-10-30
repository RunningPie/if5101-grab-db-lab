# Team Setup and Collaboration Guide

This document is for contributors to the IF5101 group project.
Update this file as the configuration evolves, but **DO NOT** put real passwords or private details here.

## 1. Local environment

1. Install Git, Docker with Compose v2, and [DBeaver Community](https://dbeaver.io/).
2. Clone the repository.
3. Copy `.env.example` to `.env`.
4. Set unique local passwords in `.env`. This file is ignored by Git.
5. From the repository root, start PostgreSQL using the commands in the public [README](../README.md).
6. Confirm the container is running:

   ```bash
   docker compose -f docker/compose.postgres.yaml ps
   ```

7. Open DBeaver and connect with the following settings:

| Property | PostgreSQL |
| --- | --- |
| Connection mode | Server |
| Host | `127.0.0.1` |
| Port | `POSTGRES_PORT` from `.env` |
| Database | `POSTGRES_DB` from `.env` |
| User | `POSTGRES_USER` from `.env` |
| Password | `POSTGRES_PASSWORD` from `.env` |

DBeaver may ask to install a JDBC driver on the first connection. Use **Test Connection** before saving.

## Python Development Workflow

All contributors must use uv to manage Python dependencies and execute project scripts.

### Setting Up the Environment

After cloning the repository or pulling changes to its Python dependencies, run:

```bash
uv sync --locked
```

Use `uv run` to execute Python scripts and tests without manually activating the virtual environment.

```bash
uv run pytest
```

### Adding Dependencies

If a new Python library is needed, add it through uv:

```bash
uv add faker
```

For development tools:

```bash
uv add --dev pytest
```

Commit both `pyproject.toml` and `uv.lock` in the same pull request.

Avoid installing packages manually with `pip install` into the project environment because these changes are not necessarily reflected in the dependency declarations.

### Dependency Consistency

- Use the Python version specified in `.python-version`.
- Keep `uv.lock` under version control.
- Never commit `.venv/`.
- Run `uv sync --locked` after pulling changes that modify dependencies.
- Avoid maintaining a separate `requirements.txt` unless compatibility with external tooling requires it.

### Troubleshooting

**`uv` command not found:** Install uv using its official installation instructions and reopen your terminal.

**Dependency synchronization fails:** Check the Python version, internet connectivity, and whether `pyproject.toml` and `uv.lock` are synchronized.

**A package works locally but fails on another machine:** Verify that it was added using `uv add` and that the updated lockfile was committed.

## 2. Working agreements

- Use branches for independent changes; create pull requests before merging into `main`.
- Coordinate column names, primary keys, foreign keys, and relationship constraints before implementation.
- Follow consistent `snake_case` naming conventions for tables and columns.
- Keep PostgreSQL schema and queries in `sql/postgres/`.
- Do not commit `.env`, database volume contents or large generated datasets.
- Prefer reproducible scripts and versioned dataset parameters over manually shared SQL dumps.

## 3. Proposed data ownership

| Owner | Entities |
| --- | --- |
| Dama | `customers`, `service_orders`, `food_orders`, `mobility_orders`, `delivery_orders` |
| Ishak | `trips`, `driver_assignments`, `driver_partners`, `vehicles` |
| Nabil | `locations`, `service_areas`, `merchant_outlets`, `payments` |

This is the proposed assignment, not an enforcement mechanism. All members may write queries joining across domain boundaries.

## 4. Planned implementation milestones

- Finalize ER-to-relational mapping and foreign-key dependencies.
- Implement DDL and constraints.
- Implement data generation profiles and reproducible seed orchestration.
- Implement 10 read and 10 write queries.
- Benchmark query performance on a designated reference host and record methodology.

The PostgreSQL schema is partially implemented; data generation and benchmarking remain planned.

## 5. Troubleshooting

**Connection refused:** Check `docker compose ... ps` and `docker compose ... logs`. Ensure Docker is running and the port in `.env` matches DBeaver.

**Port in use:** Change `POSTGRES_PORT` in `.env`, recreate the container, and update DBeaver.

**Changed passwords do not work:** Existing database volumes often retain their initialized authentication state. Do not assume updating `.env` changes an existing user's password.

**Changed SQL has no effect:** The Compose file launches PostgreSQL; they do not apply or migrate project schema automatically.

**Need a clean local database:** Back up anything important, then use `docker compose -f <compose-file> down -v` to remove its Docker volume. This permanently deletes local data.

## 6. Benchmark protocol (to be finalized)

Use fixed dataset profiles, record database versions and host specs, and perform read and write workloads under repeatable conditions. Reset or restore database state between write benchmark cases as appropriate. Do not compare latency measurements from different laptops as if they were controlled results.
