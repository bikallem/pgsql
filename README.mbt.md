# bikallem/postgresql

A PostgreSQL database driver for MoonBit implementing the PostgreSQL wire protocol (v3.0).

Native-only. Requires `moonbitlang/async` for async I/O.

- [Install](#install)
- [Usage](#usage)
  - [Value Types](#value-types)
  - [Prepared Statements](#prepared-statements)
  - [Transactions](#transactions)
  - [Connection Pooling](#connection-pooling)
  - [Row Streaming](#row-streaming)
  - [COPY Protocol](#copy-protocol)
  - [LISTEN/NOTIFY](#listennotify)
  - [Error Handling](#error-handling)
  - [Timeouts and Cancellation](#timeouts-and-cancellation)
- [Development](#development)

## Install

```sh
moon add bikallem/postgresql
```

## Usage

```mbt check
///|
async test "simple and parameterized queries" {
  let config = Config::new("user", "pass", "dbname", host="127.0.0.1")
  let client = Client::connect(config)

  // Simple query
  let result = client.query("SELECT id, name FROM users")
  for row in result.iter() {
    let id = row.int(0).unwrap()
    let name = row.string(1).unwrap()
    println("\{id}: \{name}")
  }

  // Parameterized query
  let result = client.query_params("SELECT * FROM users WHERE age > $1", [
    Int(21),
  ])
  let _ = result

  client.close()
}
```

`Config::new` now defaults to `ssl_mode=Require` (encrypted transport).
For local environments without TLS, pass `ssl_mode=Disable` explicitly.

### Value Types

Parameters and results use the `Value` enum:

| Variant | MoonBit Type | PostgreSQL Types |
|---------|-------------|-----------------|
| `Null` | — | NULL |
| `Bool(Bool)` | `Bool` | BOOLEAN |
| `Int(Int)` | `Int` | SMALLINT, INTEGER |
| `Int64(Int64)` | `Int64` | BIGINT |
| `Float(Double)` | `Double` | REAL, DOUBLE PRECISION, NUMERIC |
| `String(String)` | `String` | TEXT, VARCHAR, CHAR |
| `Bytes(Bytes)` | `Bytes` | BYTEA |
| `Date(String)` | `String` | DATE |
| `Time(String)` | `String` | TIME, TIMETZ |
| `Timestamp(String)` | `String` | TIMESTAMP |
| `TimestampTz(String)` | `String` | TIMESTAMPTZ |
| `Interval(String)` | `String` | INTERVAL |
| `Json(String)` | `String` | JSON, JSONB |
| `Uuid(String)` | `String` | UUID |

Row accessors: `int(i)`, `int64(i)`, `float(i)`, `bool(i)`,
`string(i)`, `date(i)`, `time(i)`, `timestamp(i)`, `json(i)`,
`uuid(i)`, `by_name(name)`, `is_null(i)`.

Note: `COUNT(*)` returns BIGINT, so use `int64()` not `int()`.

### Prepared Statements

Prepare once, execute many times with different parameters:

```mbt check
///|
async test "prepared statements" {
  let config = Config::new("user", "pass", "dbname", host="127.0.0.1")
  let client = Client::connect(config)

  let stmt = client.prepare("INSERT INTO users (name) VALUES ($1)")
  let _ = stmt.execute([String("Alice")])
  let _ = stmt.execute([String("Bob")])
  stmt.close()

  client.close()
}
```

### Transactions

```mbt check
///|
async test "transactions" {
  let config = Config::new("user", "pass", "dbname", host="127.0.0.1")
  let client = Client::connect(config)

  // Auto commit on success, rollback on error
  client.transaction(async fn(tx) {
    let _ = tx.execute_params("INSERT INTO users (name) VALUES ($1)", [
      String("Carol"),
    ])
  })

  client.close()
}
```

### Connection Pooling

Manage a pool of reusable connections with concurrency limiting:

```mbt check
///|
async test "connection pool" {
  let config = Config::new("user", "pass", "dbname", host="127.0.0.1")
  let pool = Pool::new(config, max_size=5, acquire_timeout_ms=10000)

  // Auto-release with `with_connection`
  let count : Int64 = pool.with_connection(async fn(client) {
    let result = client.query("SELECT count(*) FROM users")
    result.row(0).unwrap().int64(0).unwrap()
  })
  let _ = count

  pool.close()
}
```

### Row Streaming

Stream large result sets without loading everything into memory:

```mbt check
///|
async test "row streaming" {
  let config = Config::new("user", "pass", "dbname", host="127.0.0.1")
  let client = Client::connect(config)

  let stream = client.query_stream("SELECT * FROM large_table", batch_size=200)

  // Iterate row-by-row, fetching in batches from the server
  stream.for_each(fn(row) { let _ = row.string(0) })
  // stream is auto-closed after for_each

  client.close()
}
```

Streaming wraps the query in a transaction automatically if needed (portals require one). Use `stream.next()` for manual iteration, and `stream.close()` when done early.
Do not call database operations on the same `Client` from inside stream callbacks; this is rejected with `ClientUsageError` to avoid re-entrant deadlocks.

### COPY Protocol

Bulk data import/export using PostgreSQL's COPY protocol:

```mbt check
///|
async test "copy" {
  let config = Config::new("user", "pass", "dbname", host="127.0.0.1")
  let client = Client::connect(config)

  // COPY IN — bulk insert
  let rows_imported = client.copy_in("COPY users (name, age) FROM STDIN", async fn(
    writer,
  ) {
    writer.write_row(["Alice", "30"])
    writer.write_row(["Bob", "25"])
  })
  let _ = rows_imported

  // COPY OUT — bulk export
  let rows_exported = client.copy_out("COPY users TO STDOUT", fn(data) {
    let _ = data // raw tab-separated bytes
  })
  let _ = rows_exported

  client.close()
}
```

Do not call database operations on the same `Client` from inside COPY callbacks. Re-entrant use is rejected (surfaced as `CopyError`) to avoid self-deadlock.

### LISTEN/NOTIFY

Receive asynchronous notifications from PostgreSQL channels:

```mbt check
///|
async test "listen/notify" {
  let config = Config::new("user", "pass", "dbname", host="127.0.0.1")
  let listener = Client::connect(config)
  let notifier = Client::connect(config)

  listener.listen("events")

  let _ = notifier.execute("NOTIFY events, 'hello'")

  let notification = listener.wait_for_notification()
  let _ = notification.channel() // "events"
  let _ = notification.payload() // "hello"

  listener.unlisten("events")

  listener.close()
  notifier.close()
}
```

Use `poll_notifications()` to check for queued notifications without blocking.
`wait_for_notification()` treats backend `ErrorResponse` as fatal and raises `ServerError` immediately.

### Error Handling

Server errors carry structured information for programmatic handling:

```mbt check
///|
async test "error handling" {
  let config = Config::new("user", "pass", "dbname", host="127.0.0.1")
  let client = Client::connect(config)

  let result = client.query("SELECT 1") catch {
    @pgsql.ServerError(info) => {
      ignore((info.code : String)) // SQLSTATE, e.g. "42P01"
      ignore((info.message : String)) // human-readable message
      ignore((info.severity : String)) // ERROR, FATAL, PANIC
      ignore((info.detail : String?)) // optional detail
      ignore((info.hint : String?)) // optional hint
      return
    }
    _ => return
  }
  let _ = result

  client.close()
}
```

### Timeouts and Cancellation

Use `read_timeout` to bound socket reads, and `Client::cancel()` to send a
PostgreSQL cancel request for the currently running operation.

```mbt nocheck
let config = Config::new(
  "user",
  "pass",
  "dbname",
  host="127.0.0.1",
  read_timeout=5000, // 5s read timeout
)
let client = Client::connect(config)

// from another task/coroutine while a long query is running:
client.cancel()
```

## Development

Requires [Nix](https://nixos.org/) with flakes enabled.

```sh
direnv allow          # enter nix shell, initializes PostgreSQL on first run
pg_ctl start -l .postgres/log
moon test --target native
pg_ctl stop
```
