///| Prepared Statement API
///
/// Provides reusable prepared statements for prepare-once, execute-many semantics.

///|
/// A reusable prepared statement. Created via Client::prepare or Transaction::prepare.
/// Must be closed when no longer needed to release server resources.
struct PreparedStatement {
  /// Reference to the client
  client : Client
  /// Server-side statement name
  name : String
  /// Original SQL
  sql : String
  /// Whether the statement has been closed
  mut closed : Bool
}

///|
/// Execute the prepared statement as a query with parameters, returning rows.
pub async fn PreparedStatement::query(
  self : PreparedStatement,
  params : Array[Value],
) -> QueryResult {
  if self.closed {
    raise PreparedStmtError("PreparedStatement is closed")
  }
  if self.client.closed {
    raise PreparedStmtError("Client connection is closed")
  }

  // Delegate to shared bind-execute helper
  let messages = self.client.bind_execute(self.name, params)
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
  if self.closed {
    return
  }
  self.closed = true
  if self.client.closed {
    // Client already closed; server resources are already released.
    return
  }
  self.client.conn.send(@protocol.Close(b'S', self.name))
  self.client.conn.send(@protocol.Sync)
  let messages = self.client.conn.receive_until_ready()
  match find_error(messages) {
    Some(err) => raise ServerError(err)
    None => ()
  }
}

///|
/// Check if the prepared statement has been closed.
pub fn PreparedStatement::is_closed(self : PreparedStatement) -> Bool {
  self.closed
}

///|
/// Get the server-side statement name.
pub fn PreparedStatement::get_name(self : PreparedStatement) -> String {
  self.name
}

///|
/// Get the original SQL string.
pub fn PreparedStatement::get_sql(self : PreparedStatement) -> String {
  self.sql
}
