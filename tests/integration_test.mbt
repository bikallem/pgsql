///|
/// Integration Tests
///
/// Requires the dedicated test PostgreSQL instance at 127.0.0.1:5433
/// with SCRAM-SHA-256 auth and self-signed TLS.
///
/// Start with: ./tests/setup-pg.sh start
/// Run with:   moon test --target native tests/
fn get_config() -> @pgsql.Config {
  @pgsql.Config::new(
    "postgres",
    "postgres",
    "postgres",
    host="127.0.0.1",
    port=5433,
    ssl_mode=Require,
  )
}

///|
async test "connect and query version" {
  let client = @pgsql.Client::connect(get_config())
  let result = client.query("SELECT version()")
  assert_true(result.row_count() > 0)
  let version = result.row(0).unwrap().string(0).unwrap()
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
  assert_eq(result.row(0).unwrap().string(1), Some("Alice"))
  assert_eq(result.row(1).unwrap().string(1), Some("Bob"))
  assert_eq(result.row(0).unwrap().int(2), Some(42))

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
  assert_eq(result2.row(0).unwrap().int(0), Some(100))

  // Delete
  let deleted = client.execute_params("DELETE FROM test_crud WHERE name = $1", [
    @pgsql.String("Bob"),
  ])
  assert_eq(deleted, 1)

  // Verify delete
  let result3 = client.query("SELECT COUNT(*) FROM test_crud")
  assert_eq(result3.row(0).unwrap().int64(0), Some(1L))

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
  assert_eq(result.row(0).unwrap().string(0), Some("committed"))

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
  assert_eq(result.row(0).unwrap().string(0), Some("before"))

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
  let row = result.row(0).unwrap()
  assert_eq(row.bool(0), Some(true))
  assert_eq(row.int(1), Some(42))
  assert_eq(row.int64(2), Some(9999999999L))
  // Float comparison with tolerance
  match row.float(3) {
    Some(f) => assert_true(f > 3.13 && f < 3.15)
    None => fail("Expected float value")
  }
  assert_eq(row.string(4), Some("hello"))
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
  assert_eq(result.row(0).unwrap().int(0), Some(1))
  client.close()
}

///|
async test "prepared statement: insert and select" {
  let client = @pgsql.Client::connect(get_config())
  let _ = client.execute(
    "CREATE TABLE IF NOT EXISTS test_prep (id SERIAL PRIMARY KEY, name TEXT NOT NULL, value INT)",
  )
  let _ = client.execute("DELETE FROM test_prep")

  // Prepare insert statement
  let insert_stmt = client.prepare(
    "INSERT INTO test_prep (name, value) VALUES ($1, $2)",
  )

  // Execute 3 times with different params
  let _ = insert_stmt.execute([@pgsql.String("Alice"), @pgsql.Int(10)])
  let _ = insert_stmt.execute([@pgsql.String("Bob"), @pgsql.Int(20)])
  let _ = insert_stmt.execute([@pgsql.String("Carol"), @pgsql.Int(30)])
  insert_stmt.close()

  // Prepare select statement
  let select_stmt = client.prepare(
    "SELECT name, value FROM test_prep WHERE value > $1 ORDER BY name",
  )
  let result = select_stmt.query([@pgsql.Int(15)])
  assert_eq(result.row_count(), 2)
  assert_eq(result.row(0).unwrap().string(0), Some("Bob"))
  assert_eq(result.row(1).unwrap().string(0), Some("Carol"))
  select_stmt.close()

  let _ = client.execute("DROP TABLE test_prep")
  client.close()
}

///|
async test "prepared statement: close idempotency" {
  let client = @pgsql.Client::connect(get_config())

  let stmt = client.prepare("SELECT 1")
  stmt.close()
  // Second close should be a no-op, not an error
  stmt.close()
  assert_true(stmt.is_closed())

  client.close()
}

///|
async test "prepared statement: use after close raises error" {
  let client = @pgsql.Client::connect(get_config())

  let stmt = client.prepare("SELECT $1::int")
  stmt.close()

  let mut got_error = false
  try {
    let _ = stmt.query([@pgsql.Int(1)])
  } catch {
    @pgsql.PreparedStmtError(_) => got_error = true
    _ => ()
  }
  assert_true(got_error)

  client.close()
}

///|
async test "prepared statement: inside transaction" {
  let client = @pgsql.Client::connect(get_config())
  let _ = client.execute(
    "CREATE TABLE IF NOT EXISTS test_prep_tx (id SERIAL PRIMARY KEY, val TEXT)",
  )
  let _ = client.execute("DELETE FROM test_prep_tx")

  client.transaction(async fn(tx) {
    let stmt = tx.prepare("INSERT INTO test_prep_tx (val) VALUES ($1)")
    let _ = stmt.execute([@pgsql.String("tx_row1")])
    let _ = stmt.execute([@pgsql.String("tx_row2")])
    stmt.close()
  })

  let result = client.query("SELECT val FROM test_prep_tx ORDER BY id")
  assert_eq(result.row_count(), 2)
  assert_eq(result.row(0).unwrap().string(0), Some("tx_row1"))
  assert_eq(result.row(1).unwrap().string(0), Some("tx_row2"))

  let _ = client.execute("DROP TABLE test_prep_tx")
  client.close()
}

///|
async test "unnamed statement regression: many parameterized queries" {
  let client = @pgsql.Client::connect(get_config())
  let _ = client.execute(
    "CREATE TABLE IF NOT EXISTS test_unnamed (id SERIAL PRIMARY KEY, val INT)",
  )
  let _ = client.execute("DELETE FROM test_unnamed")

  // Run 100 parameterized queries in a loop — verifies unnamed statement
  // does not leak server resources
  for i = 0; i < 100; i = i + 1 {
    let _ = client.execute_params(
      "INSERT INTO test_unnamed (val) VALUES ($1)",
      [@pgsql.Int(i)],
    )
  }

  let result = client.query("SELECT COUNT(*) FROM test_unnamed")
  assert_eq(result.row(0).unwrap().int64(0), Some(100L))

  let _ = client.execute("DROP TABLE test_unnamed")
  client.close()
}

///|
async test "savepoint: commit through savepoint" {
  let client = @pgsql.Client::connect(get_config())
  let _ = client.execute(
    "CREATE TABLE IF NOT EXISTS test_sp (id SERIAL PRIMARY KEY, val TEXT)",
  )
  let _ = client.execute("DELETE FROM test_sp")

  client.transaction(async fn(tx) {
    let _ = tx.execute_params("INSERT INTO test_sp (val) VALUES ($1)", [
      @pgsql.String("before_sp"),
    ])

    tx.savepoint("sp1")
    let _ = tx.execute_params("INSERT INTO test_sp (val) VALUES ($1)", [
      @pgsql.String("in_sp"),
    ])

    // Rollback to savepoint — "in_sp" row is undone
    tx.rollback_to("sp1")

    let _ = tx.execute_params("INSERT INTO test_sp (val) VALUES ($1)", [
      @pgsql.String("after_rollback"),
    ])

    tx.release("sp1")
  })

  let result = client.query("SELECT val FROM test_sp ORDER BY id")
  assert_eq(result.row_count(), 2)
  assert_eq(result.row(0).unwrap().string(0), Some("before_sp"))
  assert_eq(result.row(1).unwrap().string(0), Some("after_rollback"))

  let _ = client.execute("DROP TABLE test_sp")
  client.close()
}

///|
async test "transaction: TxError on inactive transaction" {
  let client = @pgsql.Client::connect(get_config())

  client.transaction(async fn(tx) {
    // Explicitly commit, marking transaction as inactive
    tx.commit()

    // Now operations on the inactive transaction should raise TxError
    let mut got_error = false
    try {
      let _ = tx.execute("SELECT 1")
    } catch {
      @pgsql.TxError(_) => got_error = true
      _ => ()
    }
    assert_true(got_error)
  })

  client.close()
}

///|
async test "client: query after close raises error" {
  let client = @pgsql.Client::connect(get_config())
  // Verify the connection works
  let result = client.query("SELECT 1 AS val")
  assert_eq(result.row(0).unwrap().int(0), Some(1))

  client.close()

  // Operations on a closed client should raise an error
  let mut got_error = false
  try {
    let _ = client.query("SELECT 1")
  } catch {
    _ => got_error = true
  }
  assert_true(got_error)
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

///|
async test "auth error: wrong password" {
  let bad_config = @pgsql.Config::new(
    "postgres",
    "wrong_password",
    "postgres",
    host="127.0.0.1",
    port=5433,
    ssl_mode=Require,
  )
  let mut got_auth_error = false
  try {
    let _ = @pgsql.Client::connect(bad_config)
  } catch {
    @pgsql.AuthError(_) => got_auth_error = true
    _ => ()
  }
  assert_true(got_auth_error)
}

///|
async test "date, time, timestamp, json, uuid types" {
  let client = @pgsql.Client::connect(get_config())
  let result = client.query(
    "SELECT CURRENT_DATE, CURRENT_TIME, CURRENT_TIMESTAMP, '2024-03-15 14:30:00'::timestamp, '1 day'::interval, '{\"k\":\"v\"}'::json, '{\"a\":1}'::jsonb, gen_random_uuid()",
  )
  assert_eq(result.row_count(), 1)
  let row = result.row(0).unwrap()

  // Date
  assert_true(row.date(0) is Some(_))
  // Time
  assert_true(row.time(1) is Some(_))
  // TimestampTz (CURRENT_TIMESTAMP returns timestamptz)
  assert_true(row.timestamp(2) is Some(_))
  // Timestamp without tz
  assert_true(row.timestamp(3) is Some(_))
  // Interval
  assert_eq(row.get(4), Some(@pgsql.Interval("1 day")))
  // JSON
  inspect(
    row.json(5),
    content=(
      #|Some("{\"k\":\"v\"}")
    ),
  )
  // JSONB (note: JSONB may reformat keys)
  assert_true(row.json(6) is Some(_))
  // UUID
  assert_true(row.uuid(7) is Some(_))

  // Verify parameterized queries work with new types
  let result2 = client.query_params("SELECT $1::date, $2::json, $3::uuid", [
    @pgsql.Date("2024-01-15"),
    @pgsql.Json("{\"x\":42}"),
    @pgsql.Uuid("550e8400-e29b-41d4-a716-446655440000"),
  ])
  let row2 = result2.row(0).unwrap()
  assert_eq(row2.date(0), Some("2024-01-15"))
  inspect(
    row2.json(1),
    content=(
      #|Some("{\"x\":42}")
    ),
  )
  assert_eq(row2.uuid(2), Some("550e8400-e29b-41d4-a716-446655440000"))

  client.close()
}

///|
async test "COPY OUT: export rows" {
  let client = @pgsql.Client::connect(get_config())
  let _ = client.execute(
    "CREATE TABLE IF NOT EXISTS test_copy_out (id INT, name TEXT)",
  )
  let _ = client.execute("DELETE FROM test_copy_out")
  let _ = client.execute(
    "INSERT INTO test_copy_out VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Carol')",
  )

  let chunks : Array[String] = []
  let rows = client.copy_out("COPY test_copy_out TO STDOUT", fn(data : Bytes) {
    let chars : Array[Char] = Array::new(capacity=data.length())
    for i = 0; i < data.length(); i = i + 1 {
      chars.push(data[i].to_int().unsafe_to_char())
    }
    chunks.push(String::from_array(chars))
  })
  assert_eq(rows, 3)
  // Chunks should contain tab-separated data
  let all_data = chunks.iter().fold(init="", fn(acc, s) { acc + s })
  assert_true(all_data.contains("Alice"))
  assert_true(all_data.contains("Bob"))

  let _ = client.execute("DROP TABLE test_copy_out")
  client.close()
}

///|
async test "COPY IN: import rows" {
  let client = @pgsql.Client::connect(get_config())
  let _ = client.execute(
    "CREATE TABLE IF NOT EXISTS test_copy_in (id INT, name TEXT)",
  )
  let _ = client.execute("DELETE FROM test_copy_in")

  let rows = client.copy_in("COPY test_copy_in FROM STDIN", async fn(w) {
    w.write_row(["1", "Alice"])
    w.write_row(["2", "Bob"])
    w.write_row(["3", "Carol"])
  })
  assert_eq(rows, 3)

  let result = client.query("SELECT id, name FROM test_copy_in ORDER BY id")
  assert_eq(result.row_count(), 3)
  assert_eq(result.row(0).unwrap().string(1), Some("Alice"))
  assert_eq(result.row(1).unwrap().string(1), Some("Bob"))
  assert_eq(result.row(2).unwrap().string(1), Some("Carol"))

  let _ = client.execute("DROP TABLE test_copy_in")
  client.close()
}

///|
async test "LISTEN/NOTIFY: basic notification" {
  let listener = @pgsql.Client::connect(get_config())
  let notifier = @pgsql.Client::connect(get_config())

  listener.listen("test_channel")

  // Send notification from another client
  let _ = notifier.execute("NOTIFY test_channel, 'hello'")

  // Wait for the notification
  let notification = listener.wait_for_notification()
  assert_eq(notification.channel(), "test_channel")
  assert_eq(notification.payload(), "hello")
  assert_true(notification.process_id() > 0)

  listener.unlisten("test_channel")
  listener.close()
  notifier.close()
}

///|
async test "LISTEN/NOTIFY: poll_notifications" {
  let listener = @pgsql.Client::connect(get_config())
  let notifier = @pgsql.Client::connect(get_config())

  listener.listen("poll_ch")

  // Send two notifications
  let _ = notifier.execute("NOTIFY poll_ch, 'msg1'")
  let _ = notifier.execute("NOTIFY poll_ch, 'msg2'")

  // Trigger a query to receive the notifications
  let _ = listener.query("SELECT 1")

  let notifications = listener.poll_notifications()
  assert_eq(notifications.length(), 2)
  assert_eq(notifications[0].payload(), "msg1")
  assert_eq(notifications[1].payload(), "msg2")

  // Queue should be empty now
  let empty = listener.poll_notifications()
  assert_eq(empty.length(), 0)

  listener.unlisten("poll_ch")
  listener.close()
  notifier.close()
}

///|
async test "pool: acquire and release" {
  let pool = @pgsql.Pool::new(get_config(), max_size=3)

  let client1 = pool.acquire()
  let result = client1.query("SELECT 1 AS val")
  assert_eq(result.row(0).unwrap().int(0), Some(1))
  pool.release(client1)

  // Acquire again — should reuse the released connection
  let client2 = pool.acquire()
  let result2 = client2.query("SELECT 2 AS val")
  assert_eq(result2.row(0).unwrap().int(0), Some(2))
  pool.release(client2)

  pool.close()
}

///|
async test "pool: with_connection auto-release" {
  let pool = @pgsql.Pool::new(get_config(), max_size=2)

  let value = pool.with_connection(async fn(client) {
    let result = client.query("SELECT 42 AS val")
    result.row(0).unwrap().int(0).unwrap()
  })
  assert_eq(value, 42)

  // Connection should have been released — acquire should work
  let client = pool.acquire()
  let result = client.query("SELECT 1")
  assert_eq(result.row(0).unwrap().int(0), Some(1))
  pool.release(client)

  pool.close()
}

///|
async test "stream: basic row streaming" {
  let client = @pgsql.Client::connect(get_config())
  let _ = client.execute("CREATE TABLE IF NOT EXISTS test_stream (id INT)")
  let _ = client.execute("DELETE FROM test_stream")
  let _ = client.execute(
    "INSERT INTO test_stream SELECT generate_series(1, 250)",
  )

  let stream = client.query_stream(
    "SELECT id FROM test_stream ORDER BY id",
    batch_size=50,
  )
  assert_eq(stream.fields().length(), 1)

  let mut count = 0
  let mut last_id = 0
  stream.for_each(fn(row) {
    count += 1
    last_id = row.int(0).unwrap()
  })
  assert_eq(count, 250)
  assert_eq(last_id, 250)

  let _ = client.execute("DROP TABLE test_stream")
  client.close()
}

///|
async test "stream: close before exhaustion" {
  let client = @pgsql.Client::connect(get_config())
  let _ = client.execute(
    "CREATE TABLE IF NOT EXISTS test_stream_close (id INT)",
  )
  let _ = client.execute("DELETE FROM test_stream_close")
  let _ = client.execute(
    "INSERT INTO test_stream_close SELECT generate_series(1, 100)",
  )

  let stream = client.query_stream(
    "SELECT id FROM test_stream_close ORDER BY id",
    batch_size=10,
  )

  // Read only 5 rows
  let mut count = 0
  while count < 5 {
    match stream.next() {
      Some(_) => count += 1
      None => break
    }
  }
  assert_eq(count, 5)

  // Close the stream early
  stream.close()

  // Client should still be usable
  let result = client.query("SELECT 1 AS val")
  assert_eq(result.row(0).unwrap().int(0), Some(1))

  let _ = client.execute("DROP TABLE test_stream_close")
  client.close()
}

///|
async test "stream: parameterized streaming" {
  let client = @pgsql.Client::connect(get_config())
  let _ = client.execute(
    "CREATE TABLE IF NOT EXISTS test_stream_params (id INT, name TEXT)",
  )
  let _ = client.execute("DELETE FROM test_stream_params")
  let _ = client.execute(
    "INSERT INTO test_stream_params VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Alice')",
  )

  let stream = client.query_stream(
    "SELECT id FROM test_stream_params WHERE name = $1 ORDER BY id",
    params=[@pgsql.String("Alice")],
    batch_size=10,
  )

  let mut count = 0
  stream.for_each(fn(_row) { count += 1 })
  assert_eq(count, 2)

  let _ = client.execute("DROP TABLE test_stream_params")
  client.close()
}

///|
async test "connect with ssl_mode=Disable (plain SCRAM)" {
  let plain_config = @pgsql.Config::new(
    "postgres",
    "postgres",
    "postgres",
    host="127.0.0.1",
    port=5433,
    ssl_mode=Disable,
  )
  let client = @pgsql.Client::connect(plain_config)
  let result = client.query("SELECT 1 AS val")
  assert_eq(result.row(0).unwrap().int(0), Some(1))
  client.close()
}
