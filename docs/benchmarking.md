# Benchmarking Methodology

## Objectives
Evaluate database performance under different data volumes.

## Dataset Profiles
- Small
- Medium
- Large

## Workload
- 10 read queries
- 10 write queries

## Metrics
- Execution time (ms)
- Query execution plan
- Rows affected

## Procedure
1. Initialize database.
2. Populate synthetic data.
3. Execute warm-up runs.
4. Execute each query 5 times.
5. Record results.
6. Restore database state when necessary.
7. Repeat for other dataset profiles.