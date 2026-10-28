# Team Setup and Collaboration Guide

This document is for contributors to the IF5101 group project.
Update this file as the configuration evolves, but **DO NOT** put real passwords or private details here.

## 1. Local environment

1. Install Git, Docker with Compose v2, and [DBeaver Community](https://dbeaver.io/).
2. Clone the repository.
3. Copy `.env.example` to `.env`.
4. Set unique local passwords in `.env`. This file is ignored by Git.
5. From the repository root, start either PostgreSQL or Firebird using the commands in the public [README](../README.md).
6. Confirm the container is running:

   ```bash
   docker compose -f docker/compose.postgres.yaml ps
   # or
   docker compose -f docker/compose.firebird.yaml ps
   ```

7. Open DBeaver and connect with the following settings:

| Property | PostgreSQL | Firebird |
| --- | --- | --- |
| Connection mode | Server | Remote/server (not embedded) |
| Host | `127.0.0.1` | `127.0.0.1` |
| Port | `POSTGRES_PORT` from `.env` | `FIREBIRD_PORT` from `.env` |
| Database | `POSTGRES_DB` from `.env` | `/var/lib/firebird/data/<FIREBIRD_DATABASE>` |
| User | `POSTGRES_USER` from `.env` | `SYSDBA` |
| Password | `POSTGRES_PASSWORD` from `.env` | `FIREBIRD_ROOT_PASSWORD` from `.env` |

DBeaver may ask to install a JDBC driver on the first connection. Use **Test Connection** before saving. The Firebird database path is inside the Docker container; it is not a Windows path.

## 2. Working agreements

- Use branches for independent changes; create pull requests before merging into `main`.
- Coordinate column names, primary keys, foreign keys, and relationship constraints before implementation.
- Follow consistent `snake_case` naming conventions for tables and columns.
- Keep PostgreSQL-specific and Firebird-specific SQL in separate folders when dialect differences require it.
- Do not commit `.env`, database volume contents, `.fdb` files, or large generated datasets.
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
- Select the primary RDBMS after a small proof of concept.
- Implement DDL and constraints.
- Implement data generation profiles and reproducible seed orchestration.
- Implement 10 read and 10 write queries.
- Benchmark query performance on a designated reference host and record methodology.

The `sql/`, `scripts/`, and `config/` directories are planned; their features are not included in the current starter.

## 5. Troubleshooting

**Connection refused:** Check `docker compose ... ps` and `docker compose ... logs`. Ensure Docker is running and the port in `.env` matches DBeaver.

**Port in use:** Change `POSTGRES_PORT` or `FIREBIRD_PORT` in `.env`, recreate the container, and update DBeaver.

**Firebird cannot find the database:** Use the container path `/var/lib/firebird/data/<filename>.fdb`, not a host-side file path. Verify `FIREBIRD_DATABASE` and startup logs.

**Changed passwords do not work:** Existing database volumes often retain their initialized authentication state. Do not assume updating `.env` changes an existing user's password.

**Changed SQL has no effect:** The Compose files launch the DBMS; they do not apply or migrate project schema automatically.

**Need a clean local database:** Back up anything important, then use `docker compose -f <compose-file> down -v` to remove its Docker volume. This permanently deletes local data.

## 6. Benchmark protocol (to be finalized)

Use fixed dataset profiles, record database versions and host specs, and perform read and write workloads under repeatable conditions. Reset or restore database state between write benchmark cases as appropriate. Do not compare latency measurements from different laptops as if they were controlled results.
