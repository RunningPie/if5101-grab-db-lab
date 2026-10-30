"""Initialize the PostgreSQL schema and coordinate future experiment steps."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys

from dotenv import dotenv_values

ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = ROOT / '.env'
COMPOSE_FILE = ROOT / 'docker' / 'compose.postgres.yaml'
SCHEMA_DIR = ROOT / 'sql' / 'DDL'
SCHEMA_FILES = ('01_tables.sql', '02_foreign_keys.sql', '03_indexes.sql',
                '04_integrity_constraints.sql')


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description='Initialize the PostgreSQL schema (the default action).'
    )
    commands = parser.add_subparsers(dest='command')
    commands.add_parser('init', help='initialize the schema in an empty database')
    for name in ('seed', 'benchmark', 'run'):
        # TO DO: Implement these commands in the future. For now, they are placeholders to avoid confusion.
        command = commands.add_parser(name, help='planned experiment step; not yet implemented')
        command.add_argument('--profile', required=True, choices=('small', 'medium', 'large'))
    return parser


def load_settings() -> dict[str, str]:
    if not ENV_FILE.is_file():
        raise ValueError('Missing .env. Copy .env.example to .env and configure PostgreSQL.')
    values = {key: value for key, value in dotenv_values(ENV_FILE).items() if value is not None}
    values.update(os.environ)
    for key in ('POSTGRES_USER', 'POSTGRES_PASSWORD'):
        if not values.get(key):
            raise ValueError(f'{key} must be set in .env or the environment.')
    values.setdefault('POSTGRES_DB', 'grab_lab')
    if not values['POSTGRES_DB']:
        raise ValueError('POSTGRES_DB must not be empty.')
    return values


def initialize_schema(settings: dict[str, str]) -> None:
    paths = [SCHEMA_DIR / name for name in SCHEMA_FILES]
    missing = [str(path) for path in paths if not path.is_file()]
    if missing:
        raise ValueError('Missing schema files: ' + ', '.join(missing))
    if not COMPOSE_FILE.is_file():
        raise ValueError(f'Missing Compose file: {COMPOSE_FILE}')
    sql = '\n'.join(path.read_text(encoding='utf-8-sig') for path in paths)
    command = [
        'docker', 'compose', '--env-file', str(ENV_FILE), '-f', str(COMPOSE_FILE),
        'exec', '-T', 'postgres', 'psql', '-X', '-v', 'ON_ERROR_STOP=1',
        '-U', settings['POSTGRES_USER'], '-d', settings['POSTGRES_DB'],
    ]
    # Separate connection check avoids starting the initialization on a bad connection.
    subprocess.run(command + ['-c', 'SELECT 1'], check=True, env=settings,
                   stdout=subprocess.DEVNULL)
    print('Connected to PostgreSQL. Applying schema in one transaction...', flush=True)
    subprocess.run(command + ['--single-transaction', '-f', '-'], input=sql,
                   text=True, check=True, env=settings)
    print('Schema initialized successfully.')


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command in ('seed', 'benchmark', 'run'):
        print(f"The '{args.command}' command is not implemented yet; no changes were made.", file=sys.stderr)
        return 1
    try:
        initialize_schema(load_settings())
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print(f'Initialization failed: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
