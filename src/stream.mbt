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
  buffer : Array[Row]
  mut buffer_pos : Int
  mut exhausted : Bool
  mut closed : Bool
  auto_tx : Bool
}

///|
/// Column metadata for the stream
pub fn RowStream::fields(self : RowStream) -> Array[ColumnInfo] {
  self.fields
}

///|
/// Get the next row, or None if the stream is exhausted
pub async fn RowStream::next(self : RowStream) -> Row? {
  guard not(self.closed) else {
    raise StreamError("Stream is closed")
  }
  // Return from buffer if available
  if self.buffer_pos < self.buffer.length() {
    let row = self.buffer[self.buffer_pos]
    self.buffer_pos += 1
    return Some(row)
  }
  // If already exhausted, nothing more to fetch
  if self.exhausted {
    return None
  }
  // Fetch next batch
  self.fetch_batch()
  if self.buffer.length() == 0 {
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
  while true {
    match self.next() {
      Some(row) => f(row)
      None => break
    }
  }
  self.close()
}

///|
/// Close the stream, releasing server resources.
/// Commits the auto-transaction if one was started.
pub async fn RowStream::close(self : RowStream) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  // Always close the named statement; also close portal if not exhausted
  let msgs : Array[@protocol.FrontendMessage] = []
  if not(self.exhausted) {
    msgs.push(@protocol.Close(b'P', self.portal_name))
  }
  msgs.push(@protocol.Close(b'S', self.stmt_name))
  msgs.push(@protocol.Sync)
  self.client.conn.send_all(msgs)
  let _ = self.client.conn.receive_until_ready()
  // Commit auto-transaction if we started one
  if self.auto_tx {
    let _ = self.client.execute("COMMIT")
  }
}

///|
/// Fetch the next batch of rows from the server
async fn RowStream::fetch_batch(self : RowStream) -> Unit {
  self.buffer.clear()
  self.buffer_pos = 0
  // Send Execute with batch_size limit + Flush
  self.client.conn.send_all([
    @protocol.Execute(self.portal_name, self.batch_size),
    @protocol.Flush,
  ])
  // Read responses until we get PortalSuspended or CommandComplete
  while true {
    let messages = self.client.conn.receive()
    for msg in messages {
      match msg {
        @protocol.DataRow(values) => {
          let typed_values = convert_row_values(values, self.fields)
          self.buffer.push(Row::new(typed_values, self.fields))
        }
        @protocol.PortalSuspended =>
          // More rows available in next batch
          return
        @protocol.CommandComplete(_) => {
          // All rows have been returned — need to read until ReadyForQuery
          // by sending Sync
          self.exhausted = true
          self.client.conn.send(@protocol.Sync)
          let rfq_msgs = self.client.conn.receive_until_ready()
          match find_error(rfq_msgs) {
            Some(err) => raise ServerError(err)
            None => ()
          }
          return
        }
        @protocol.ErrorResponse(fields) =>
          raise ServerError(ServerErrorInfo::from_fields(fields))
        @protocol.NotificationResponse(pid, channel, payload) =>
          self.client.conn.notification_queue.push(
            Notification::new(channel, payload, pid),
          )
        _ => ()
      }
    }
  }
}

///|
/// Create a streaming query.
/// Uses a named portal with Execute(max_rows) for batch fetching.
/// Automatically wraps in a transaction if not already in one.
pub async fn Client::query_stream(
  self : Client,
  sql : String,
  params~ : Array[Value] = [],
  batch_size~ : Int = 100,
) -> RowStream {
  self.check_open()
  self.stmt_counter += 1
  let stmt_name = "__stream_" + self.stmt_counter.to_string()
  let portal_name = "__portal_" + self.stmt_counter.to_string()

  // Auto-start transaction if not in one (portals don't survive outside tx)
  let auto_tx = not(self.in_transaction())
  if auto_tx {
    let _ = self.execute("BEGIN")
  }

  // Parse + Bind + Describe + Execute(portal, batch_size) + Flush
  let param_bytes = serialize_params(params)
  self.conn.send_all([
    @protocol.Parse(stmt_name, sql, []),
    @protocol.Bind(portal_name, stmt_name, [], param_bytes, []),
    @protocol.Describe(b'P', portal_name),
    @protocol.Execute(portal_name, batch_size),
    @protocol.Flush,
  ])

  // Read responses: ParseComplete, BindComplete, RowDescription, then rows
  let mut columns : Array[ColumnInfo] = []
  let rows : Array[Row] = []
  let mut exhausted = false

  while true {
    let messages = self.conn.receive()
    let mut done = false
    for msg in messages {
      match msg {
        @protocol.ParseComplete | @protocol.BindComplete => ()
        @protocol.RowDescription(f) =>
          columns = f.map(fn(fd) { column_info_from_field(fd) })
        @protocol.NoData => columns = []
        @protocol.DataRow(values) => {
          let typed_values = convert_row_values(values, columns)
          rows.push(Row::new(typed_values, columns))
        }
        @protocol.PortalSuspended => {
          // First batch done, more rows available
          done = true
        }
        @protocol.CommandComplete(_) => {
          // All rows fit in first batch
          exhausted = true
          // Need to Sync to get ReadyForQuery
          self.conn.send(@protocol.Sync)
          let _ = self.conn.receive_until_ready()
          done = true
        }
        @protocol.ErrorResponse(fields) => {
          if auto_tx {
            // Rollback the auto-transaction on error
            // Send Sync first to get back to ReadyForQuery
            self.conn.send(@protocol.Sync)
            let _ = self.conn.receive_until_ready()
            let _ = self.execute("ROLLBACK")
          }
          raise ServerError(ServerErrorInfo::from_fields(fields))
        }
        @protocol.NotificationResponse(pid, channel, payload) =>
          self.conn.notification_queue.push(
            Notification::new(channel, payload, pid),
          )
        _ => ()
      }
    }
    if done {
      break
    }
  }

  {
    client: self,
    portal_name,
    stmt_name,
    batch_size,
    fields: columns,
    buffer: rows,
    buffer_pos: 0,
    exhausted,
    closed: false,
    auto_tx,
  }
}
