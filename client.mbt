///| High-Level PostgreSQL Client
///
/// Provides a high-level API for interacting with PostgreSQL.

///|
/// PostgreSQL client
struct Client {
  /// Underlying connection
  conn : Connection
  /// Statement counter for PreparedStatement naming
  mut stmt_counter : Int
  /// Whether the client connection has been closed
  mut closed : Bool
  /// Serializes transaction callback lifetimes across tasks.
  tx_guard : @async.Semaphore
  /// True while executing a user callback under this client's operation lock
  mut in_user_callback : Bool
  /// True while executing a Client::transaction user callback.
  mut in_transaction_callback : Bool
}

///|
/// Create a new client by connecting to PostgreSQL
pub async fn Client::connect(config : Config) -> Client {
  let conn = connect(config)
  {
    conn,
    stmt_counter: 0,
    closed: false,
    tx_guard: @async.Semaphore::new(1),
    in_user_callback: false,
    in_transaction_callback: false,
  }
}

///|
/// Guard: raises ConnectionClosedError if the client has been closed
fn Client::check_open(self : Client) -> Unit raise ConnectionClosedError {
  if self.closed {
    raise ConnectionClosedError
  }
}

///|
/// Guard: prevent re-entrant operations from callbacks running under lock.
fn Client::check_not_in_user_callback(
  self : Client,
) -> Unit raise ClientUsageError {
  raise_if_reentrant_user_callback(self.in_user_callback)
}

///|
/// Guard: prevent re-entrant client operations from transaction callbacks.
fn Client::check_not_in_transaction_callback(
  self : Client,
) -> Unit raise ClientUsageError {
  raise_if_reentrant_transaction_callback(self.in_transaction_callback)
}

///|
/// Run a callback while a boolean flag is set. Resets the flag on both
/// success and error, preventing stale flag state after exceptions.
async fn[T] Client::with_flag(
  self : Client,
  set : (Client) -> Unit,
  clear : (Client) -> Unit,
  f : async () -> T,
) -> T {
  set(self)
  let result = f() catch {
    err => {
      clear(self)
      raise err
    }
  }
  clear(self)
  result
}

///|
/// Execute user callback code while marking the client as callback-active.
async fn[T] Client::run_user_callback(self : Client, f : async () -> T) -> T {
  self.with_flag(
    fn(c) { c.in_user_callback = true },
    fn(c) { c.in_user_callback = false },
    f,
  )
}

///|
/// Execute transaction callback code while marking tx-callback-active.
async fn[T] Client::run_transaction_callback(
  self : Client,
  f : async () -> T,
) -> T {
  self.with_flag(
    fn(c) { c.in_transaction_callback = true },
    fn(c) { c.in_transaction_callback = false },
    f,
  )
}

///|
/// Run a callback while holding a semaphore, releasing on both success and error.
async fn[T] with_semaphore(sem : @async.Semaphore, f : async () -> T) -> T {
  sem.acquire()
  let result = f() catch {
    err => {
      sem.release()
      raise err
    }
  }
  sem.release()
  result
}

///|
/// Execute a protocol operation under the per-connection operation guard.
/// Ensures only one in-flight operation can touch the socket/decoder for
/// a client at a time.
async fn[T] Client::with_operation(self : Client, f : async () -> T) -> T {
  self.check_not_in_user_callback()
  self.check_not_in_transaction_callback()
  with_semaphore(self.tx_guard, async fn() {
    with_semaphore(self.conn.operation_guard, async fn() {
      if self.closed {
        raise ConnectionClosedError
      }
      f()
    })
  })
}

///|
/// Execute an operation while transaction lifetime ownership is already held.
/// This acquires only the connection operation lock and is intended for
/// Transaction methods and transaction lifecycle statements.
async fn[T] Client::with_transaction_operation(
  self : Client,
  f : async () -> T,
) -> T {
  self.check_not_in_user_callback()
  with_semaphore(self.conn.operation_guard, async fn() {
    if self.closed {
      raise ConnectionClosedError
    }
    f()
  })
}

///|
/// Execute a simple query (non-parameterized)
/// Returns query results
pub async fn Client::query(self : Client, sql : String) -> QueryResult {
  self.with_operation(async fn() { self.query_unlocked(sql) })
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
  let messages = self.bind_execute("", params, prefix=[
    Parse("", sql, []),
  ])
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
  self.with_operation(async fn() { self.prepare_unlocked(sql) })
}

///|
/// Begin a transaction
pub async fn Client::begin(self : Client) -> Unit {
  ignore((self.execute("BEGIN") : Int))
}

///|
/// Commit a transaction
pub async fn Client::commit(self : Client) -> Unit {
  ignore((self.execute("COMMIT") : Int))
}

///|
/// Rollback a transaction
pub async fn Client::rollback(self : Client) -> Unit {
  ignore((self.execute("ROLLBACK") : Int))
}

///|
/// Check if in a transaction
pub fn Client::in_transaction(self : Client) -> Bool {
  self.conn.transaction_status is (InTransaction | Failed)
}

///|
/// Transaction status
pub fn Client::transaction_status(self : Client) -> TransactionStatus {
  self.conn.transaction_status
}

///|
/// Close the client connection
pub async fn Client::close(self : Client) -> Unit {
  if self.closed {
    return
  }
  self.check_not_in_user_callback()
  self.check_not_in_transaction_callback()
  with_semaphore(self.tx_guard, async fn() {
    if self.closed {
      return
    }
    self.closed = true
    with_semaphore(self.conn.operation_guard, async fn() { self.conn.close() })
  })
}

///|
/// Server parameter
pub fn Client::server_param(self : Client, name : String) -> String? {
  self.conn.server_params.get(name)
}

///|
/// Backend process ID
pub fn Client::process_id(self : Client) -> Int {
  self.conn.process_id
}

///|
/// Backend secret key (for cancel requests)
pub fn Client::secret_key(self : Client) -> Int {
  self.conn.secret_key
}

///|
/// Request cancellation of the currently running operation.
/// Sends a PostgreSQL CancelRequest on a separate TCP connection.
pub async fn Client::cancel(self : Client) -> Unit {
  self.check_open()
  cancel_request(self.conn.config, self.conn.process_id, self.conn.secret_key)
}

///|
/// Start listening on a notification channel
pub async fn Client::listen(self : Client, channel : String) -> Unit {
  ignore((self.execute("LISTEN " + quote_identifier(channel)) : Int))
}

///|
/// Stop listening on a notification channel
pub async fn Client::unlisten(self : Client, channel : String) -> Unit {
  ignore((self.execute("UNLISTEN " + quote_identifier(channel)) : Int))
}

///|
/// Return any queued notifications and clear the queue
pub fn Client::poll_notifications(self : Client) -> Array[Notification] {
  self.conn.notification_queue.drain()
}

///|
/// Wait until a notification arrives.
/// First checks the queue, then loops on receive until one arrives.
pub async fn Client::wait_for_notification(self : Client) -> Notification {
  self.with_operation(async fn() {
    // Check queue first
    match self.conn.notification_queue.dequeue() {
      Some(notification) => return notification
      None => ()
    }
    // Loop on receive until a notification arrives
    while true {
      let messages = self.conn.receive()
      for msg in messages {
        raise_if_server_error_message(msg)
        ignore((self.conn.dispatch_backend_message(msg) : BackendDispatchResult))
      }
      match self.conn.notification_queue.dequeue() {
        Some(notification) => return notification
        None => ()
      }
    } nobreak {
      // Unreachable — loop runs until notification or error
      Notification::new("", "", 0)
    }
  })
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
  prefix? : Array[FrontendMessage] = [],
) -> Array[BackendMessage] {
  self.with_operation(async fn() {
    self.bind_execute_unlocked(stmt_name, params, prefix~)
  })
}

///|
/// Execute simple-query path assuming operation serialization is already held.
async fn Client::query_unlocked(self : Client, sql : String) -> QueryResult {
  self.conn.send(Query(sql))
  let messages = self.conn.receive_until_ready()
  check_error(messages)
  build_query_result(messages)
}

///|
/// Execute prepare path assuming operation serialization is already held.
async fn Client::prepare_unlocked(
  self : Client,
  sql : String,
) -> PreparedStatement {
  self.stmt_counter += 1
  let name = "__prep_" + self.stmt_counter.to_string()
  self.conn.send_all([Parse(name, sql, []), Sync])
  let messages = self.conn.receive_until_ready()
  check_error(messages)
  { client: self, name, sql, closed: false, tx_scoped: false }
}

///|
/// Shared bind-describe-execute-sync sequence assuming operation lock held.
async fn Client::bind_execute_unlocked(
  self : Client,
  stmt_name : String,
  params : Array[Value],
  prefix? : Array[FrontendMessage] = [],
) -> Array[BackendMessage] {
  let param_bytes = serialize_params(params)
  let msgs = Array::from_iter(prefix.iter())
  msgs.append([
    Bind("", stmt_name, [], param_bytes, []),
    Describe(TARGET_PORTAL, ""),
    Execute("", 0),
    Sync,
  ])
  self.conn.send_all(msgs)

  let messages = self.conn.receive_until_ready()
  check_error(messages)
  messages
}

// =============================================================================
// Helper Functions
// =============================================================================

///|
/// Raise ClientUsageError when entering a re-entrant callback operation.
fn raise_if_reentrant_user_callback(
  in_user_callback : Bool,
) -> Unit raise ClientUsageError {
  if in_user_callback {
    raise ClientUsageError(
      "Re-entrant operations on the same Client are not allowed inside stream/COPY callbacks",
    )
  }
}

///|
/// Raise ClientUsageError for direct Client operations inside tx callback.
fn raise_if_reentrant_transaction_callback(
  in_transaction_callback : Bool,
) -> Unit raise ClientUsageError {
  if in_transaction_callback {
    raise ClientUsageError(
      "Direct Client operations inside transaction callback are not allowed; use the Transaction handle",
    )
  }
}

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
  messages : Array[BackendMessage],
) -> QueryResult {
  let mut columns : Array[ColumnInfo] = []
  let mut col_index : Map[String, Int] = {}
  let rows : Array[Row] = []
  let mut command_tag = ""

  for msg in messages {
    match msg {
      RowDescription(f) => {
        columns = f.map(fn(fd) { column_info_from_field(fd) })
        col_index = build_column_index(columns)
      }
      DataRow(values) => {
        let typed_values = convert_row_values(values, columns)
        rows.push(Row::new(typed_values, columns, col_index))
      }
      CommandComplete(tag) => command_tag = tag
      EmptyQueryResponse => ()
      _ => ()
    }
  }

  QueryResult::new(columns, rows, command_tag)
}

///|
/// Convert raw DataRow values to typed Values
fn convert_row_values(
  raw_values : Array[Bytes?],
  columns : Array[ColumnInfo],
) -> Array[Value] {
  raw_values.mapi(fn(i, raw) {
    let type_oid = if i < columns.length() {
      columns[i].type_oid
    } else {
      OID_TEXT
    }
    parse_text_value(raw, type_oid)
  })
}

///|
/// Serialize parameter values for Bind message
fn serialize_params(params : Array[Value]) -> Array[Bytes?] {
  params.map(fn(p) { serialize_value(p) })
}

///|
/// Parse affected rows from command tag.
/// Command tags have the form "VERB N" or "INSERT oid N" where N is
/// the affected row count at the end.  We scan backwards from the
/// end to extract the trailing integer directly, avoiding intermediate
/// string splits and allocations.
fn parse_affected_rows(tag : String) -> Int {
  let bytes = @utf8.encode(tag[:])
  let len = bytes.length()
  // Find the start of the trailing number by scanning backwards
  let mut end = len
  while end > 0 && bytes[end - 1] >= b'0' && bytes[end - 1] <= b'9' {
    end -= 1
  }
  if end == len {
    return 0 // no trailing digits
  }
  let mut result = 0
  let mut multiplier = 1
  for i = len - 1; i >= end; i = i - 1 {
    result += (bytes[i].to_int() - b'0'.to_int()) * multiplier
    multiplier *= 10
  }
  result
}
