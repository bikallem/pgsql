# bikallem/postgresql

A PostgreSQL database driver for MoonBit implementing the PostgreSQL wire protocol (v3.0).

Native-only. Requires `moonbitlang/async` for async I/O.

## Architecture

```
bikallem/postgresql          ← public API (Client, Config, Value, QueryResult, Row, Transaction)
  └── protocol/              ← internal wire protocol (encoder, decoder, messages, auth)

tests/integration/           ← integration tests (requires running PostgreSQL)
examples/contacts/           ← CLI example app
```

### Dependency Graph

```
examples/contacts ──┐
tests/integration ──┤
                    ▼
            bikallem/postgresql ──► moonbitlang/async/socket
                    │
                    ▼
            bikallem/postgresql/protocol  (internal, no external deps)
```

## Packages

### `bikallem/postgresql`

The public API. All interaction goes through `Client`.

**Types:**

| Type | Description |
|------|-------------|
| `Config` | Connection parameters (host, port, user, password, database) |
| `Client` | Main entry point — connect, query, execute, transact |
| `QueryResult` | Column metadata + rows from a query |
| `Row` | Single result row with typed accessors |
| `Value` | Enum: `Null`, `Bool`, `Int`, `Int64`, `Float`, `String`, `Bytes` |
| `ColumnInfo` | Column name, type OID, type size |
| `TransactionStatus` | `Idle`, `InTransaction`, `Failed` |
| `Transaction` | Handle for executing queries within a transaction |
| `ServerErrorInfo` | Detailed PostgreSQL error (severity, SQLSTATE code, message, etc.) |

**Client methods:**

```
Client::connect(config)             → Client            (async)
Client::close(self)                 → Unit
Client::query(self, sql)            → QueryResult       (async)
Client::execute(self, sql)          → Int               (async, returns affected rows)
Client::query_params(self, sql, params)   → QueryResult (async)
Client::execute_params(self, sql, params) → Int         (async)
Client::transaction(self, fn)       → T                 (async, auto commit/rollback)
Client::begin(self)                 → Unit              (async)
Client::commit(self)                → Unit              (async)
Client::rollback(self)              → Unit              (async)
```

**Row accessors:**

```
Row::get(self, index)          → Value?
Row::get_by_name(self, name)   → Value?
Row::get_string(self, index)   → String?
Row::get_int(self, index)      → Int?
Row::get_int64(self, index)    → Int64?
Row::get_float(self, index)    → Double?
Row::get_bool(self, index)     → Bool?
Row::is_null(self, index)      → Bool
```

### `bikallem/postgresql/protocol`

Internal package. Implements the PostgreSQL v3.0 wire protocol:

- **types.mbt** — Type OID constants, protocol-level `Value` enum, `FieldDescription`
- **messages.mbt** — `FrontendMessage` and `BackendMessage` enums
- **encoder.mbt** — Serializes frontend messages to bytes
- **decoder.mbt** — Parses backend messages from bytes
- **buffer_reader.mbt / buffer_writer.mbt** — Binary buffer utilities
- **auth.mbt** — MD5 and cleartext password authentication

Not imported directly by users. The main package wraps it with public types and a conversion layer (`convert.mbt`).

### `tests/integration`

Integration tests requiring a running PostgreSQL at `127.0.0.1:5432` with `trust` auth.

```sh
pg_ctl start -l .postgres/log
moon test --target native tests/integration/
```

Covers: connect, CRUD, transactions (commit + rollback), parameterized queries with all value types, error handling (invalid SQL, constraint violations).

### `examples/contacts`

CLI contact manager demonstrating the full API.

```sh
moon run examples/contacts --target native -- <command>
```

Commands: `setup`, `list`, `add`, `update`, `delete`, `search`.

## Usage

```moonbit
async fn main {
  let config = @pgsql.Config::new("user", "pass", "dbname", host="127.0.0.1")
  let client = @pgsql.Client::connect(config)

  // Simple query
  let result = client.query("SELECT id, name FROM users")
  for row in result.iter() {
    let id = row.get_int(0).unwrap()
    let name = row.get_string(1).unwrap()
    println("\{id}: \{name}")
  }

  // Parameterized query
  let result = client.query_params(
    "SELECT * FROM users WHERE age > $1",
    [@pgsql.Int(21)],
  )

  // Transaction (auto commit/rollback)
  client.transaction(async fn(tx) {
    let _ = tx.execute_params(
      "INSERT INTO users (name) VALUES ($1)",
      [@pgsql.String("Alice")],
    )
  })

  client.close()
}
```

## Development

Requires [Nix](https://nixos.org/) with flakes enabled.

```sh
direnv allow          # enter nix shell, initializes PostgreSQL on first run
pg_ctl start -l .postgres/log
moon test --target native
pg_ctl stop
```
