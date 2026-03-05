///| COPY Protocol Support
///
/// Provides bulk data transfer using PostgreSQL's COPY protocol.

///|
/// Writer for sending data during COPY IN operations
struct CopyWriter {
  conn : Connection
}

///|
/// Write raw data chunk to the COPY stream
pub async fn CopyWriter::write(self : CopyWriter, data : Bytes) -> Unit {
  self.conn.send(@protocol.CopyData(data))
}

///|
/// Write a tab-separated row to the COPY stream
pub async fn CopyWriter::write_row(
  self : CopyWriter,
  values : Array[String],
) -> Unit {
  let buf : Array[Byte] = []
  for i, v in values {
    if i > 0 {
      buf.push(b'\t')
    }
    let bytes = @utf8.encode(v[:])
    for j = 0; j < bytes.length(); j = j + 1 {
      buf.push(bytes[j])
    }
  }
  buf.push(b'\n')
  self.conn.send(@protocol.CopyData(Bytes::from_array(buf)))
}

///|
/// Execute COPY TO STDOUT, calling handler for each data chunk.
/// Returns the number of rows copied.
pub async fn Client::copy_out(
  self : Client,
  sql : String,
  handler : async (Bytes) -> Unit,
) -> Int {
  self.with_operation(async fn() {
    self.conn.send(@protocol.Query(sql))

    // Loop on receive until ReadyForQuery, calling handler for CopyData
    let mut row_count = 0
    let mut command_tag = ""
    let mut server_error : ServerErrorInfo? = None
    let mut handler_error : String? = None
    while true {
      let messages = self.conn.receive()
      for msg in messages {
        match msg {
          @protocol.CopyOutResponse(_, _) => ()
          @protocol.CopyData(data) =>
            if handler_error is None {
              handler(data) catch {
                err => handler_error = Some(err.to_string())
              }
            }
          @protocol.CopyDone => ()
          @protocol.CommandComplete(tag) => command_tag = tag
          @protocol.ErrorResponse(fields) =>
            if server_error is None {
              server_error = Some(ServerErrorInfo::from_fields(fields))
            }
          @protocol.NotificationResponse(pid, channel, payload) =>
            self.conn.enqueue_notification(
              Notification::new(channel, payload, pid),
            )
          @protocol.ParameterStatus(name, value) =>
            self.conn.server_params[name] = value
          @protocol.ReadyForQuery(status) => {
            self.conn.transaction_status = status
            match server_error {
              Some(info) => raise ServerError(info)
              None => ()
            }
            match handler_error {
              Some(msg) => raise CopyError(msg)
              None => ()
            }
            row_count = parse_affected_rows(command_tag)
            return row_count
          }
          _ => ()
        }
      }
    } nobreak {
      row_count
    }
  })
}

///|
/// Execute COPY FROM STDIN, calling writer callback to send data.
/// Returns the number of rows copied.
pub async fn Client::copy_in(
  self : Client,
  sql : String,
  writer : async (CopyWriter) -> Unit,
) -> Int {
  self.with_operation(async fn() {
    self.conn.send(@protocol.Query(sql))

    // Wait for CopyInResponse
    let mut got_copy_in = false
    let mut startup_error : ServerErrorInfo? = None
    while not(got_copy_in) {
      let messages = self.conn.receive()
      for msg in messages {
        match msg {
          @protocol.CopyInResponse(_, _) => got_copy_in = true
          @protocol.ErrorResponse(fields) =>
            if startup_error is None {
              startup_error = Some(ServerErrorInfo::from_fields(fields))
            }
          @protocol.NotificationResponse(pid, channel, payload) =>
            self.conn.enqueue_notification(
              Notification::new(channel, payload, pid),
            )
          @protocol.ParameterStatus(name, value) =>
            self.conn.server_params[name] = value
          @protocol.ReadyForQuery(status) => {
            self.conn.transaction_status = status
            match startup_error {
              Some(info) => raise ServerError(info)
              None => raise CopyError("COPY IN was not started")
            }
          }
          _ => ()
        }
      }
    }

    // Let the caller write data
    let copy_writer = CopyWriter::{ conn: self.conn }
    writer(copy_writer) catch {
      err => {
        // On error, send CopyFail and wait for ReadyForQuery
        self.conn.send(@protocol.CopyFail(err.to_string()))
        let _ = self.conn.receive_until_ready()
        raise CopyError(err.to_string())
      }
    }

    // Send CopyDone
    self.conn.send(@protocol.CopyDone)

    // Wait for completion
    let messages = self.conn.receive_until_ready()

    check_error(messages)

    // Extract row count from CommandComplete
    let mut row_count = 0
    for msg in messages {
      match msg {
        @protocol.CommandComplete(tag) => row_count = parse_affected_rows(tag)
        _ => ()
      }
    }
    row_count
  })
}
