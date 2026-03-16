///|
/// Regression: re-entrant callback operations must fail fast before lock wait.
test "raise_if_reentrant raises usage error for user callback" {
  let mut message = ""
  let failed = try {
    raise_if_reentrant(
      true,
      "Re-entrant operations on the same Client are not allowed inside stream/COPY callbacks",
    )
    false
  } catch {
    ClientUsageError(msg) => {
      message = msg
      true
    }
  }

  assert_true(failed)
  assert_true(message.contains("Re-entrant operations"))
}

///|
test "raise_if_reentrant allows non-callback calls" {
  raise_if_reentrant(false, "should not raise")
}

///|
/// Regression: direct Client operations inside transaction callback fail fast.
test "raise_if_reentrant raises usage error for transaction callback" {
  let mut message = ""
  let failed = try {
    raise_if_reentrant(
      true,
      "Direct Client operations inside transaction callback are not allowed; use the Transaction handle",
    )
    false
  } catch {
    ClientUsageError(msg) => {
      message = msg
      true
    }
  }

  assert_true(failed)
  assert_true(message.contains("transaction callback"))
}

///|
test "raise_if_reentrant allows outside transaction callback" {
  raise_if_reentrant(false, "should not raise")
}
