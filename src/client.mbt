///| High-Level PostgreSQL Client
///
/// Provides a high-level API for interacting with PostgreSQL.

///|
/// PostgreSQL client
pub struct Client {
  /// Underlying connection
  conn : Connection
  /// Statement counter for PreparedStatement naming
  mut stmt_counter : Int
  /// Whether the client connection has been closed
  mut closed : Bool
}

///|
/// Create a new client by connecting to PostgreSQL
pub async fn Client::connect(config : Config) -> Client {
  let conn = connect(config)
  { conn, stmt_counter: 0, closed: false }
}

///|
/// Execute a simple query (non-parameterized)
/// Returns query results
pub async fn Client::query(self : Client, sql : String) -> QueryResult {
  // Send Query message
  self.conn.send(@protocol.Query(sql))

  // Receive all messages until ReadyForQuery
  let messages = self.conn.receive_until_ready()

  // Check for errors
  match find_error(messages) {
    Some(err) => raise ServerError(err)
    None => ()
  }

  // Build result from messages
  build_query_result(messages)
}

///|
/// Execute a query with parameters using extended query protocol.
/// Uses the unnamed prepared statement which PostgreSQL automatically
/// replaces on each Parse, so no cleanup is needed.
pub async fn Client::query_params(
  self : Client,
  sql : String,
  params : Array[Value],
) -> QueryResult {
  // Parse + bind-execute in a single batch
  let messages = self.bind_execute(
    "",
    params,
    prefix=[@protocol.Parse("", sql, [])],
  )
  build_query_result(messages)
}

///|
/// Execute a statement without returning rows (INSERT, UPDATE, DELETE, etc.)
/// Returns the number of affected rows
pub async fn Client::execute(self : Client, sql : String) -> Int {
  let result = self.query(sql)
  parse_affected_rows(result.command_tag)
}

///|
/// Execute a parameterized statement without returning rows
pub async fn Client::execute_params(
  self : Client,
  sql : String,
  params : Array[Value],
) -> Int {
  let result = self.query_params(sql, params)
  parse_affected_rows(result.command_tag)
}

///|
/// Create a named prepared statement for reuse.
/// The statement is parsed on the server immediately.
/// Use PreparedStatement::query/execute to run it with parameters,
/// and PreparedStatement::close when done.
pub async fn Client::prepare(self : Client, sql : String) -> PreparedStatement {
  self.stmt_counter += 1
  let name = "__prep_" + self.stmt_counter.to_string()

  // Parse the statement on the server
  self.conn.send(@protocol.Parse(name, sql, []))
  self.conn.send(@protocol.Sync)

  let messages = self.conn.receive_until_ready()

  match find_error(messages) {
    Some(err) => raise ServerError(err)
    None => ()
  }

  { client: self, name, sql, closed: false }
}

///|
/// Begin a transaction
pub async fn Client::begin(self : Client) -> Unit {
  let _ = self.execute("BEGIN")
}

///|
/// Commit a transaction
pub async fn Client::commit(self : Client) -> Unit {
  let _ = self.execute("COMMIT")
}

///|
/// Rollback a transaction
pub async fn Client::rollback(self : Client) -> Unit {
  let _ = self.execute("ROLLBACK")
}

///|
/// Check if in a transaction
pub fn Client::in_transaction(self : Client) -> Bool {
  match self.conn.transaction_status {
    @protocol.InTransaction => true
    @protocol.Failed => true
    _ => false
  }
}

///|
/// Get transaction status
pub fn Client::get_transaction_status(self : Client) -> TransactionStatus {
  tx_status_from_protocol(self.conn.transaction_status)
}

///|
/// Close the client connection
pub async fn Client::close(self : Client) -> Unit {
  self.closed = true
  self.conn.close()
}

///|
/// Get server parameter
pub fn Client::get_server_param(self : Client, name : String) -> String? {
  self.conn.get_server_param(name)
}

///|
/// Get backend process ID
pub fn Client::get_process_id(self : Client) -> Int {
  self.conn.process_id
}

// =============================================================================
// Internal Helpers
// =============================================================================

///|
/// Shared bind-describe-execute-sync sequence used by query_params and
/// PreparedStatement::query. Sends Bind, Describe(Portal), Execute, and Sync
/// as a single batched write, receives all messages until ReadyForQuery,
/// checks for server errors, and returns the messages for result building.
/// The `prefix` parameter allows prepending messages (e.g. Parse) to the batch.
async fn Client::bind_execute(
  self : Client,
  stmt_name : String,
  params : Array[Value],
  prefix~ : Array[@protocol.FrontendMessage] = [],
) -> Array[@protocol.BackendMessage] {
  let param_bytes = serialize_params(params)
  let msgs : Array[@protocol.FrontendMessage] = []
  for msg in prefix {
    msgs.push(msg)
  }
  msgs.push(@protocol.Bind("", stmt_name, [], param_bytes, []))
  msgs.push(@protocol.Describe(b'P', ""))
  msgs.push(@protocol.Execute("", 0))
  msgs.push(@protocol.Sync)
  self.conn.send_all(msgs)

  let messages = self.conn.receive_until_ready()

  match find_error(messages) {
    Some(err) => raise ServerError(err)
    None => ()
  }

  messages
}

// =============================================================================
// Helper Functions
// =============================================================================

///|
/// Quote a SQL identifier with double quotes, escaping internal double quotes.
/// e.g. `my"name` becomes `"my""name"`
fn quote_identifier(name : String) -> String {
  let buf : Array[Char] = ['"']
  for c in name {
    if c == '"' {
      buf.push('"')
    }
    buf.push(c)
  }
  buf.push('"')
  String::from_array(buf)
}

///|
/// Build QueryResult from backend messages
fn build_query_result(
  messages : Array[@protocol.BackendMessage],
) -> QueryResult {
  let mut proto_fields : Array[@protocol.FieldDescription] = []
  let mut columns : Array[ColumnInfo] = []
  let rows : Array[Row] = []
  let mut command_tag = ""

  for msg in messages {
    match msg {
      @protocol.RowDescription(f) => {
        proto_fields = f
        columns = proto_fields.map(fn(fd) { column_info_from_field(fd) })
      }
      @protocol.DataRow(values) => {
        let typed_values = convert_row_values(values, proto_fields)
        rows.push(Row::new(typed_values, columns))
      }
      @protocol.CommandComplete(tag) => command_tag = tag
      @protocol.EmptyQueryResponse => ()
      _ => ()
    }
  }

  QueryResult::new(columns, rows, command_tag)
}

///|
/// Convert raw DataRow values to typed Values
fn convert_row_values(
  raw_values : Array[Bytes?],
  fields : Array[@protocol.FieldDescription],
) -> Array[Value] {
  let result : Array[Value] = []

  for i = 0; i < raw_values.length(); i = i + 1 {
    let type_oid = if i < fields.length() {
      fields[i].type_oid
    } else {
      @protocol.OID_TEXT
    }
    let proto_value = @protocol.parse_text_value(raw_values[i], type_oid)
    result.push(value_from_protocol(proto_value))
  }

  result
}

///|
/// Serialize parameter values for Bind message
fn serialize_params(params : Array[Value]) -> Array[Bytes?] {
  let result : Array[Bytes?] = []
  for param in params {
    result.push(@protocol.serialize_value(value_to_protocol(param)))
  }
  result
}

///|
/// Parse affected rows from command tag
fn parse_affected_rows(tag : String) -> Int {
  // Command tags like "INSERT 0 1", "UPDATE 5", "DELETE 3"
  // The last number is the affected rows count
  let parts = split_string(tag, ' ')
  if parts.length() > 0 {
    let last = parts[parts.length() - 1]
    parse_int_simple(last)
  } else {
    0
  }
}

///|
/// Simple string split by character
fn split_string(s : String, sep : Char) -> Array[String] {
  let result : Array[String] = []
  let current : Array[Char] = []

  for c in s {
    if c == sep {
      if current.length() > 0 {
        result.push(String::from_array(current))
        current.clear()
      }
    } else {
      current.push(c)
    }
  }

  if current.length() > 0 {
    result.push(String::from_array(current))
  }

  result
}

///|
/// Simple integer parsing
fn parse_int_simple(s : String) -> Int {
  let mut result = 0
  let mut negative = false
  let mut started = false

  for c in s {
    if c == '-' && not(started) {
      negative = true
      started = true
    } else if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - '0'.to_int())
      started = true
    }
  }

  if negative {
    -result
  } else {
    result
  }
}
