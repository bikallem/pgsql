///| Prepared Statement API
///
/// Provides reusable prepared statements for prepare-once, execute-many semantics.

///|
/// A reusable prepared statement. Created via Pgsql::prepare or Transaction::prepare.
/// Must be closed when no longer needed to release server resources.
struct PreparedStatement {
  /// Reference to the client
  client : Pgsql
  /// Server-side statement name
  name : String
  /// Original SQL
  sql : String
  /// Parameter type OIDs from ParameterDescription
  param_types : Array[UInt]
  /// Whether the statement has been closed
  mut closed : Bool
  /// True when created via Transaction::prepare and bound to tx callback scope.
  mut tx_scoped : Bool
}

///|
/// Execute the prepared statement as a query with parameters, returning rows.
pub async fn PreparedStatement::query(
  self : PreparedStatement,
  params : Array[Value],
) -> QueryResult {
  guard not(self.closed) else {
    raise PreparedStmtError("PreparedStatement is closed")
  }
  guard not(self.client.closed) else {
    raise PreparedStmtError("Pgsql connection is closed")
  }

  // Transaction-scoped prepared statements execute under tx-owned operation path.
  let messages = if self.tx_scoped {
    if not(self.client.in_transaction_callback) {
      raise PreparedStmtError(
        "Transaction-scoped PreparedStatement can only be used inside its transaction callback",
      )
    }
    self.client.with_transaction_operation(async fn() {
      self.client.bind_execute_unlocked(self.name, params)
    })
  } else {
    self.client.bind_execute(self.name, params)
  }
  build_query_result(messages)
}

///|
/// Execute the prepared statement without returning rows (INSERT, UPDATE, DELETE).
/// Returns the number of affected rows.
pub async fn PreparedStatement::execute(
  self : PreparedStatement,
  params : Array[Value],
) -> Int {
  let result = self.query(params)
  parse_affected_rows(result.command_tag)
}

///|
/// Close the prepared statement, releasing server resources.
/// Idempotent — calling close on an already-closed statement is a no-op.
pub async fn PreparedStatement::close(self : PreparedStatement) -> Unit {
  guard not(self.closed) else { return }
  self.closed = true
  guard not(self.client.closed) else {
    // Pgsql already closed; server resources are already released.
    return
  }
  let close_stmt = async fn() {
    self.client.conn.send_all([Close(TARGET_STATEMENT, self.name), Sync])
    self.client.conn.drain_until_ready()
  }
  if self.tx_scoped {
    if not(self.client.in_transaction_callback) {
      raise PreparedStmtError(
        "Transaction-scoped PreparedStatement can only be closed inside its transaction callback",
      )
    }
    self.client.with_transaction_operation(close_stmt)
  } else {
    self.client.with_operation(close_stmt)
  }
}

///|
/// Check if the prepared statement has been closed.
pub fn PreparedStatement::is_closed(self : PreparedStatement) -> Bool {
  self.closed
}

///|
/// Server-side statement name.
pub fn PreparedStatement::name(self : PreparedStatement) -> String {
  self.name
}

///|
/// Original SQL string.
pub fn PreparedStatement::sql(self : PreparedStatement) -> String {
  self.sql
}

///|
/// Parameter type OIDs expected by this prepared statement.
pub fn PreparedStatement::param_types(self : PreparedStatement) -> Array[UInt] {
  self.param_types.copy()
}
