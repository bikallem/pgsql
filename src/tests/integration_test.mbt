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
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_crud (id SERIAL PRIMARY KEY, name TEXT NOT NULL, value INT)",
      ) : Int),
  )

  // Clean up from previous runs
  ignore((client.execute("DELETE FROM test_crud") : Int))

  // Insert
  ignore(
    (
      client.execute_params(
        "INSERT INTO test_crud (name, value) VALUES ($1, $2)",
        [@pgsql.String("Alice"), @pgsql.Int(42)],
      ) : Int),
  )
  ignore(
    (
      client.execute_params(
        "INSERT INTO test_crud (name, value) VALUES ($1, $2)",
        [@pgsql.String("Bob"), @pgsql.Int(99)],
      ) : Int),
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
  ignore((client.execute("DROP TABLE test_crud") : Int))
  client.close()
}

///|
async test "transaction commit" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_tx (id SERIAL PRIMARY KEY, val TEXT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_tx") : Int))

  client.transaction(async fn(tx) {
    ignore(
      (
        tx.execute_params("INSERT INTO test_tx (val) VALUES ($1)", [
          @pgsql.String("committed"),
        ]) : Int),
    )
    ()
  })

  let result = client.query("SELECT val FROM test_tx")
  assert_eq(result.row_count(), 1)
  assert_eq(result.row(0).unwrap().string(0), Some("committed"))

  ignore((client.execute("DROP TABLE test_tx") : Int))
  client.close()
}

///|
async test "transaction rollback on error" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_tx_rb (id SERIAL PRIMARY KEY, val TEXT NOT NULL)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_tx_rb") : Int))

  // Insert a valid row first
  ignore(
    (
      client.execute_params("INSERT INTO test_tx_rb (val) VALUES ($1)", [
        @pgsql.String("before"),
      ]) : Int),
  )

  // This transaction should fail and rollback
  client.transaction(async fn(tx) {
    ignore(
      (
        tx.execute_params("INSERT INTO test_tx_rb (val) VALUES ($1)", [
          @pgsql.String("inside"),
        ]) : Int),
    )
    // This will fail: NULL for NOT NULL column
    ignore(
      (
        tx.execute_params("INSERT INTO test_tx_rb (val) VALUES ($1)", [
          @pgsql.Null,
        ]) : Int),
    )
    ()
  }) catch {
    _ => () // Expected error
  }

  // Only the pre-transaction row should remain
  let result = client.query("SELECT val FROM test_tx_rb ORDER BY id")
  assert_eq(result.row_count(), 1)
  assert_eq(result.row(0).unwrap().string(0), Some("before"))

  ignore((client.execute("DROP TABLE test_tx_rb") : Int))
  client.close()
}

///|
/// Regression: direct Client operations in transaction callback must fail fast.
async test "transaction callback: direct client query fails fast" {
  let client = @pgsql.Client::connect(get_config())

  let mut saw_usage_error = false
  let failed = try {
    client.transaction(async fn(_tx) {
      ignore((client.query("SELECT 1") : @pgsql.QueryResult))
    })
    false
  } catch {
    @pgsql.ClientUsageError(msg) => {
      saw_usage_error = msg.contains("transaction callback")
      true
    }
    _ => false
  }

  assert_true(failed)
  assert_true(saw_usage_error)
  // Client remains usable after fail-fast rejection.
  let result = client.query("SELECT 1 AS ok")
  assert_eq(result.row(0).unwrap().int(0), Some(1))
  client.close()
}

///|
/// Regression: concurrent Client operations are rejected while tx callback owns
/// the connection lease.
async test "transaction callback: concurrent client query fails fast" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute("CREATE TABLE IF NOT EXISTS test_tx_exclusive (id INT)") :
      Int),
  )
  ignore((client.execute("DELETE FROM test_tx_exclusive") : Int))

  let concurrent_rejected = @async.with_task_group(async fn(group) {
    let tx_task = group.spawn(async fn() {
      client.transaction(async fn(tx) {
        ignore((tx.execute("INSERT INTO test_tx_exclusive VALUES (1)") : Int))
        // Keep callback active while concurrent operation attempts access.
        @async.sleep(150)
        ignore((tx.execute("INSERT INTO test_tx_exclusive VALUES (2)") : Int))
      })
    })

    // Let callback start before launching concurrent query.
    @async.sleep(50)
    let concurrent_task = group.spawn(async fn() {
      try {
        ignore(
          (
            client.query("SELECT COUNT(*) FROM test_tx_exclusive") :
            @pgsql.QueryResult),
        )
        false
      } catch {
        @pgsql.ClientUsageError(msg) => msg.contains("transaction callback")
        _ => false
      }
    })

    let rejected = concurrent_task.wait()
    tx_task.wait()
    rejected
  })

  assert_true(concurrent_rejected)

  let final_count = client.query("SELECT COUNT(*) FROM test_tx_exclusive")
  assert_eq(final_count.row(0).unwrap().int64(0), Some(2L))

  ignore((client.execute("DROP TABLE test_tx_exclusive") : Int))
  client.close()
}

///|
async test "parameterized queries with all Value types" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_types (b BOOL, i INT, bi BIGINT, f FLOAT8, t TEXT, n TEXT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_types") : Int))

  ignore(
    (
      client.execute_params(
        "INSERT INTO test_types (b, i, bi, f, t, n) VALUES ($1, $2, $3, $4, $5, $6)",
        [
          @pgsql.Bool(true),
          @pgsql.Int(42),
          @pgsql.Int64(9999999999L),
          @pgsql.Float(3.14),
          @pgsql.String("hello"),
          @pgsql.Null,
        ],
      ) : Int),
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

  ignore((client.execute("DROP TABLE test_types") : Int))
  client.close()
}

///|
async test "UTF-8 text round-trip via parameters and row decoding" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_utf8 (id INT PRIMARY KEY, val TEXT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_utf8") : Int))

  let text = @utf8.decode_lossy(
    Bytes::from_array([
      b'e', b'm', b'o', b'j', b'i', b'-', b'\xF0', b'\x9F', b'\x9A', b'\x80', b' ',
      b'a', b'n', b'd', b' ', b'k', b'a', b'n', b'a', b'-', b'\xE3', b'\x81', b'\x93',
      b'\xE3', b'\x82', b'\x93', b'\xE3', b'\x81', b'\xAB', b'\xE3', b'\x81', b'\xA1',
      b'\xE3', b'\x81', b'\xAF',
    ])[:],
  )
  ignore(
    (
      client.execute_params("INSERT INTO test_utf8 (id, val) VALUES ($1, $2)", [
        @pgsql.Int(1),
        @pgsql.String(text),
      ]) : Int),
  )

  let result = client.query("SELECT val FROM test_utf8 WHERE id = 1")
  assert_eq(result.row(0).unwrap().string(0), Some(text))

  ignore((client.execute("DROP TABLE test_utf8") : Int))
  client.close()
}

///|
async test "error handling: invalid SQL" {
  let client = @pgsql.Client::connect(get_config())
  let mut got_error = false
  ignore((client.query("SELCT invalid syntax") : @pgsql.QueryResult)) catch {
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
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_prep (id SERIAL PRIMARY KEY, name TEXT NOT NULL, value INT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_prep") : Int))

  // Prepare insert statement
  let insert_stmt = client.prepare(
    "INSERT INTO test_prep (name, value) VALUES ($1, $2)",
  )

  // Execute 3 times with different params
  ignore((insert_stmt.execute([@pgsql.String("Alice"), @pgsql.Int(10)]) : Int))
  ignore((insert_stmt.execute([@pgsql.String("Bob"), @pgsql.Int(20)]) : Int))
  ignore((insert_stmt.execute([@pgsql.String("Carol"), @pgsql.Int(30)]) : Int))
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

  ignore((client.execute("DROP TABLE test_prep") : Int))
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
  ignore((stmt.query([@pgsql.Int(1)]) : @pgsql.QueryResult)) catch {
    @pgsql.PreparedStmtError(_) => got_error = true
    _ => ()
  }
  assert_true(got_error)

  client.close()
}

///|
async test "prepared statement: inside transaction" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_prep_tx (id SERIAL PRIMARY KEY, val TEXT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_prep_tx") : Int))

  client.transaction(async fn(tx) {
    let stmt = tx.prepare("INSERT INTO test_prep_tx (val) VALUES ($1)")
    ignore((stmt.execute([@pgsql.String("tx_row1")]) : Int))
    ignore((stmt.execute([@pgsql.String("tx_row2")]) : Int))
    stmt.close()
  })

  let result = client.query("SELECT val FROM test_prep_tx ORDER BY id")
  assert_eq(result.row_count(), 2)
  assert_eq(result.row(0).unwrap().string(0), Some("tx_row1"))
  assert_eq(result.row(1).unwrap().string(0), Some("tx_row2"))

  ignore((client.execute("DROP TABLE test_prep_tx") : Int))
  client.close()
}

///|
async test "unnamed statement regression: many parameterized queries" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_unnamed (id SERIAL PRIMARY KEY, val INT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_unnamed") : Int))

  // Run 100 parameterized queries in a loop — verifies unnamed statement
  // does not leak server resources
  for i = 0; i < 100; i = i + 1 {
    ignore(
      (
        client.execute_params("INSERT INTO test_unnamed (val) VALUES ($1)", [
          @pgsql.Int(i),
        ]) : Int),
    )
  }

  let result = client.query("SELECT COUNT(*) FROM test_unnamed")
  assert_eq(result.row(0).unwrap().int64(0), Some(100L))

  ignore((client.execute("DROP TABLE test_unnamed") : Int))
  client.close()
}

///|
async test "savepoint: commit through savepoint" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_sp (id SERIAL PRIMARY KEY, val TEXT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_sp") : Int))

  client.transaction(async fn(tx) {
    ignore(
      (
        tx.execute_params("INSERT INTO test_sp (val) VALUES ($1)", [
          @pgsql.String("before_sp"),
        ]) : Int),
    )

    tx.savepoint("sp1")
    ignore(
      (
        tx.execute_params("INSERT INTO test_sp (val) VALUES ($1)", [
          @pgsql.String("in_sp"),
        ]) : Int),
    )

    // Rollback to savepoint — "in_sp" row is undone
    tx.rollback_to("sp1")

    ignore(
      (
        tx.execute_params("INSERT INTO test_sp (val) VALUES ($1)", [
          @pgsql.String("after_rollback"),
        ]) : Int),
    )

    tx.release("sp1")
  })

  let result = client.query("SELECT val FROM test_sp ORDER BY id")
  assert_eq(result.row_count(), 2)
  assert_eq(result.row(0).unwrap().string(0), Some("before_sp"))
  assert_eq(result.row(1).unwrap().string(0), Some("after_rollback"))

  ignore((client.execute("DROP TABLE test_sp") : Int))
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
    ignore((tx.execute("SELECT 1") : Int)) catch {
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
  ignore((client.query("SELECT 1") : @pgsql.QueryResult)) catch {
    _ => got_error = true
  }
  assert_true(got_error)
}

///|
async test "error handling: constraint violation" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_constraint (id INT PRIMARY KEY)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_constraint") : Int))

  ignore(
    (
      client.execute_params("INSERT INTO test_constraint (id) VALUES ($1)", [
        @pgsql.Int(1),
      ]) : Int),
  )

  // Duplicate key violation
  let mut got_error = false
  ignore(
    (
      client.execute_params("INSERT INTO test_constraint (id) VALUES ($1)", [
        @pgsql.Int(1),
      ]) : Int),
  ) catch {
    _ => got_error = true
  }
  assert_true(got_error)

  ignore((client.execute("DROP TABLE test_constraint") : Int))
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
  // Use task group to reliably catch async errors on all platforms
  let got_error = @async.with_task_group(async fn(group) {
    let task = group.spawn(async fn() {
      try {
        let client = @pgsql.Client::connect(bad_config)
        client.close()
        false
      } catch {
        _ => true
      }
    })
    task.wait()
  })
  assert_true(got_error)
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
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_copy_out (id INT, name TEXT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_copy_out") : Int))
  ignore(
    (
      client.execute(
        "INSERT INTO test_copy_out VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Carol')",
      ) : Int),
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

  ignore((client.execute("DROP TABLE test_copy_out") : Int))
  client.close()
}

///|
async test "COPY IN: import rows" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_copy_in (id INT, name TEXT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_copy_in") : Int))

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

  ignore((client.execute("DROP TABLE test_copy_in") : Int))
  client.close()
}

///|
async test "COPY IN: write_row escapes COPY text special characters" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_copy_escape (a TEXT, b TEXT, c TEXT, d TEXT, e TEXT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_copy_escape") : Int))

  let rows = client.copy_in("COPY test_copy_escape FROM STDIN", async fn(w) {
    w.write_row(["tab\tvalue", "line1\nline2", "car\rret", "slash\\\\x", "\\N"])
  })
  assert_eq(rows, 1)

  let result = client.query("SELECT a, b, c, d, e FROM test_copy_escape")
  let row = result.row(0).unwrap()
  assert_eq(row.string(0), Some("tab\tvalue"))
  assert_eq(row.string(1), Some("line1\nline2"))
  assert_eq(row.string(2), Some("car\rret"))
  assert_eq(row.string(3), Some("slash\\\\x"))
  assert_eq(row.string(4), Some("\\N"))

  ignore((client.execute("DROP TABLE test_copy_escape") : Int))
  client.close()
}

///|
async test "COPY IN: write_row_nullable supports NULL values" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_copy_nullable (a TEXT, b TEXT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_copy_nullable") : Int))

  let rows = client.copy_in("COPY test_copy_nullable FROM STDIN", async fn(w) {
    w.write_row_nullable([Some("alive"), None])
  })
  assert_eq(rows, 1)

  let result = client.query("SELECT a, b FROM test_copy_nullable")
  let row = result.row(0).unwrap()
  assert_eq(row.string(0), Some("alive"))
  assert_true(row.is_null(1))

  ignore((client.execute("DROP TABLE test_copy_nullable") : Int))
  client.close()
}

///|
async test "COPY IN: writer rejects writes after callback return" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_copy_writer_escape (id INT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_copy_writer_escape") : Int))

  let mut leaked_writer : @pgsql.CopyWriter? = None
  let rows = client.copy_in("COPY test_copy_writer_escape FROM STDIN", async fn(
    w,
  ) {
    leaked_writer = Some(w)
    w.write_row(["1"])
  })
  assert_eq(rows, 1)

  let mut rejected = false
  match leaked_writer {
    Some(writer) =>
      writer.write_row(["2"]) catch {
        @pgsql.CopyError(msg) => rejected = msg.contains("no longer active")
        _ => ()
      }
    None => fail("Expected leaked writer to be captured in callback")
  }
  assert_true(rejected)

  let result = client.query("SELECT COUNT(*) FROM test_copy_writer_escape")
  assert_eq(result.row(0).unwrap().int64(0), Some(1L))

  ignore((client.execute("DROP TABLE test_copy_writer_escape") : Int))
  client.close()
}

///|
async test "COPY OUT: re-entrant callback operation fails fast" {
  let client = @pgsql.Client::connect(get_config())

  let mut saw_usage_error = false
  let failed = try {
    ignore(
      (
        client.copy_out("COPY (SELECT 1) TO STDOUT", async fn(_data : Bytes) {
          ignore((client.query("SELECT 1") : @pgsql.QueryResult))
        }) : Int),
    )
    false
  } catch {
    @pgsql.CopyCallbackError(failure) => {
      saw_usage_error = failure.message.contains("ClientUsageError")
      true
    }
    @pgsql.CopyError(msg) => {
      saw_usage_error = msg.contains("ClientUsageError")
      true
    }
    _ => false
  }
  assert_true(failed)
  assert_true(saw_usage_error)

  // Connection should remain usable after fail-fast callback rejection.
  let result = client.query("SELECT 1 AS ok")
  assert_eq(result.row(0).unwrap().int(0), Some(1))
  client.close()
}

///|
async test "COPY IN: re-entrant callback operation fails fast" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_copy_in_reentrant (id INT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_copy_in_reentrant") : Int))

  let mut saw_usage_error = false
  let failed = try {
    ignore(
      (
        client.copy_in("COPY test_copy_in_reentrant FROM STDIN", async fn(
          w : @pgsql.CopyWriter,
        ) {
          ignore((client.query("SELECT 1") : @pgsql.QueryResult))
          w.write_row(["1"])
        }) : Int),
    )
    false
  } catch {
    @pgsql.CopyCallbackError(failure) => {
      saw_usage_error = failure.message.contains("ClientUsageError")
      true
    }
    @pgsql.CopyError(msg) => {
      saw_usage_error = msg.contains("ClientUsageError")
      true
    }
    _ => false
  }
  assert_true(failed)
  assert_true(saw_usage_error)

  let count_result = client.query("SELECT COUNT(*) FROM test_copy_in_reentrant")
  assert_eq(count_result.row(0).unwrap().int64(0), Some(0L))

  ignore((client.execute("DROP TABLE test_copy_in_reentrant") : Int))
  client.close()
}

///|
async test "LISTEN/NOTIFY: basic notification" {
  let listener = @pgsql.Client::connect(get_config())
  let notifier = @pgsql.Client::connect(get_config())

  listener.listen("test_channel")

  // Send notification from another client
  ignore((notifier.execute("NOTIFY test_channel, 'hello'") : Int))

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
  ignore((notifier.execute("NOTIFY poll_ch, 'msg1'") : Int))
  ignore((notifier.execute("NOTIFY poll_ch, 'msg2'") : Int))

  // Trigger a query to receive the notifications
  ignore((listener.query("SELECT 1") : @pgsql.QueryResult))

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
async test "LISTEN/NOTIFY: UTF-8 payload round-trip" {
  let listener = @pgsql.Client::connect(get_config())
  let notifier = @pgsql.Client::connect(get_config())

  listener.listen("utf8_ch")

  let payload = @utf8.decode_lossy(
    Bytes::from_array([
      b'n', b'o', b't', b'i', b'f', b'y', b'-', b'\xF0', b'\x9F', b'\x8E', b'\x89',
      b'-', b'\xE4', b'\xB8', b'\x96', b'\xE7', b'\x95', b'\x8C',
    ])[:],
  )
  ignore(
    (
      notifier.execute_params("SELECT pg_notify('utf8_ch', $1)", [
        @pgsql.String(payload),
      ]) : Int),
  )

  let notification = listener.wait_for_notification()
  assert_eq(notification.channel(), "utf8_ch")
  assert_eq(notification.payload(), payload)

  listener.unlisten("utf8_ch")
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
  ignore(
    (client.execute("CREATE TABLE IF NOT EXISTS test_stream (id INT)") : Int),
  )
  ignore((client.execute("DELETE FROM test_stream") : Int))
  ignore(
    (
      client.execute("INSERT INTO test_stream SELECT generate_series(1, 250)") :
      Int),
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

  ignore((client.execute("DROP TABLE test_stream") : Int))
  client.close()
}

///|
async test "stream: close before exhaustion" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute("CREATE TABLE IF NOT EXISTS test_stream_close (id INT)") :
      Int),
  )
  ignore((client.execute("DELETE FROM test_stream_close") : Int))
  ignore(
    (
      client.execute(
        "INSERT INTO test_stream_close SELECT generate_series(1, 100)",
      ) : Int),
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

  ignore((client.execute("DROP TABLE test_stream_close") : Int))
  client.close()
}

///|
/// Regression: stream auto-transaction commit must occur before lock release.
async test "stream: close commits before allowing concurrent query" {
  let client = @pgsql.Client::connect(get_config())

  let stream = client.query_stream(
    "SELECT txid_current()::bigint AS xid, g FROM generate_series(1, 8) AS g",
    batch_size=1,
  )
  let first_row = stream.next().unwrap()
  let stream_xid = first_row.int64(0).unwrap()

  let outsider_xid = @async.with_task_group(async fn(group) {
    // This query blocks on stream-held operation lock until close releases it.
    let outsider = group.spawn(async fn() {
      let result = client.query("SELECT txid_current()::bigint")
      result.row(0).unwrap().int64(0).unwrap()
    })
    @async.sleep(20)
    stream.close()
    outsider.wait()
  })

  // If close releases lock before COMMIT, outsider can run in same tx xid.
  assert_true(outsider_xid != stream_xid)

  client.close()
}

///|
async test "stream: parameterized streaming" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_stream_params (id INT, name TEXT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_stream_params") : Int))
  ignore(
    (
      client.execute(
        "INSERT INTO test_stream_params VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Alice')",
      ) : Int),
  )

  let stream = client.query_stream(
    "SELECT id FROM test_stream_params WHERE name = $1 ORDER BY id",
    params=[@pgsql.String("Alice")],
    batch_size=10,
  )

  let mut count = 0
  stream.for_each(fn(_row) { count += 1 })
  assert_eq(count, 2)

  ignore((client.execute("DROP TABLE test_stream_params") : Int))
  client.close()
}

///|
async test "stream: invalid batch_size rejected" {
  let client = @pgsql.Client::connect(get_config())

  let mut got_error = false
  ignore((client.query_stream("SELECT 1", batch_size=0) : @pgsql.RowStream)) catch {
    @pgsql.StreamError(msg) => got_error = msg.contains("batch_size")
    _ => ()
  }
  assert_true(got_error)

  // Ensure no lock leaked on validation error.
  let result = client.query("SELECT 1 AS ok")
  assert_eq(result.row(0).unwrap().int(0), Some(1))
  client.close()
}

///|
async test "stream: next() exhausts and auto-closes resources" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_stream_auto_close (id INT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_stream_auto_close") : Int))
  ignore(
    (
      client.execute("INSERT INTO test_stream_auto_close VALUES (1), (2), (3)") :
      Int),
  )

  let stream = client.query_stream(
    "SELECT id FROM test_stream_auto_close ORDER BY id",
    batch_size=1,
  )
  let seen : Array[Int] = []
  while true {
    match stream.next() {
      Some(row) => seen.push(row.int(0).unwrap())
      None => break
    }
  }
  assert_eq(seen.length(), 3)
  assert_eq(seen[0], 1)
  assert_eq(seen[2], 3)

  // Should work without explicit stream.close() call.
  let result = client.query("SELECT COUNT(*) FROM test_stream_auto_close")
  assert_eq(result.row(0).unwrap().int64(0), Some(3L))

  ignore((client.execute("DROP TABLE test_stream_auto_close") : Int))
  client.close()
}

///|
async test "stream: re-entrant callback operation fails fast" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_stream_reentrant (id INT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_stream_reentrant") : Int))
  ignore(
    (
      client.execute("INSERT INTO test_stream_reentrant VALUES (1), (2), (3)") :
      Int),
  )

  let stream = client.query_stream(
    "SELECT id FROM test_stream_reentrant ORDER BY id",
    batch_size=2,
  )
  let mut saw_usage_error = false
  let failed = try {
    stream.for_each(async fn(_row) {
      ignore((client.query("SELECT 1") : @pgsql.QueryResult))
    })
    false
  } catch {
    @pgsql.ClientUsageError(msg) => {
      saw_usage_error = msg.contains("Re-entrant operations")
      true
    }
    _ => false
  }
  assert_true(failed)
  assert_true(saw_usage_error)

  // Stream close on callback error should leave client usable.
  let result = client.query("SELECT 1 AS val")
  assert_eq(result.row(0).unwrap().int(0), Some(1))

  ignore((client.execute("DROP TABLE test_stream_reentrant") : Int))
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

///|
async test "client: transaction_status transitions" {
  let client = @pgsql.Client::connect(get_config())

  // Initially idle
  assert_eq(client.transaction_status(), @pgsql.Idle)

  client.transaction(async fn(tx) {
    // Inside transaction
    assert_eq(client.transaction_status(), @pgsql.InTransaction)
    ignore((tx.execute("SELECT 1") : Int))
  })

  // After commit, back to idle
  assert_eq(client.transaction_status(), @pgsql.Idle)
  client.close()
}

///|
async test "client: server_param retrieves server_version" {
  let client = @pgsql.Client::connect(get_config())

  let version = client.server_param("server_version")
  assert_true(version is Some(_))
  // server_version contains the version number, e.g. "16.2"
  assert_true(version.unwrap().length() > 0)

  // Non-existent parameter should return None
  let missing = client.server_param("nonexistent_param_xyz")
  assert_true(missing is None)

  client.close()
}

///|
async test "row: by_name column access" {
  let client = @pgsql.Client::connect(get_config())

  let result = client.query("SELECT 1 AS num, 'hello' AS txt")
  let row = result.row(0).unwrap()

  // Access by name
  assert_eq(row.by_name("num"), Some(@pgsql.Int(1)))
  assert_eq(row.by_name("txt"), Some(@pgsql.String("hello")))

  // Non-existent column returns None
  assert_eq(row.by_name("nonexistent"), None)

  client.close()
}

///|
async test "query result: iter, column_count, command_tag" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_qr_meta (id SERIAL PRIMARY KEY, val TEXT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_qr_meta") : Int))

  // Check command_tag on INSERT
  let insert_result = client.query_params(
    "INSERT INTO test_qr_meta (val) VALUES ($1)",
    [@pgsql.String("a")],
  )
  assert_true(insert_result.command_tag().contains("INSERT"))

  // Insert more rows
  ignore(
    (
      client.execute_params("INSERT INTO test_qr_meta (val) VALUES ($1)", [
        @pgsql.String("b"),
      ]) : Int),
  )
  ignore(
    (
      client.execute_params("INSERT INTO test_qr_meta (val) VALUES ($1)", [
        @pgsql.String("c"),
      ]) : Int),
  )

  // Query and check column_count
  let result = client.query("SELECT id, val FROM test_qr_meta ORDER BY id")
  assert_eq(result.column_count(), 2)

  // Iterate with iter() and fold to collect values
  let vals = result
    .iter()
    .fold(init=Array::new(), fn(acc, row) {
      acc.push(row.string(1).unwrap())
      acc
    })
  assert_eq(vals.length(), 3)
  assert_eq(vals[0], "a")
  assert_eq(vals[1], "b")
  assert_eq(vals[2], "c")

  ignore((client.execute("DROP TABLE test_qr_meta") : Int))
  client.close()
}

///|
async test "bytea: binary data round-trip" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_bytea (id INT PRIMARY KEY, data BYTEA)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_bytea") : Int))

  // Create binary data with various byte values including nulls
  let binary_data = Bytes::from_array([
    b'\x00', b'\x01', b'\x02', b'\xFF', b'\xFE', b'\x80', b'\x7F', b'\x42',
  ])

  ignore(
    (
      client.execute_params(
        "INSERT INTO test_bytea (id, data) VALUES ($1, $2)",
        [@pgsql.Int(1), @pgsql.Bytes(binary_data)],
      ) : Int),
  )

  let result = client.query_params(
    "SELECT data FROM test_bytea WHERE id = $1",
    [@pgsql.Int(1)],
  )
  let row = result.row(0).unwrap()
  match row.get(0) {
    Some(@pgsql.Bytes(returned_data)) => {
      assert_eq(returned_data.length(), binary_data.length())
      for i = 0; i < binary_data.length(); i = i + 1 {
        assert_eq(returned_data[i], binary_data[i])
      }
    }
    other => fail("Expected Bytes value, got: \{other}")
  }

  ignore((client.execute("DROP TABLE test_bytea") : Int))
  client.close()
}

///|
async test "ssl mode: Prefer falls back to plain" {
  let prefer_config = @pgsql.Config::new(
    "postgres",
    "postgres",
    "postgres",
    host="127.0.0.1",
    port=5433,
    ssl_mode=Prefer,
  )
  let client = @pgsql.Client::connect(prefer_config)
  let result = client.query("SELECT 1 AS val")
  assert_eq(result.row(0).unwrap().int(0), Some(1))
  client.close()
}

///|
async test "transaction: explicit rollback" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_tx_explicit_rb (id SERIAL PRIMARY KEY, val TEXT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_tx_explicit_rb") : Int))

  // Insert a baseline row
  ignore(
    (
      client.execute_params(
        "INSERT INTO test_tx_explicit_rb (val) VALUES ($1)",
        [@pgsql.String("baseline")],
      ) : Int),
  )

  // Transaction with explicit rollback
  client.transaction(async fn(tx) {
    ignore(
      (
        tx.execute_params("INSERT INTO test_tx_explicit_rb (val) VALUES ($1)", [
          @pgsql.String("should_vanish"),
        ]) : Int),
    )
    tx.rollback()
  })

  // Only the baseline row should exist
  let result = client.query("SELECT val FROM test_tx_explicit_rb ORDER BY id")
  assert_eq(result.row_count(), 1)
  assert_eq(result.row(0).unwrap().string(0), Some("baseline"))

  ignore((client.execute("DROP TABLE test_tx_explicit_rb") : Int))
  client.close()
}

///|
async test "prepared statement: name and sql accessors" {
  let client = @pgsql.Client::connect(get_config())

  let sql = "SELECT $1::int AS val"
  let stmt = client.prepare(sql)

  // name should be non-empty (server-assigned or driver-generated)
  assert_true(stmt.name().length() > 0)

  // sql should match the original query
  assert_eq(stmt.sql(), sql)

  stmt.close()
  client.close()
}

///|
async test "large result set: 1000 rows" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (client.execute("CREATE TABLE IF NOT EXISTS test_large (id INT)") : Int),
  )
  ignore((client.execute("DELETE FROM test_large") : Int))
  ignore(
    (
      client.execute("INSERT INTO test_large SELECT generate_series(1, 1000)") :
      Int),
  )

  let stream = client.query_stream(
    "SELECT id FROM test_large ORDER BY id",
    batch_size=100,
  )

  let mut count = 0
  let mut last_id = 0
  stream.for_each(fn(row) {
    count += 1
    last_id = row.int(0).unwrap()
  })
  assert_eq(count, 1000)
  assert_eq(last_id, 1000)

  ignore((client.execute("DROP TABLE test_large") : Int))
  client.close()
}

///|
// pool: max_size enforcement is tested by pool_wbtest.mbt whitebox tests
// which can directly control semaphore state without async timeout issues.

///|
async test "numeric type: decimal precision" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_numeric (id INT PRIMARY KEY, val NUMERIC(10,4))",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_numeric") : Int))

  ignore(
    (
      client.execute(
        "INSERT INTO test_numeric (id, val) VALUES (1, '123.4567')",
      ) : Int),
  )

  let result = client.query("SELECT val FROM test_numeric WHERE id = 1")
  let row = result.row(0).unwrap()
  // NUMERIC is returned as a string representation
  let val = row.string(0)
  assert_eq(val, Some("123.4567"))

  ignore((client.execute("DROP TABLE test_numeric") : Int))
  client.close()
}

///|
async test "error details: ServerErrorInfo fields" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_err_info (id INT PRIMARY KEY)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_err_info") : Int))

  ignore(
    (
      client.execute_params("INSERT INTO test_err_info (id) VALUES ($1)", [
        @pgsql.Int(1),
      ]) : Int),
  )

  // Duplicate key violation
  let mut got_server_error = false
  ignore(
    (
      client.execute_params("INSERT INTO test_err_info (id) VALUES ($1)", [
        @pgsql.Int(1),
      ]) : Int),
  ) catch {
    @pgsql.ServerError(info) => {
      got_server_error = true
      // 23505 = unique_violation
      assert_eq(info.code, "23505")
      assert_true(info.constraint is Some(_))
      assert_true(info.detail is Some(_))
      assert_eq(info.severity, "ERROR")
    }
    _ => ()
  }
  assert_true(got_server_error)

  ignore((client.execute("DROP TABLE test_err_info") : Int))
  client.close()
}

///|
async test "nested savepoints" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_nested_sp (id SERIAL PRIMARY KEY, val TEXT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_nested_sp") : Int))

  client.transaction(async fn(tx) {
    // Insert before any savepoint
    ignore(
      (
        tx.execute_params("INSERT INTO test_nested_sp (val) VALUES ($1)", [
          @pgsql.String("outer"),
        ]) : Int),
    )

    // Outer savepoint
    tx.savepoint("sp_outer")

    ignore(
      (
        tx.execute_params("INSERT INTO test_nested_sp (val) VALUES ($1)", [
          @pgsql.String("in_outer_sp"),
        ]) : Int),
    )

    // Inner savepoint
    tx.savepoint("sp_inner")

    ignore(
      (
        tx.execute_params("INSERT INTO test_nested_sp (val) VALUES ($1)", [
          @pgsql.String("in_inner_sp"),
        ]) : Int),
    )

    // Rollback inner savepoint — "in_inner_sp" is undone
    tx.rollback_to("sp_inner")

    // Release inner savepoint
    tx.release("sp_inner")

    // Release outer savepoint — "in_outer_sp" persists
    tx.release("sp_outer")
  })

  let result = client.query("SELECT val FROM test_nested_sp ORDER BY id")
  assert_eq(result.row_count(), 2)
  assert_eq(result.row(0).unwrap().string(0), Some("outer"))
  assert_eq(result.row(1).unwrap().string(0), Some("in_outer_sp"))

  ignore((client.execute("DROP TABLE test_nested_sp") : Int))
  client.close()
}

///|
async test "stream: batch_size equals result set size" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute("CREATE TABLE IF NOT EXISTS test_stream_exact (id INT)") :
      Int),
  )
  ignore((client.execute("DELETE FROM test_stream_exact") : Int))
  ignore(
    (
      client.execute(
        "INSERT INTO test_stream_exact SELECT generate_series(1, 25)",
      ) : Int),
  )

  let stream = client.query_stream(
    "SELECT id FROM test_stream_exact ORDER BY id",
    batch_size=25,
  )

  let mut count = 0
  stream.for_each(fn(row) {
    count += 1
    ignore((row.int(0) : Int?))
  })
  assert_eq(count, 25)

  ignore((client.execute("DROP TABLE test_stream_exact") : Int))
  client.close()
}

///|
async test "empty query returns empty result" {
  let client = @pgsql.Client::connect(get_config())

  let result = client.query("")
  assert_eq(result.row_count(), 0)

  // Client remains usable
  let result2 = client.query("SELECT 1 AS val")
  assert_eq(result2.row(0).unwrap().int(0), Some(1))

  client.close()
}

///|
async test "stream: batch_size larger than result set" {
  let client = @pgsql.Client::connect(get_config())
  ignore(
    (
      client.execute(
        "CREATE TABLE IF NOT EXISTS test_stream_large_batch (id INT)",
      ) : Int),
  )
  ignore((client.execute("DELETE FROM test_stream_large_batch") : Int))
  ignore(
    (
      client.execute("INSERT INTO test_stream_large_batch VALUES (1), (2), (3)") :
      Int),
  )

  let stream = client.query_stream(
    "SELECT id FROM test_stream_large_batch ORDER BY id",
    batch_size=100,
  )

  let seen : Array[Int] = []
  stream.for_each(fn(row) { seen.push(row.int(0).unwrap()) })
  assert_eq(seen.length(), 3)
  assert_eq(seen[0], 1)
  assert_eq(seen[1], 2)
  assert_eq(seen[2], 3)

  ignore((client.execute("DROP TABLE test_stream_large_batch") : Int))
  client.close()
}

///|
async test "notification: multiple channels" {
  let listener = @pgsql.Client::connect(get_config())
  let notifier = @pgsql.Client::connect(get_config())

  listener.listen("multi_ch_a")
  listener.listen("multi_ch_b")

  // Send to both channels
  ignore((notifier.execute("NOTIFY multi_ch_a, 'msg_a'") : Int))
  ignore((notifier.execute("NOTIFY multi_ch_b, 'msg_b'") : Int))

  // Collect both notifications
  let n1 = listener.wait_for_notification()
  let n2 = listener.wait_for_notification()

  // Verify both channels received (order may vary)
  let channels = [n1.channel(), n2.channel()]
  let payloads = [n1.payload(), n2.payload()]
  assert_true(channels.contains("multi_ch_a"))
  assert_true(channels.contains("multi_ch_b"))
  assert_true(payloads.contains("msg_a"))
  assert_true(payloads.contains("msg_b"))

  listener.unlisten("multi_ch_a")
  listener.unlisten("multi_ch_b")
  listener.close()
  notifier.close()
}
