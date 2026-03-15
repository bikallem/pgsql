///|
/// Regression: check_error raises ServerError for ErrorResponse.
test "check_error raises ServerError" {
  let fields : Map[String, String] = {}
  fields[FIELD_MESSAGE] = "decoder hardening failure"
  fields[FIELD_CODE] = "XX000"

  let mut message = ""
  let failed = try {
    check_error([QueryMessage::ErrorResponse(fields)])
    false
  } catch {
    ServerError(info) => {
      message = info.message
      true
    }
  }

  assert_true(failed)
  assert_eq(message, "decoder hardening failure")
}

///|
test "check_error ignores non-error messages" {
  check_error([QueryMessage::CommandComplete("SELECT 1")])
}

///|
/// Regression: re-entrant callback operations must fail fast before lock wait.
test "raise_if_reentrant_user_callback raises usage error" {
  let mut message = ""
  let failed = try {
    raise_if_reentrant_user_callback(true)
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
test "raise_if_reentrant_user_callback allows non-callback calls" {
  raise_if_reentrant_user_callback(false)
}

///|
/// Regression: direct Client operations inside transaction callback fail fast.
test "raise_if_reentrant_transaction_callback raises usage error" {
  let mut message = ""
  let failed = try {
    raise_if_reentrant_transaction_callback(true)
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
test "raise_if_reentrant_transaction_callback allows outside callback" {
  raise_if_reentrant_transaction_callback(false)
}
