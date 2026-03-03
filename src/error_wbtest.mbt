///|
/// White-box tests for error Show implementations
test "Show for ConnectionClosedError" {
  let err : ConnectionClosedError = ConnectionClosedError
  inspect(err, content="ConnectionClosedError")
}

///|
test "Show for AuthError" {
  let err = AuthError("bad password")
  inspect(err, content="AuthError: bad password")
}

///|
test "Show for ServerError" {
  let info = ServerErrorInfo::from_fields(
    { "S": "ERROR", "C": "42P01", "M": "relation missing" },
  )
  let err = ServerError(info)
  inspect(err, content="ServerError: [42P01] relation missing")
}

///|
test "Show for TxError" {
  let err = TxError("already committed")
  inspect(err, content="TransactionError: already committed")
}

///|
test "Show for PreparedStmtError" {
  let err = PreparedStmtError("statement closed")
  inspect(err, content="PreparedStatementError: statement closed")
}
