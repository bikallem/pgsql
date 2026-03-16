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
    /nix/store/*-postgresql-*/bin \
    "/c/Program Files/PostgreSQL"/*/bin \
    "/mnt/c/Program Files/PostgreSQL"/*/bin
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
    local pwfile
    pwfile=$(mktemp)
    echo "$PGPASSWORD" > "$pwfile"
    initdb \
      --pgdata="$PGDATA" \
      --auth=scram-sha-256 \
      --username="$PGUSER" \
      --pwfile="$pwfile" \
      --locale=C \
      || initdb \
        --pgdata="$PGDATA" \
        --auth=scram-sha-256 \
        --username="$PGUSER" \
        --pwfile="$pwfile" \
        --no-locale
    rm -f "$pwfile"

    # Generate self-signed TLS certificate (if openssl available)
    local ssl_enabled=off
    if command -v openssl >/dev/null 2>&1; then
      openssl req -new -x509 -nodes \
        -days 3650 \
        -subj "/CN=localhost" \
        -keyout "$PGDATA/server.key" \
        -out "$PGDATA/server.crt" \
        2>/dev/null
      chmod 600 "$PGDATA/server.key"
      ssl_enabled=on
    else
      echo "Warning: openssl not found, starting without TLS"
    fi

    # Configure postgresql.conf
    cat >> "$PGDATA/postgresql.conf" <<EOF

# Test instance overrides
port = $PGPORT
listen_addresses = '127.0.0.1'
unix_socket_directories = ''
ssl = $ssl_enabled
EOF
    if [ "$ssl_enabled" = "on" ]; then
      cat >> "$PGDATA/postgresql.conf" <<EOF
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
EOF
    fi

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
