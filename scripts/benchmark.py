"""Benchmark the read and write queries in sql/DML on one dataset profile."""

from __future__ import annotations

import argparse
from collections import defaultdict
import csv
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import re
import statistics
import subprocess
import sys
from typing import NamedTuple

import yaml

from generate_data import CONFIG_FILE, PROFILES
from orchestrator import COMPOSE_FILE, ENV_FILE, ROOT, load_settings

READ_FILE = ROOT / 'sql' / 'DML' / '01_read_queries.sql'
WRITE_FILE = ROOT / 'sql' / 'DML' / '02_write_queries.sql'
RESULTS_DIR = ROOT / 'results'
# Each query starts at a header comment such as "-- R1: Title" and runs until the next header.
HEADER = re.compile(r'^-- ([RW]\d+): *(.*)$', re.MULTILINE)
DOLLAR_TAG = re.compile(r'\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$')
TIMING = re.compile(r'^Time: ([0-9.]+) ms')
TRANSACTION_CONTROL = ('BEGIN', 'START', 'COMMIT', 'END', 'ROLLBACK', 'SAVEPOINT', 'RELEASE')
MAINTENANCE_DB = 'postgres'


class Query(NamedTuple):
    name: str
    title: str
    kind: str
    statements: list[str]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description='Run the queries in sql/DML/01_read_queries.sql and 02_write_queries.sql '
                    'against the database in POSTGRES_DB and record their execution times.'
    )
    parser.add_argument('--profile', required=True, choices=PROFILES,
                        help='dataset profile loaded in POSTGRES_DB')
    parser.add_argument('--runs', type=int, default=5, help='timed runs per query (default: 5)')
    parser.add_argument('--only', choices=('reads', 'writes'), help='run only one workload')
    return parser


def split_statements(sql: str) -> list[str]:
    """Split on top-level semicolons, ignoring those in comments and quoted text."""
    statements: list[str] = []
    start = None
    i = 0
    while i < len(sql):
        if sql.startswith('--', i):
            end = sql.find('\n', i)
            i = len(sql) if end == -1 else end + 1
            continue
        if sql.startswith('/*', i):
            end = sql.find('*/', i + 2)
            i = len(sql) if end == -1 else end + 2
            continue
        char = sql[i]
        if char.isspace():
            i += 1
            continue
        if start is None:
            start = i
        dollar = DOLLAR_TAG.match(sql, i) if char == '$' else None
        if char in '\'"' or dollar:
            closing = dollar.group() if dollar else char
            end = sql.find(closing, i + len(closing))
            i = len(sql) if end == -1 else end + len(closing)
            continue
        if char == ';':
            statements.append(sql[start:i + 1])
            start = None
        i += 1
    if start is not None:
        statements.append(sql[start:].rstrip() + '\n;')
    return statements


def load_queries(path: Path, kind: str) -> list[Query]:
    if not path.is_file():
        raise ValueError(f'Missing query file: {path}')
    text = path.read_text(encoding='utf-8-sig')
    headers = list(HEADER.finditer(text))
    if not headers:
        raise ValueError(f'{path.name} has no query headers such as "-- R1: Title".')
    queries = []
    for header, following in zip(headers, headers[1:] + [None]):
        body = text[header.end():following.start() if following else len(text)]
        statements = split_statements(body)
        if not statements:
            raise ValueError(f'{path.name}: {header[1]} has no SQL statement.')
        queries.append(Query(header[1], header[2].strip(), kind, statements))
    names = [query.name for query in queries]
    duplicates = sorted({name for name in names if names.count(name) > 1})
    if duplicates:
        raise ValueError(f'{path.name} repeats query headers: ' + ', '.join(duplicates))
    return queries


def is_transaction_control(statement: str) -> bool:
    return statement.split(None, 1)[0].rstrip(';').upper() in TRANSACTION_CONTROL


def quote_ident(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


def run_psql(settings: dict[str, str], database: str, script: str) -> str:
    command = [
        'docker', 'compose', '--env-file', str(ENV_FILE), '-f', str(COMPOSE_FILE),
        'exec', '-T', 'postgres', 'psql', '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1',
        '-U', settings['POSTGRES_USER'], '-d', database, '-f', '-',
    ]
    # UTF-8 both ways, so the SQL and plans are not decoded with the Windows code page.
    result = subprocess.run(command, input=script, encoding='utf-8', check=True, env=settings,
                            stdout=subprocess.PIPE)
    return result.stdout


def plan_script(queries: list[Query]) -> list[str]:
    # Warm-up run: EXPLAIN ANALYZE executes each statement, so it also warms the caches.
    lines = ['\\o', '\\timing off']
    for query in queries:
        for statement in query.statements:
            if is_transaction_control(statement):
                lines.append(statement)
            else:
                lines += [f'\\echo @@plan {query.name}', f'EXPLAIN (ANALYZE, BUFFERS) {statement}']
    return lines


def prime_script(queries: list[Query]) -> list[str]:
    # Plain EXPLAIN plans without executing, so a new session's catalog lookups are not timed.
    lines = ['\\o /dev/null']
    for query in queries:
        lines += [f'EXPLAIN {statement}' for statement in query.statements
                  if not is_transaction_control(statement)]
    return lines


def timed_script(queries: list[Query], run: int) -> list[str]:
    # Results are discarded; psql still prints each statement's "Time:" line to stdout.
    lines = ['\\o /dev/null', '\\timing on']
    for query in queries:
        for statement in query.statements:
            lines += [f'\\echo @@run {query.name} {run}', statement]
            if not is_transaction_control(statement):
                lines.append('\\echo @@rows :ROW_COUNT')
    return lines


def parse_output(output: str, queries: list[Query], runs: list[int], results: dict) -> None:
    times: dict[tuple[str, int], list[float]] = defaultdict(list)
    rows: dict[tuple[str, int], int] = defaultdict(int)
    plan = current = None
    for line in output.splitlines():
        if line.startswith('@@plan '):
            plan, current = [], None
            results[line.split()[1]]['plans'].append(plan)
        elif line.startswith('@@run '):
            _, name, run = line.split()
            plan, current = None, (name, int(run))
        elif line.startswith('@@rows ') and current:
            rows[current] += int(line.split()[1])
        elif current and (match := TIMING.match(line)):
            times[current].append(float(match[1]))
        elif plan is not None and line:
            plan.append(line)
    for query in queries:
        for run in runs:
            key = (query.name, run)
            if len(times[key]) != len(query.statements):
                raise ValueError(f'Could not read the timing of {query.name}, run {run}.')
            results[query.name]['times_ms'].append(round(sum(times[key]), 3))
            results[query.name]['rows'].append(rows[key])


def check_database(settings: dict[str, str], profile: str, need_exclusive: bool) -> str:
    database = settings['POSTGRES_DB']
    config = yaml.safe_load(CONFIG_FILE.read_text(encoding='utf-8'))
    expected = config['profiles'][profile]['service_orders']
    output = run_psql(settings, database, (
        'SHOW server_version;\n'
        'SELECT count(*) FROM service_orders;\n'
        "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() "
        "AND backend_type = 'client backend' AND pid <> pg_backend_pid();\n"
    ))
    version, orders, others = output.splitlines()
    if int(orders) != expected:
        raise ValueError(
            f"{database} has {orders} service orders, but the '{profile}' profile has {expected}. "
            'Set POSTGRES_DB to that profile\'s database, or rebuild it (see scripts/README.md).'
        )
    if need_exclusive and int(others) > 0:
        raise ValueError(
            f'{others} other session(s) are connected to {database}, for example DBeaver. '
            'The write benchmark copies the database, which PostgreSQL only allows when no one '
            'else is connected. Disconnect them and run again, or use --only reads.'
        )
    return version


def checkpoint(settings: dict[str, str], database: str) -> None:
    # Write out pending changes now, so a background checkpoint does not run during the timed runs.
    # The runs follow back to back without pausing: an idle pause lets the CPU slow down and skews them.
    run_psql(settings, database, 'CHECKPOINT;\n')


def benchmark_reads(settings: dict[str, str], queries: list[Query], runs: int, results: dict) -> None:
    for query in queries:
        # One session per query: a warm-up run that records the plan, then the timed runs.
        checkpoint(settings, settings['POSTGRES_DB'])
        lines = plan_script([query])
        for run in range(1, runs + 1):
            lines += timed_script([query], run)
        output = run_psql(settings, settings['POSTGRES_DB'], '\n'.join(lines) + '\n')
        parse_output(output, [query], list(range(1, runs + 1)), results)
        print(f"  {query.name}: {statistics.mean(results[query.name]['times_ms']):.3f} ms on average",
              flush=True)


def benchmark_writes(settings: dict[str, str], queries: list[Query], runs: int, results: dict) -> None:
    # Every run, including the warm-up, starts from a fresh copy of the database, so W1-W10
    # always see the seeded data and the original database is never changed.
    source = settings['POSTGRES_DB']
    copy = f'{source}_bench'
    drop = ('SET client_min_messages = warning;\n'
            f'DROP DATABASE IF EXISTS {quote_ident(copy)} WITH (FORCE);\n')
    create = (f'CREATE DATABASE {quote_ident(copy)} TEMPLATE {quote_ident(source)} '
              'STRATEGY FILE_COPY;\n')
    try:
        for run in range(runs + 1):
            run_psql(settings, MAINTENANCE_DB, drop + create)
            checkpoint(settings, copy)
            if run == 0:
                output = run_psql(settings, copy, '\n'.join(plan_script(queries)) + '\n')
                parse_output(output, queries, [], results)
                print('  warm-up run done', flush=True)
                continue
            lines = prime_script(queries) + timed_script(queries, run)
            output = run_psql(settings, copy, '\n'.join(lines) + '\n')
            parse_output(output, queries, [run], results)
            total = sum(results[query.name]['times_ms'][-1] for query in queries)
            print(f'  run {run}/{runs}: {total:.3f} ms for all write queries', flush=True)
    finally:
        try:
            run_psql(settings, MAINTENANCE_DB, drop)
        except subprocess.CalledProcessError:
            print(f'Could not drop {copy}; drop it manually.', file=sys.stderr)


def summarize(query: Query, result: dict) -> dict:
    times = result['times_ms']
    return {
        'query': query.name,
        'title': query.title,
        'type': query.kind,
        'runs': len(times),
        'mean_ms': round(statistics.mean(times), 3),
        'median_ms': round(statistics.median(times), 3),
        'min_ms': min(times),
        'max_ms': max(times),
        'stdev_ms': round(statistics.stdev(times), 3) if len(times) > 1 else 0.0,
        'rows': result['rows'][-1],
        'times_ms': times,
        'rows_per_run': result['rows'],
        'plans': result['plans'],
    }


def save_results(profile: str, metadata: dict, summaries: list[dict]) -> Path:
    RESULTS_DIR.mkdir(exist_ok=True)
    base = RESULTS_DIR / f"{profile}_{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    with base.with_suffix('.csv').open('w', newline='', encoding='utf-8') as file:
        writer = csv.writer(file)
        writer.writerow(('profile', 'query', 'type', 'run', 'time_ms', 'rows'))
        for summary in summaries:
            for run, (time_ms, rows) in enumerate(zip(summary['times_ms'], summary['rows_per_run']),
                                                  start=1):
                writer.writerow((profile, summary['query'], summary['type'], run, time_ms, rows))
    base.with_suffix('.json').write_text(
        json.dumps({**metadata, 'queries': summaries}, indent=2) + '\n', encoding='utf-8'
    )
    return base


def print_summary(summaries: list[dict]) -> None:
    print(f"\n{'Query':<6} {'Mean ms':>11} {'Median ms':>11} {'Min ms':>11} {'Max ms':>11} "
          f"{'Rows':>8}  Title")
    for s in summaries:
        print(f"{s['query']:<6} {s['mean_ms']:>11.3f} {s['median_ms']:>11.3f} {s['min_ms']:>11.3f} "
              f"{s['max_ms']:>11.3f} {s['rows']:>8}  {s['title']}")


def benchmark(settings: dict[str, str], profile: str, runs: int, only: str | None) -> None:
    if runs < 1:
        raise ValueError('--runs must be at least 1.')
    if not COMPOSE_FILE.is_file():
        raise ValueError(f'Missing Compose file: {COMPOSE_FILE}')
    reads = load_queries(READ_FILE, 'read') if only != 'writes' else []
    writes = load_queries(WRITE_FILE, 'write') if only != 'reads' else []
    version = check_database(settings, profile, need_exclusive=bool(writes))
    # Vacuum first, so autovacuum does not start on the freshly seeded tables during the runs.
    run_psql(settings, settings['POSTGRES_DB'], 'VACUUM (ANALYZE);\n')
    started_at = datetime.now(timezone.utc)
    results = {query.name: {'times_ms': [], 'rows': [], 'plans': []} for query in reads + writes}
    print(f"Benchmarking {settings['POSTGRES_DB']} ({profile}) on PostgreSQL {version}: "
          f'{len(reads)} read and {len(writes)} write queries, 1 warm-up and {runs} timed runs each.',
          flush=True)
    if reads:
        print('Read queries:', flush=True)
        benchmark_reads(settings, reads, runs, results)
    if writes:
        print('Write queries, each run on a fresh copy of the database:', flush=True)
        benchmark_writes(settings, writes, runs, results)
    summaries = [summarize(query, results[query.name]) for query in reads + writes]
    metadata = {
        'profile': profile,
        'database': settings['POSTGRES_DB'],
        'postgres_version': version,
        'started_at': started_at.isoformat(timespec='seconds'),
        'finished_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        'warmup_runs': 1,
        'timed_runs': runs,
        'host': {'platform': platform.platform(), 'cpu_count': os.cpu_count()},
    }
    print_summary(summaries)
    base = save_results(profile, metadata, summaries)
    print(f'\nSaved {base.with_suffix(".csv").relative_to(ROOT)} and '
          f'{base.with_suffix(".json").relative_to(ROOT)}.')


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        benchmark(load_settings(), args.profile, args.runs, args.only)
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print(f'Benchmark failed: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
