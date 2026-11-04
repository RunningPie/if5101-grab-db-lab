# Implementation Environment

## Supported RDBMS
- PostgreSQL 17.11 (Docker image `postgres:17`, 160 MB)

## Containerization
- Docker Engine 29.5.3 (Docker Desktop)
- Docker Compose 5.1.4
- Docker Desktop VM: 10 CPUs, 7.75 GiB memory. The container has no CPU or memory limit of its own.

## Host Specifications
The benchmark and setup results in `results/` were measured on this machine.
- CPU: Apple M5, 10 cores
- RAM: 16 GB
- Storage: 926 GiB
- OS: macOS 26.5.2 (arm64)

## Database Setup
See README.md for startup instructions.

## Database Configuration
PostgreSQL runs with its default configuration:

| Setting | Value |
| --- | --- |
| `shared_buffers` | 128MB |
| `work_mem` | 4MB |
| `maintenance_work_mem` | 64MB |
| `effective_cache_size` | 4GB |
| `max_wal_size` | 1GB |
| `max_connections` | 100 |
