///|
/// Integration Tests
///
/// Requires a running PostgreSQL instance at localhost:5432
/// with user/password/database = postgres/postgres/postgres.
///
/// Run with: moon test --target native src/tests/integration/
fn get_config() -> @pgsql.Config {
  @pgsql.Config::new(
    "postgres",
    "postgres",
    "postgres",
    host="127.0.0.1",
    port=5432,
  )
}

///|
async test "connect and query version" {
  let client = @pgsql.Client::connect(get_config())
  let result = client.query("SELECT version()")
  assert_true(result.row_count() > 0)
  let version = result.get_row(0).unwrap().get_string(0).unwrap()
  assert_true(version.contains("PostgreSQL"))
  client.close()
}

///|
async test "full CRUD lifecycle" {
  let client = @pgsql.Client::connect(get_config())

  // Create table
  let _ = client.execute(
    "CREATE TABLE IF NOT EXISTS test_crud (id SERIAL PRIMARY KEY, name TEXT NOT NULL, value INT)",
  )

  // Clean up from previous runs
  let _ = client.execute("DELETE FROM test_crud")

  // Insert
  let _ = client.execute_params(
    "INSERT INTO test_crud (name, value) VALUES ($1, $2)",
    [@pgsql.String("Alice"), @pgsql.Int(42)],
  )
  let _ = client.execute_params(
    "INSERT INTO test_crud (name, value) VALUES ($1, $2)",
    [@pgsql.String("Bob"), @pgsql.Int(99)],
  )

  // Select
  let result = client.query(
    "SELECT id, name, value FROM test_crud ORDER BY name",
  )
  assert_eq(result.row_count(), 2)
  assert_eq(result.get_row(0).unwrap().get_string(1), Some("Alice"))
  assert_eq(result.get_row(1).unwrap().get_string(1), Some("Bob"))
  assert_eq(result.get_row(0).unwrap().get_int(2), Some(42))

  // Update
  let affected = client.execute_params(
    "UPDATE test_crud SET value = $1 WHERE name = $2",
    [@pgsql.Int(100), @pgsql.String("Alice")],
  )
  assert_eq(affected, 1)

  // Verify update
  let result2 = client.query_params(
    "SELECT value FROM test_crud WHERE name = $1",
    [@pgsql.String("Alice")],
  )
  assert_eq(result2.get_row(0).unwrap().get_int(0), Some(100))

  // Delete
  let deleted = client.execute_params("DELETE FROM test_crud WHERE name = $1", [
    @pgsql.String("Bob"),
  ])
  assert_eq(deleted, 1)

  // Verify delete
  let result3 = client.query("SELECT COUNT(*) FROM test_crud")
  assert_eq(result3.get_row(0).unwrap().get_int(0), Some(1))

  // Drop table
  let _ = client.execute("DROP TABLE test_crud")
  client.close()
}

///|
async test "transaction commit" {
  let client = @pgsql.Client::connect(get_config())
  let _ = client.execute(
    "CREATE TABLE IF NOT EXISTS test_tx (id SERIAL PRIMARY KEY, val TEXT)",
  )
  let _ = client.execute("DELETE FROM test_tx")

  client.transaction(async fn(tx) {
    let _ = tx.execute_params("INSERT INTO test_tx (val) VALUES ($1)", [
      @pgsql.String("committed"),
    ])
    ()
  })

  let result = client.query("SELECT val FROM test_tx")
  assert_eq(result.row_count(), 1)
  assert_eq(result.get_row(0).unwrap().get_string(0), Some("committed"))

  let _ = client.execute("DROP TABLE test_tx")
  client.close()
}

///|
async test "transaction rollback on error" {
  let client = @pgsql.Client::connect(get_config())
  let _ = client.execute(
    "CREATE TABLE IF NOT EXISTS test_tx_rb (id SERIAL PRIMARY KEY, val TEXT NOT NULL)",
  )
  let _ = client.execute("DELETE FROM test_tx_rb")

  // Insert a valid row first
  let _ = client.execute_params("INSERT INTO test_tx_rb (val) VALUES ($1)", [
    @pgsql.String("before"),
  ])

  // This transaction should fail and rollback
  client.transaction(async fn(tx) {
    let _ = tx.execute_params("INSERT INTO test_tx_rb (val) VALUES ($1)", [
      @pgsql.String("inside"),
    ])
    // This will fail: NULL for NOT NULL column
    let _ = tx.execute_params("INSERT INTO test_tx_rb (val) VALUES ($1)", [
      @pgsql.Null,
    ])
    ()
  }) catch {
    _ => () // Expected error
  }

  // Only the pre-transaction row should remain
  let result = client.query("SELECT val FROM test_tx_rb ORDER BY id")
  assert_eq(result.row_count(), 1)
  assert_eq(result.get_row(0).unwrap().get_string(0), Some("before"))

  let _ = client.execute("DROP TABLE test_tx_rb")
  client.close()
}

///|
async test "parameterized queries with all Value types" {
  let client = @pgsql.Client::connect(get_config())
  let _ = client.execute(
    "CREATE TABLE IF NOT EXISTS test_types (b BOOL, i INT, bi BIGINT, f FLOAT8, t TEXT, n TEXT)",
  )
  let _ = client.execute("DELETE FROM test_types")

  let _ = client.execute_params(
    "INSERT INTO test_types (b, i, bi, f, t, n) VALUES ($1, $2, $3, $4, $5, $6)",
    [
      @pgsql.Bool(true),
      @pgsql.Int(42),
      @pgsql.Int64(9999999999L),
      @pgsql.Float(3.14),
      @pgsql.String("hello"),
      @pgsql.Null,
    ],
  )

  let result = client.query("SELECT b, i, bi, f, t, n FROM test_types")
  let row = result.get_row(0).unwrap()
  assert_eq(row.get_bool(0), Some(true))
  assert_eq(row.get_int(1), Some(42))
  assert_eq(row.get_int64(2), Some(9999999999L))
  // Float comparison with tolerance
  match row.get_float(3) {
    Some(f) => assert_true(f > 3.13 && f < 3.15)
    None => fail("Expected float value")
  }
  assert_eq(row.get_string(4), Some("hello"))
  assert_true(row.is_null(5))

  let _ = client.execute("DROP TABLE test_types")
  client.close()
}

///|
async test "error handling: invalid SQL" {
  let client = @pgsql.Client::connect(get_config())
  let mut got_error = false
  try {
    let _ = client.query("SELCT invalid syntax")
  } catch {
    _ => got_error = true
  }
  assert_true(got_error)
  // Client should still be usable after error
  let result = client.query("SELECT 1 AS val")
  assert_eq(result.get_row(0).unwrap().get_int(0), Some(1))
  client.close()
}

///|
async test "error handling: constraint violation" {
  let client = @pgsql.Client::connect(get_config())
  let _ = client.execute(
    "CREATE TABLE IF NOT EXISTS test_constraint (id INT PRIMARY KEY)",
  )
  let _ = client.execute("DELETE FROM test_constraint")

  let _ = client.execute_params(
    "INSERT INTO test_constraint (id) VALUES ($1)",
    [@pgsql.Int(1)],
  )

  // Duplicate key violation
  let mut got_error = false
  try {
    let _ = client.execute_params(
      "INSERT INTO test_constraint (id) VALUES ($1)",
      [@pgsql.Int(1)],
    )
  } catch {
    _ => got_error = true
  }
  assert_true(got_error)

  let _ = client.execute("DROP TABLE test_constraint")
  client.close()
}
