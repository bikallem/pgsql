#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PGDATA="$SCRIPT_DIR/.postgres"
PGPORT=5433
PGUSER=postgres
PGPASSWORD=postgres

# Add PostgreSQL binaries to PATH when needed.
# Supports distro paths and Nix-style store layouts.
ensure_pg_tools() {
  if command -v initdb >/dev/null 2>&1 && command -v pg_ctl >/dev/null 2>&1; then
    return 0
  fi

  local dir
  for dir in \
    /usr/lib/postgresql/*/bin \
    /usr/local/opt/postgresql/bin \
    /usr/local/opt/postgresql@*/bin \
    /opt/homebrew/opt/postgresql/bin \
    /opt/homebrew/opt/postgresql@*/bin \
    /nix/store/*-postgresql-*/bin
  do
    if [ -x "$dir/initdb" ] && [ -x "$dir/pg_ctl" ]; then
      export PATH="$dir:$PATH"
      break
    fi
  done

  if ! command -v initdb >/dev/null 2>&1 || ! command -v pg_ctl >/dev/null 2>&1; then
    echo "PostgreSQL tools not found (need initdb and pg_ctl in PATH)." >&2
    return 127
  fi
}

ensure_pg_tools

start() {
  if [ -f "$PGDATA/postmaster.pid" ]; then
    echo "Test PostgreSQL already running (port $PGPORT)"
    return 0
  fi

  if [ ! -d "$PGDATA" ]; then
    echo "Initializing test PostgreSQL in $PGDATA ..."
    initdb \
      --pgdata="$PGDATA" \
      --auth=scram-sha-256 \
      --username="$PGUSER" \
      --pwfile=<(echo "$PGPASSWORD") \
      --locale=C \
      > /dev/null

    # Generate self-signed TLS certificate
    openssl req -new -x509 -nodes \
      -days 3650 \
      -subj "/CN=localhost" \
      -keyout "$PGDATA/server.key" \
      -out "$PGDATA/server.crt" \
      2>/dev/null
    chmod 600 "$PGDATA/server.key"

    # Configure postgresql.conf
    cat >> "$PGDATA/postgresql.conf" <<EOF

# Test instance overrides
port = $PGPORT
listen_addresses = '127.0.0.1'
unix_socket_directories = ''
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
EOF

    # Configure pg_hba.conf — SCRAM-SHA-256 for both TLS and plain
    cat > "$PGDATA/pg_hba.conf" <<EOF
# TYPE  DATABASE  USER  ADDRESS        METHOD
local   all       all                  scram-sha-256
hostssl all       all   127.0.0.1/32   scram-sha-256
host    all       all   127.0.0.1/32   scram-sha-256
EOF
  fi

  echo "Starting test PostgreSQL on port $PGPORT ..."
  pg_ctl start -D "$PGDATA" -l "$PGDATA/server.log" -o "-p $PGPORT" -w
  echo "Test PostgreSQL running on port $PGPORT"
}

stop() {
  if [ -f "$PGDATA/postmaster.pid" ]; then
    echo "Stopping test PostgreSQL ..."
    pg_ctl stop -D "$PGDATA" -m fast -w
  else
    echo "Test PostgreSQL is not running"
  fi
}

clean() {
  stop
  if [ -d "$PGDATA" ]; then
    echo "Removing $PGDATA ..."
    rm -rf "$PGDATA"
    echo "Cleaned"
  fi
}

case "${1:-}" in
  start) start ;;
  stop)  stop ;;
  clean) clean ;;
  *)
    echo "Usage: $0 {start|stop|clean}"
    exit 1
    ;;
esac
