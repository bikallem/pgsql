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
  self.check_open()
  self.conn.send(@protocol.Query(sql))

  // Loop on receive until ReadyForQuery, calling handler for CopyData
  let mut row_count = 0
  let mut command_tag = ""
  while true {
    let messages = self.conn.receive()
    for msg in messages {
      match msg {
        @protocol.CopyOutResponse(_, _) => ()
        @protocol.CopyData(data) => handler(data)
        @protocol.CopyDone => ()
        @protocol.CommandComplete(tag) => command_tag = tag
        @protocol.ReadyForQuery(status) => {
          self.conn.transaction_status = status
          row_count = parse_affected_rows(command_tag)
          return row_count
        }
        @protocol.ErrorResponse(fields) =>
          raise ServerError(ServerErrorInfo::from_fields(fields))
        _ => ()
      }
    }
  } nobreak {
    row_count
  }
}

///|
/// Execute COPY FROM STDIN, calling writer callback to send data.
/// Returns the number of rows copied.
pub async fn Client::copy_in(
  self : Client,
  sql : String,
  writer : async (CopyWriter) -> Unit,
) -> Int {
  self.check_open()
  self.conn.send(@protocol.Query(sql))

  // Wait for CopyInResponse
  let mut got_copy_in = false
  while not(got_copy_in) {
    let messages = self.conn.receive()
    for msg in messages {
      match msg {
        @protocol.CopyInResponse(_, _) => got_copy_in = true
        @protocol.ErrorResponse(fields) =>
          raise ServerError(ServerErrorInfo::from_fields(fields))
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
}
