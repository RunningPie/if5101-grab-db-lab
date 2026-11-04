"""Measure what setting up one profile costs: schema and seeding time, storage, and container resources.

The profile is loaded into a temporary database, which is dropped at the end, so the profile's own
database and the benchmark results stay untouched.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time

try:
    import resource
except ImportError:  # Windows has no resource module, so the generator's peak memory is not recorded.
    resource = None

from benchmark import MAINTENANCE_DB, RESULTS_DIR, quote_ident, run_psql
from generate_data import PROFILES, TABLES, write_seed_script
from orchestrator import COMPOSE_FILE, ENV_FILE, ROOT, SCHEMA_DIR, SCHEMA_FILES, load_settings

IDLE_SECONDS = 3
SAMPLE_INTERVAL = 0.25
COPY_ROWS = re.compile(r'^COPY (\d+)$', re.MULTILINE)
POSTGRES_SETTINGS = ('shared_buffers', 'work_mem', 'maintenance_work_mem', 'effective_cache_size',
                     'max_wal_size', 'max_connections')
CGROUP_FILES = ('/sys/fs/cgroup/memory.current', '/sys/fs/cgroup/memory.stat', '/sys/fs/cgroup/cpu.stat')
IN_PUBLIC = "JOIN pg_namespace n ON n.oid = {}namespace WHERE n.nspname = 'public'"
SCHEMA_OBJECTS = {
    'tables': f"SELECT count(*) FROM pg_class c {IN_PUBLIC.format('c.rel')} AND c.relkind = 'r'",
    'enum_types': f"SELECT count(*) FROM pg_type t {IN_PUBLIC.format('t.typ')} AND t.typtype = 'e'",
    'domains': f"SELECT count(*) FROM pg_type t {IN_PUBLIC.format('t.typ')} AND t.typtype = 'd'",
    'primary_keys': f"SELECT count(*) FROM pg_constraint c {IN_PUBLIC.format('c.con')} AND c.contype = 'p'",
    'foreign_keys': f"SELECT count(*) FROM pg_constraint c {IN_PUBLIC.format('c.con')} AND c.contype = 'f'",
    'unique_constraints': f"SELECT count(*) FROM pg_constraint c {IN_PUBLIC.format('c.con')} AND c.contype = 'u'",
    'check_constraints': f"SELECT count(*) FROM pg_constraint c {IN_PUBLIC.format('c.con')} AND c.contype = 'c'",
    'indexes': "SELECT count(*) FROM pg_indexes WHERE schemaname = 'public'",
    'functions': f"SELECT count(*) FROM pg_proc p {IN_PUBLIC.format('p.pro')}",
    'triggers': ("SELECT count(*) FROM pg_trigger tg JOIN pg_class c ON c.oid = tg.tgrelid "
                 f"{IN_PUBLIC.format('c.rel')} AND NOT tg.tgisinternal"),
}
TABLE_SIZES = (
    'SELECT c.relname, pg_table_size(c.oid), pg_indexes_size(c.oid), '
    '(SELECT count(*) FROM pg_index i WHERE i.indrelid = c.oid) '
    f"FROM pg_class c {IN_PUBLIC.format('c.rel')} AND c.relkind = 'r' "
    'ORDER BY pg_total_relation_size(c.oid) DESC;\n'
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description='Create the schema and seed one profile into a temporary database, measuring the time, '
                    'storage and container resources it takes. The temporary database is dropped afterwards.'
    )
    parser.add_argument('--profile', required=True, choices=PROFILES)
    return parser


def compose(*args: str) -> list[str]:
    return ['docker', 'compose', '--env-file', str(ENV_FILE), '-f', str(COMPOSE_FILE), *args]


def psql(settings: dict[str, str], database: str) -> list[str]:
    # The same psql command that orchestrator.py uses for init and seed.
    return compose('exec', '-T', 'postgres', 'psql', '-X', '-v', 'ON_ERROR_STOP=1',
                   '-U', settings['POSTGRES_USER'], '-d', database)


def output_of(command: list[str], settings: dict[str, str] | None = None) -> str:
    return subprocess.run(command, capture_output=True, encoding='utf-8', check=True, env=settings).stdout.strip()


class ContainerSampler(threading.Thread):
    """Reads the container's cgroup memory and CPU counters every SAMPLE_INTERVAL seconds until stopped."""

    def __init__(self, container: str):
        super().__init__(daemon=True)
        self.command = ['docker', 'exec', container, 'cat', *CGROUP_FILES]
        self.samples: list[dict] = []
        self.error: Exception | None = None
        self.stopped = threading.Event()

    def run(self) -> None:
        try:
            while not self.stopped.is_set():
                before = time.perf_counter()
                lines = output_of(self.command).splitlines()
                after = time.perf_counter()
                stats = {key: int(value) for key, value in (line.split() for line in lines[1:])}
                current = int(lines[0])
                self.samples.append({
                    'time': (before + after) / 2,
                    # Same as MEM USAGE in docker stats: the page cache that is not in active use is left out.
                    'memory': current - stats['inactive_file'] if stats['inactive_file'] < current else current,
                    'anon': stats['anon'],
                    'cpu_usec': stats['usage_usec'],
                })
                self.stopped.wait(SAMPLE_INTERVAL)
        except (OSError, subprocess.CalledProcessError, KeyError, ValueError) as exc:
            self.error = exc

    def stop(self) -> list[dict]:
        self.stopped.set()
        self.join()
        if self.error:
            raise ValueError(f'Could not read the container cgroup v2 counters: {self.error}')
        return self.samples


def summarize_phases(samples: list[dict], phases: list[tuple[str, float, float]]) -> dict:
    summary = {}
    for name, start, end in phases:
        inside = [sample for sample in samples if start <= sample['time'] < end]
        # CPU between two samples inside the phase; 100% is one full core.
        pairs = [(a, b) for a, b in zip(samples, samples[1:]) if start <= a['time'] and b['time'] < end]
        cpu = [(b['cpu_usec'] - a['cpu_usec']) / ((b['time'] - a['time']) * 1e4) for a, b in pairs]
        used = sum(b['cpu_usec'] - a['cpu_usec'] for a, b in pairs)
        wall = sum(b['time'] - a['time'] for a, b in pairs)
        summary[name] = {
            'samples': len(inside),
            'memory_max_bytes': max((sample['memory'] for sample in inside), default=None),
            'anon_max_bytes': max((sample['anon'] for sample in inside), default=None),
            'cpu_mean_percent': round(used / (wall * 1e4), 1) if wall else None,
            'cpu_max_percent': round(max(cpu), 1) if cpu else None,
        }
    return summary


def host_info() -> dict:
    cpu, memory = platform.processor() or None, None
    if sys.platform == 'darwin':
        cpu = output_of(['sysctl', '-n', 'machdep.cpu.brand_string'])
        memory = int(output_of(['sysctl', '-n', 'hw.memsize']))
    elif hasattr(os, 'sysconf'):
        memory = os.sysconf('SC_PAGE_SIZE') * os.sysconf('SC_PHYS_PAGES')
    return {'platform': platform.platform(), 'cpu': cpu, 'cpu_count': os.cpu_count(),
            'memory_bytes': memory, 'disk_bytes': shutil.disk_usage(ROOT).total}


def docker_info(container: str) -> dict:
    info = json.loads(output_of(['docker', 'info', '--format', '{{json .}}']))
    image, image_id = output_of(['docker', 'inspect', '--format', '{{.Config.Image}} {{.Image}}', container]).split()
    return {
        'version': info['ServerVersion'], 'os': info['OperatingSystem'], 'kernel': info['KernelVersion'],
        'cpus': info['NCPU'], 'memory_bytes': info['MemTotal'], 'image': image,
        'image_bytes': int(output_of(['docker', 'image', 'inspect', '--format', '{{.Size}}', image_id])),
    }


def measure(settings: dict[str, str], profile: str) -> dict:
    if not COMPOSE_FILE.is_file():
        raise ValueError(f'Missing Compose file: {COMPOSE_FILE}')
    container = output_of(compose('ps', '-q', 'postgres'), settings)
    if not container:
        raise ValueError('The postgres container is not running. Start it first (see README.md).')
    database = f'grab_lab_{profile}_setup'
    drop = ('SET client_min_messages = warning;\n'
            f'DROP DATABASE IF EXISTS {quote_ident(database)} WITH (FORCE);\n')
    version = run_psql(settings, MAINTENANCE_DB, 'SHOW server_version;\n').strip()
    names = ', '.join(f"'{name}'" for name in POSTGRES_SETTINGS)
    postgres_settings = dict(line.split('|') for line in run_psql(
        settings, MAINTENANCE_DB,
        f'SELECT name, current_setting(name) FROM pg_settings WHERE name IN ({names}) ORDER BY name;\n',
    ).splitlines())
    ddl = '\n'.join((SCHEMA_DIR / name).read_text(encoding='utf-8-sig') for name in SCHEMA_FILES)

    print(f"Measuring the setup of the '{profile}' profile in a temporary database, {database}...", flush=True)
    sampler = ContainerSampler(container)
    phases: list[tuple[str, float, float]] = []
    sampler.start()
    try:
        start = time.perf_counter()
        time.sleep(IDLE_SECONDS)
        phases.append(('idle', start, time.perf_counter()))
        run_psql(settings, MAINTENANCE_DB, drop + f'CREATE DATABASE {quote_ident(database)};\n')

        start = time.perf_counter()
        subprocess.run(psql(settings, database) + ['--single-transaction', '-f', '-'], input=ddl,
                       encoding='utf-8', check=True, env=settings, stdout=subprocess.DEVNULL)
        phases.append(('schema', start, time.perf_counter()))
        print(f'  schema: {phases[-1][2] - start:.2f} s', flush=True)

        with tempfile.TemporaryFile() as script:
            start = time.perf_counter()
            write_seed_script(profile, script)
            phases.append(('generate', start, time.perf_counter()))
            print(f'  generate: {phases[-1][2] - start:.2f} s', flush=True)
            script_bytes = script.tell()
            script.seek(0)
            wal_start = run_psql(settings, MAINTENANCE_DB, 'SELECT pg_current_wal_lsn();\n').strip()
            start = time.perf_counter()
            load = subprocess.run(psql(settings, database) + ['--single-transaction', '-f', '-'],
                                  stdin=script, stdout=subprocess.PIPE, check=True, env=settings)
            phases.append(('load', start, time.perf_counter()))
            print(f'  load: {phases[-1][2] - start:.2f} s', flush=True)
        samples = sampler.stop()

        # On macOS ru_maxrss is in bytes, on Linux in kilobytes.
        generator_rss = (resource.getrusage(resource.RUSAGE_SELF).ru_maxrss * (1 if sys.platform == 'darwin' else 1024)
                         if resource else None)
        counts = [int(count) for count in COPY_ROWS.findall(load.stdout.decode('utf-8'))]
        if len(counts) != len(TABLES):
            raise ValueError(f'Expected {len(TABLES)} COPY results from the load, got {len(counts)}.')
        wal_bytes = int(run_psql(settings, MAINTENANCE_DB,
                                 f"SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), '{wal_start}');\n"))
        objects = run_psql(settings, database, 'SELECT ' + ', '.join(f'({sql})' for sql in SCHEMA_OBJECTS.values())
                           + ';\n').strip().split('|')
        database_bytes = int(run_psql(settings, database, 'SELECT pg_database_size(current_database());\n'))
        tables = []
        for line in run_psql(settings, database, TABLE_SIZES).splitlines():
            table, table_bytes, index_bytes, indexes = line.split('|')
            tables.append({'table': table, 'rows': dict(zip(TABLES, counts))[table], 'table_bytes': int(table_bytes),
                           'index_bytes': int(index_bytes), 'indexes': int(indexes)})
    finally:
        sampler.stopped.set()
        run_psql(settings, MAINTENANCE_DB, drop)

    seconds = {name: round(end - start, 3) for name, start, end in phases}
    return {
        'profile': profile,
        'database': database,
        'measured_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        'postgres_version': version,
        'postgres_settings': postgres_settings,
        'host': host_info(),
        'docker': docker_info(container),
        'schema': {'seconds': seconds['schema'],
                   'objects': {name: int(count) for name, count in zip(SCHEMA_OBJECTS, objects)}},
        'seed': {'generate_seconds': seconds['generate'], 'load_seconds': seconds['load'],
                 'script_bytes': script_bytes, 'generator_peak_rss_bytes': generator_rss,
                 'wal_bytes': wal_bytes, 'rows': sum(counts)},
        'storage': {'database_bytes': database_bytes, 'tables': tables},
        'container': summarize_phases(samples, phases),
    }


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        result = measure(load_settings(), args.profile)
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print(f'Measurement failed: {exc}', file=sys.stderr)
        return 1
    RESULTS_DIR.mkdir(exist_ok=True)
    path = RESULTS_DIR / f"setup_{args.profile}_{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
    path.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(f"  {result['seed']['rows']:,} rows, {result['storage']['database_bytes'] / 2**20:.1f} MiB database")
    print(f'Saved {path.relative_to(ROOT)}.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
