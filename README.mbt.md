# bikallem/postgresql

A PostgreSQL database driver for MoonBit implementing the PostgreSQL wire protocol (v3.0).

Native-only. Requires `moonbitlang/async` for async I/O.

- [Install](#install)
- [Usage](#usage)
  - [Value Types](#value-types)
  - [Prepared Statements](#prepared-statements)
  - [Transactions](#transactions)
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
  let result = client.query_params(
    "SELECT * FROM users WHERE age > $1",
    [Int(21)],
  )
  let _ = result

  client.close()
}
```

### Value Types

Parameters and results use the `Value` enum:

| Variant | MoonBit Type | PostgreSQL Types |
|---------|-------------|-----------------|
| `Null` | — | NULL |
| `Bool(Bool)` | `Bool` | BOOLEAN |
| `Int(Int)` | `Int` | SMALLINT, INTEGER |
| `Int64(Int64)` | `Int64` | BIGINT |
| `Float(Double)` | `Double` | REAL, DOUBLE PRECISION, NUMERIC |
| `String(String)` | `String` | TEXT, VARCHAR, CHAR, and all other types |
| `Bytes(Bytes)` | `Bytes` | BYTEA |

Row accessors: `int(i)`, `int64(i)`, `float(i)`, `bool(i)`,
`string(i)`, `by_name(name)`, `is_null(i)`.

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
    let _ = tx.execute_params(
      "INSERT INTO users (name) VALUES ($1)",
      [String("Carol")],
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
