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
  let pool = Pool::new(cfg, max_size=1, acquire_timeout_ms=100)

  // First acquire is expected to fail because no server is listening.
  let first_failed = try {
    let _ = pool.acquire()
    false
  } catch {
    _ => true
  }
  assert_true(first_failed)

  // If permit leaked, this second call fails with acquire-timeout instead of
  // the underlying connect failure.
  let mut second_error = ""
  let second_failed = try {
    let _ = pool.acquire()
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
