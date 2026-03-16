# bikallem/pgsql

A PostgreSQL database driver for MoonBit implementing the PostgreSQL wire protocol (v3.0).

Native-only. Requires `moonbitlang/async` for async I/O.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [API Reference](#api-reference)
  - [Connection](#connection)
  - [Queries](#queries)
  - [Parameterized Queries](#parameterized-queries)
  - [Transactions](#transactions)
  - [Prepared Statements](#prepared-statements)
  - [Row Streaming](#row-streaming)
  - [COPY Protocol](#copy-protocol)
  - [LISTEN/NOTIFY](#listennotify)
  - [Connection Pool](#connection-pool)
  - [Error Handling](#error-handling)
- [Value Types](#value-types)
- [SSL/TLS](#ssltls)
- [Development](#development)

## Features

- PostgreSQL wire protocol v3.0
- SCRAM-SHA-256, MD5, and cleartext authentication
- SSL/TLS with configurable modes (Disable, Prefer, Require, VerifyFull)
- Simple and extended query protocol
- Parameterized queries with type-safe `Value` enum
- Transaction support with automatic commit/rollback
- Prepared statements with parameter type introspection
- Row streaming for memory-efficient large result sets
- COPY IN/OUT for bulk data transfer
- LISTEN/NOTIFY for async notifications
- Connection pooling with configurable size and timeouts
- OS-level CSPRNG for SCRAM nonce generation (getrandom/SecRandomCopyBytes/BCryptGenRandom)

## Installation

Add to your `moon.mod.json`:

```json
{
  "deps": {
    "bikallem/pgsql": "0.1.0"
  }
}
```

Then in your `moon.pkg`:

```
import {
  "bikallem/pgsql" @pgsql,
  "moonbitlang/async",
}
```

## Quick Start

```moonbit
async fn main() -> Unit {
  let client = @pgsql.connect(
    @pgsql.config("postgres", "password", "mydb", host="127.0.0.1", port=5432),
  )

  // Simple query
  let result = client.query("SELECT id, name FROM users")
  for row in result.iter() {
    let id = row.int(0).unwrap()
    let name = row.string(1).unwrap()
    println("\{id}: \{name}")
  }

  client.close()
}
```

## API Reference

### Connection

```moonbit
// Configure and connect
let client = @pgsql.connect(
  @pgsql.config(
    "user", "password", "database",
    host="localhost",       // default: "localhost"
    port=5432,              // default: 5432
    ssl_mode=Require,       // default: Require
    read_timeout=30000,     // milliseconds, 0 = no timeout
  ),
)

// Server info
let version = client.server_param("server_version") // Some("16.2")

// Close
client.close()
```

### Queries

```moonbit
// Simple query — returns QueryResult
let result = client.query("SELECT id, name, email FROM users")

// Access metadata
result.row_count()    // number of rows
result.column_count() // number of columns
result.command_tag()  // e.g. "SELECT 3"
result.fields()       // Array[ColumnInfo]

// Access rows by index
let row = result.row(0).unwrap()

// Typed column access by position
row.int(0)        // Int?
row.int64(1)      // Int64?
row.string(2)     // String?
row.float(3)      // Double?
row.bool(4)       // Bool?
row.date(5)       // String?
row.time(6)       // String?
row.timestamp(7)  // String?
row.json(8)       // String?
row.uuid(9)       // String?

// Access by column name
row.by_name("email") // Value?

// Check for NULL
row.is_null(0)    // Bool

// Iterate rows
for row in result.iter() {
  // ...
}

// Execute without rows (INSERT, UPDATE, DELETE)
let affected = client.execute("DELETE FROM users WHERE id = 1") // Int
```

### Parameterized Queries

```moonbit
let result = client.query_params(
  "SELECT * FROM users WHERE age > $1 AND name = $2",
  [@pgsql.Int(18), @pgsql.String("Alice")],
)

let affected = client.execute_params(
  "INSERT INTO users (name, age) VALUES ($1, $2)",
  [@pgsql.String("Bob"), @pgsql.Int(25)],
)
```

### Transactions

```moonbit
// Automatic commit on success, rollback on error
let result = client.transaction(async fn(tx) {
  tx.execute_params("INSERT INTO accounts (id, balance) VALUES ($1, $2)", [
    @pgsql.Int(1), @pgsql.Float(100.0),
  ])
  tx.execute_params("UPDATE accounts SET balance = balance - $1 WHERE id = $2", [
    @pgsql.Float(50.0), @pgsql.Int(1),
  ])
  tx.query("SELECT balance FROM accounts WHERE id = 1")
})

// Savepoints
client.transaction(async fn(tx) {
  tx.savepoint("sp1")
  // ... risky operations ...
  tx.rollback_to("sp1")  // undo
  tx.release("sp1")      // release savepoint
})
```

### Prepared Statements

```moonbit
let stmt = client.prepare("SELECT * FROM users WHERE age > $1")

// Inspect parameter types
stmt.param_types()  // Array[UInt] — PostgreSQL type OIDs
stmt.name()         // server-side statement name
stmt.sql()          // original SQL

// Execute multiple times with different params
let young = stmt.query([@pgsql.Int(18)])
let old = stmt.query([@pgsql.Int(65)])

// Must close when done
stmt.close()
```

### Row Streaming

For large result sets that shouldn't be loaded entirely into memory:

```moonbit
let stream = client.query_stream(
  "SELECT * FROM large_table",
  batch_size=100,  // rows fetched per batch
)

// Iterate one row at a time
stream.for_each(async fn(row) {
  let id = row.int(0).unwrap()
  // process row...
})

// Or manually with next()
let stream = client.query_stream("SELECT * FROM events")
while true {
  match stream.next() {
    Some(row) => process(row)
    None => break
  }
}
// stream auto-closes when exhausted, or call stream.close() early
```

### COPY Protocol

Bulk data transfer:

```moonbit
// COPY OUT — export rows
let rows_exported = client.copy_out(
  "COPY users TO STDOUT",
  async fn(data : Bytes) {
    // called for each chunk of tab-separated data
  },
)

// COPY IN — import rows
let rows_imported = client.copy_in(
  "COPY users FROM STDIN",
  async fn(writer) {
    writer.write_row(["1", "Alice", "alice@example.com"])
    writer.write_row(["2", "Bob", "bob@example.com"])
    // NULL values
    writer.write_row_nullable([Some("3"), None, Some("carol@example.com")])
  },
)
```

### LISTEN/NOTIFY

Asynchronous notifications:

```moonbit
// Subscribe
client.listen("events")

// Wait for notification (blocks)
let notification = client.wait_for_notification()
notification.channel()    // "events"
notification.payload()    // message payload
notification.process_id() // sender's backend PID

// Or poll without blocking
let notifications = client.poll_notifications()

// Server notices (warnings, informational messages)
let notices = client.poll_notices()

// Unsubscribe
client.unlisten("events")
```

### Connection Pool

```moonbit
let config = @pgsql.config("user", "password", "database")
let pool = @pgsql.Pool::new(
  config,
  max_size=10,             // default: 10
  acquire_timeout_ms=30000, // default: 30000
)

// Manual acquire/release
let client = pool.acquire()
let result = client.query("SELECT 1")
pool.release(client)

// Automatic release with callback
let value = pool.with_connection(async fn(client) {
  let result = client.query("SELECT 42 AS val")
  result.row(0).unwrap().int(0).unwrap()
})

pool.close()
```

### Error Handling

All errors are specific suberror types:

```moonbit
try {
  let result = client.query("SELECT * FROM nonexistent")
} catch {
  @pgsql.ServerError(info) => {
    // PostgreSQL server error
    info.severity    // "ERROR", "FATAL", "PANIC"
    info.code        // SQLSTATE code, e.g. "42P01"
    info.message     // human-readable message
    info.detail      // optional detail
    info.hint        // optional hint
    info.table       // optional table name
    info.column      // optional column name
    info.constraint  // optional constraint name
  }
  @pgsql.AuthError(msg) => // authentication failure
  @pgsql.ConnectionClosedError => // connection closed
  @pgsql.ClientUsageError(msg) => // misuse (e.g. re-entrant callback)
  @pgsql.TxError(msg) => // transaction error
  @pgsql.PreparedStmtError(msg) => // prepared statement error
  @pgsql.CopyError(msg) => // COPY operation error
  @pgsql.PoolError(msg) => // pool error
  @pgsql.StreamError(msg) => // streaming error
  @pgsql.ProtocolError(msg) => // protocol violation
}
```

## Value Types

The `Value` enum maps PostgreSQL types to MoonBit:

| PostgreSQL Type | Value Variant | Accessor |
|----------------|---------------|----------|
| `NULL` | `Null` | `is_null()` |
| `boolean` | `Bool(Bool)` | `as_bool()` |
| `int2`, `int4` | `Int(Int)` | `as_int()` |
| `int8` | `Int64(Int64)` | `as_int64()` |
| `float4`, `float8`, `numeric` | `Float(Double)` | `as_float()` |
| `text`, `varchar`, `char` | `String(String)` | `as_string()` |
| `bytea` | `Bytes(Bytes)` | `as_bytes()` |
| `date` | `Date(String)` | `as_date()` |
| `time`, `timetz` | `Time(String)` | `as_time()` |
| `timestamp` | `Timestamp(String)` | `as_timestamp()` |
| `timestamptz` | `TimestampTz(String)` | `as_timestamp()` |
| `interval` | `Interval(String)` | `as_interval()` |
| `json`, `jsonb` | `Json(String)` | `as_json()` |
| `uuid` | `Uuid(String)` | `as_uuid()` |

## SSL/TLS

| Mode | Behavior |
|------|----------|
| `Disable` | Never use TLS |
| `Prefer` | Try TLS, fall back to plain if server refuses |
| `Require` | Must use TLS (default), skip certificate verification |
| `VerifyFull` | TLS with certificate verification |

## Development

```bash
# Build
moon build --target native

# Unit tests (no PostgreSQL needed)
make test

# Integration tests (starts a local PostgreSQL)
make test-integration

# All tests
make all
```

Requires PostgreSQL for integration tests. The test server is automatically managed:

```bash
./tests/setup-pg.sh start   # start on port 5433
./tests/setup-pg.sh stop    # stop
./tests/setup-pg.sh clean   # remove data directory
```
