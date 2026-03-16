///|
/// Regression: failed connect during acquire must not leak semaphore permits.
async test "Pool::acquire releases permit when connect fails" {
  let cfg = Config::new(
    "user",
    "pass",
    "db",
    host="127.0.0.1",
    port=1,
    ssl_mode=Disable,
    read_timeout=50,
  )
  let pool = Pool::new(cfg, max_size=1, acquire_timeout_ms=5000)

  // First acquire is expected to fail because no server is listening.
  let first_failed = try {
    ignore((pool.acquire() : Pgsql))
    false
  } catch {
    _ => true
  }
  assert_true(first_failed)

  // If permit leaked, this second call fails with acquire-timeout instead of
  // the underlying connect failure.
  let mut second_error = ""
  let second_failed = try {
    ignore((pool.acquire() : Pgsql))
    false
  } catch {
    err => {
      second_error = err.to_string()
      true
    }
  }
  assert_true(second_failed)
  assert_true(second_error.length() > 0)
  assert_true(not(second_error.contains("Acquire timeout")))
}

///|
/// Regression: callers blocked in acquire should fail quickly when pool closes.
async test "Pool::acquire fails with PoolError when pool closes while waiting" {
  let cfg = Config::new(
    "user",
    "pass",
    "db",
    host="127.0.0.1",
    port=1,
    ssl_mode=Disable,
    read_timeout=50,
  )
  let pool = Pool::new(cfg, max_size=1, acquire_timeout_ms=2000)
  // Hold the only permit so acquire() blocks.
  pool.semaphore.acquire()

  let err_msg = @async.with_task_group(async fn(group) {
    let waiter = group.spawn(async fn() {
      try {
        ignore((pool.acquire() : Pgsql))
        "acquired"
      } catch {
        err => err.to_string()
      }
    })
    @async.sleep(20)
    pool.close()
    waiter.wait()
  })

  assert_true(err_msg.contains("Pool is closed"))
  assert_true(not(err_msg.contains("Acquire timeout")))
}

///|
/// Regression: close must not over-release semaphore when pool is already idle.
async test "Pool::close does not abort on fully idle semaphore" {
  let cfg = Config::new(
    "user",
    "pass",
    "db",
    host="127.0.0.1",
    port=1,
    ssl_mode=Disable,
    read_timeout=50,
  )
  let pool = Pool::new(cfg, max_size=1, acquire_timeout_ms=100)
  // If close over-releases, this test process aborts.
  pool.close()
}

///|
/// Regression: permit release after close should remain valid.
async test "Pool::close preserves permit accounting for later release" {
  let cfg = Config::new(
    "user",
    "pass",
    "db",
    host="127.0.0.1",
    port=1,
    ssl_mode=Disable,
    read_timeout=50,
  )
  let pool = Pool::new(cfg, max_size=1, acquire_timeout_ms=100)

  // Simulate one in-flight checked-out client by consuming the only permit.
  pool.semaphore.acquire()
  pool.close()
  // If close over-released, the pool's release-permit path aborts internally.
  pool.release_permit()
}

///|
/// Regression: close should wake multiple blocked acquires without timeouts.
async test "Pool::close wakes all blocked acquires" {
  let cfg = Config::new(
    "user",
    "pass",
    "db",
    host="127.0.0.1",
    port=1,
    ssl_mode=Disable,
    read_timeout=50,
  )
  let pool = Pool::new(cfg, max_size=1, acquire_timeout_ms=2000)
  pool.semaphore.acquire()

  let (err1, err2) = @async.with_task_group(async fn(group) {
    let waiter1 = group.spawn(async fn() {
      try {
        ignore((pool.acquire() : Pgsql))
        "acquired"
      } catch {
        err => err.to_string()
      }
    })
    let waiter2 = group.spawn(async fn() {
      try {
        ignore((pool.acquire() : Pgsql))
        "acquired"
      } catch {
        err => err.to_string()
      }
    })
    @async.sleep(20)
    pool.close()
    (waiter1.wait(), waiter2.wait())
  })

  assert_true(err1.contains("Pool is closed"))
  assert_true(err2.contains("Pool is closed"))
  assert_true(not(err1.contains("Acquire timeout")))
  assert_true(not(err2.contains("Acquire timeout")))
}
