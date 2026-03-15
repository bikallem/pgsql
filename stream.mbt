///| Row Streaming
///
/// Memory-efficient streaming of large result sets using PostgreSQL's
/// portal suspension mechanism (Execute with max_rows).

///|
/// A streaming cursor over query results
struct RowStream {
  client : Client
  portal_name : String
  stmt_name : String
  batch_size : Int
  fields : Array[ColumnInfo]
  column_index : Map[String, Int]
  buffer : Array[Row]
  mut buffer_pos : Int
  mut exhausted : Bool
  mut closed : Bool
  auto_tx : Bool
  mut lock_held : Bool
  mut tx_guard_held : Bool
}

///|
/// Column metadata for the stream
pub fn RowStream::fields(self : RowStream) -> Array[ColumnInfo] {
  self.fields
}

///|
/// Get the next row, or None if the stream is exhausted
pub async fn RowStream::next(self : RowStream) -> Row? {
  guard not(self.closed) else { raise StreamError("Stream is closed") }
  // Return from buffer if available
  if self.buffer_pos < self.buffer.length() {
    let row = self.buffer[self.buffer_pos]
    self.buffer_pos += 1
    return Some(row)
  }
  // If already exhausted, nothing more to fetch
  if self.exhausted {
    self.close()
    return None
  }
  // Fetch next batch
  self.fetch_batch()
  if self.buffer.length() == 0 {
    self.close()
    return None
  }
  let row = self.buffer[0]
  self.buffer_pos = 1
  Some(row)
}

///|
/// Iterate over all remaining rows, then close the stream
pub async fn RowStream::for_each(
  self : RowStream,
  f : async (Row) -> Unit,
) -> Unit {
  self.for_each_inner(f) catch {
    err => {
      self.close() catch {
        _ => ()
      }
      raise err
    }
  }
  self.close()
}

///|
/// Internal helper for for_each iteration loop
async fn RowStream::for_each_inner(
  self : RowStream,
  f : async (Row) -> Unit,
) -> Unit {
  while true {
    match self.next() {
      Some(row) => self.client.run_user_callback(async fn() { f(row) })
      None => break
    }
  }
}

///|
/// Close the stream, releasing server resources.
/// Commits the auto-transaction if one was started.
pub async fn RowStream::close(self : RowStream) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  if not(self.lock_held) {
    self.client.conn.operation_guard.acquire()
    self.lock_held = true
  }
  if self.client.closed {
    self.release_locks()
    return
  }
  try {
    // Always close the named statement; also close portal if not exhausted
    let msgs : Array[FrontendMessage] = []
    if not(self.exhausted) {
      msgs.push(Close(TARGET_PORTAL, self.portal_name))
    }
    msgs.push(Close(TARGET_STATEMENT, self.stmt_name))
    msgs.push(Sync)
    self.client.conn.send_all(msgs)
    ignore((self.client.conn.receive_until_ready() : Array[QueryMessage]))
    // Commit auto-transaction while still holding operation lock so no
    // unrelated query can execute inside the stream-owned transaction.
    if self.auto_tx {
      self.client.conn.send(Query("COMMIT"))
      ignore((self.client.conn.receive_until_ready() : Array[QueryMessage]))
    }
  } catch {
    err => {
      self.release_locks()
      raise err
    }
  }
  self.release_locks()
}

///|
/// Fetch the next batch of rows from the server
async fn RowStream::fetch_batch(self : RowStream) -> Unit {
  guard self.lock_held else {
    raise StreamError("Stream operation lock not held")
  }
  try {
    self.buffer.clear()
    self.buffer_pos = 0
    // Send Execute with batch_size limit + Flush
    self.client.conn.send_all([
      Execute(self.portal_name, self.batch_size),
      Flush,
    ])
    // Read responses until we get PortalSuspended or CommandComplete
    while true {
      let raw_messages = self.client.conn.receive()
      for raw in raw_messages {
        match self.client.conn.dispatch(raw) {
          Consumed => ()
          Ready => ()
          Error(info) => {
            self.client.conn.send(Sync)
            ignore(
              (self.client.conn.receive_until_ready() : Array[QueryMessage]),
            )
            raise ServerError(info)
          }
          Message(qm) =>
            match qm {
              QueryMessage::DataRow(values) => {
                let typed_values = convert_row_values(values, self.fields)
                self.buffer.push(
                  Row::new(typed_values, self.fields, self.column_index),
                )
              }
              QueryMessage::PortalSuspended => return
              QueryMessage::CommandComplete(_) => {
                self.exhausted = true
                self.client.conn.send(Sync)
                ignore(
                  (self.client.conn.receive_until_ready() : Array[QueryMessage]),
                )
                self.client.conn.operation_guard.release()
                self.lock_held = false
                return
              }
              qm => raise ProtocolError(unexpected_message("stream fetch", qm))
            }
        }
      }
    }
  } catch {
    err => {
      if self.lock_held {
        self.client.conn.operation_guard.release()
        self.lock_held = false
      }
      self.release_tx_guard()
      raise err
    }
  }
}

///|
/// Release both the operation guard and tx_guard for this stream.
fn RowStream::release_locks(self : RowStream) -> Unit {
  if self.lock_held {
    self.client.conn.operation_guard.release()
    self.lock_held = false
  }
  self.release_tx_guard()
}

///|
/// Release client tx_guard once for this stream.
fn RowStream::release_tx_guard(self : RowStream) -> Unit {
  if self.tx_guard_held {
    self.client.tx_guard.release()
    self.tx_guard_held = false
  }
}

///|
/// Create a streaming query.
/// Uses a named portal with Execute(max_rows) for batch fetching.
/// Automatically wraps in a transaction if not already in one.
pub async fn Client::query_stream(
  self : Client,
  sql : String,
  params? : Array[Value] = [],
  batch_size? : Int = 100,
) -> RowStream {
  self.check_not_in_user_callback()
  self.check_not_in_transaction_callback()
  self.check_open()
  if batch_size <= 0 {
    raise StreamError("batch_size must be greater than 0")
  }

  self.tx_guard.acquire()
  self.conn.operation_guard.acquire()
  if self.closed {
    self.conn.operation_guard.release()
    self.tx_guard.release()
    raise ConnectionClosedError
  }
  // Auto-start transaction if not in one (portals don't survive outside tx).
  // This runs under operation lock to avoid cross-task interleaving.
  let auto_tx = not(self.in_transaction())
  if auto_tx {
    try {
      self.conn.send(Query("BEGIN"))
      ignore((self.conn.receive_until_ready() : Array[QueryMessage]))
    } catch {
      err => {
        self.conn.operation_guard.release()
        self.tx_guard.release()
        raise err
      }
    }
  }
  self.stmt_counter += 1
  let stmt_name = "__stream_" + self.stmt_counter.to_string()
  let portal_name = "__portal_" + self.stmt_counter.to_string()

  try {
    // Parse + Bind + Describe + Execute(portal, batch_size) + Flush
    let param_bytes = serialize_params(params)
    self.conn.send_all([
      Parse(stmt_name, sql, []),
      Bind(portal_name, stmt_name, [], param_bytes, []),
      Describe(TARGET_PORTAL, portal_name),
      Execute(portal_name, batch_size),
      Flush,
    ])

    // Read responses: ParseComplete, BindComplete, RowDescription, then rows
    let mut columns : Array[ColumnInfo] = []
    let mut col_index : Map[String, Int] = {}
    let rows : Array[Row] = []
    let mut exhausted = false

    while true {
      let raw_messages = self.conn.receive()
      let mut done = false
      for raw in raw_messages {
        match self.conn.dispatch(raw) {
          Consumed => ()
          Ready => ()
          Error(info) => raise ServerError(info)
          Message(qm) =>
            match qm {
              QueryMessage::ParseComplete | QueryMessage::BindComplete => ()
              QueryMessage::RowDescription(f) => {
                columns = f.map(fn(fd) { column_info_from_field(fd) })
                col_index = build_column_index(columns)
              }
              QueryMessage::NoData => columns = []
              QueryMessage::DataRow(values) => {
                let typed_values = convert_row_values(values, columns)
                rows.push(Row::new(typed_values, columns, col_index))
              }
              QueryMessage::PortalSuspended => done = true
              QueryMessage::CommandComplete(_) => {
                exhausted = true
                self.conn.send(Sync)
                ignore((self.conn.receive_until_ready() : Array[QueryMessage]))
                done = true
              }
              qm => raise ProtocolError(unexpected_message("stream setup", qm))
            }
        }
      }
      if done {
        break
      }
    }

    if exhausted {
      self.conn.operation_guard.release()
    }

    let stream = {
      client: self,
      portal_name,
      stmt_name,
      batch_size,
      fields: columns,
      column_index: col_index,
      buffer: rows,
      buffer_pos: 0,
      exhausted,
      closed: false,
      auto_tx,
      lock_held: not(exhausted),
      tx_guard_held: true,
    }
    stream
  } catch {
    err => {
      self.cleanup_failed_stream_setup(portal_name, stmt_name, auto_tx) catch {
        _ => ()
      }
      self.conn.operation_guard.release()
      self.tx_guard.release()
      raise err
    }
  }
}

///|
/// Best-effort cleanup for query_stream setup failures while operation lock is held.
async fn Client::cleanup_failed_stream_setup(
  self : Client,
  portal_name : String,
  stmt_name : String,
  auto_tx : Bool,
) -> Unit {
  if self.closed {
    return
  }
  // First force protocol sync back to ReadyForQuery if backend is in failed
  // extended-query state.
  self.conn.send(Sync) catch {
    _ => ()
  }
  ignore(
    (self.conn.receive_until_ready() catch { _ => [] } : Array[QueryMessage]),
  )

  // Then try to close portal/statement resources.
  self.conn.send_all([
    Close(TARGET_PORTAL, portal_name),
    Close(TARGET_STATEMENT, stmt_name),
    Sync,
  ]) catch {
    _ => ()
  }
  ignore(
    (self.conn.receive_until_ready() catch { _ => [] } : Array[QueryMessage]),
  )

  // Roll back auto-opened transaction if it was started.
  if auto_tx {
    self.conn.send(Query("ROLLBACK")) catch {
      _ => ()
    }
    ignore(
      (self.conn.receive_until_ready() catch { _ => [] } : Array[QueryMessage]),
    )
  }
}
