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
  guard self.conn.copy_in_active else {
    raise CopyError("COPY writer is no longer active")
  }
  self.conn.send(CopyData(data))
}

///|
/// Write a tab-separated row to the COPY stream
pub async fn CopyWriter::write_row(
  self : CopyWriter,
  values : Array[String],
) -> Unit {
  self.write_row_nullable(values.map(fn(v) { Some(v) }))
}

///|
/// Write a tab-separated row with nullable text values.
/// None values are encoded as PostgreSQL COPY NULL marker `\\N`.
pub async fn CopyWriter::write_row_nullable(
  self : CopyWriter,
  values : Array[String?],
) -> Unit {
  guard self.conn.copy_in_active else {
    raise CopyError("COPY writer is no longer active")
  }
  let buf : Array[Byte] = []
  for i, maybe_value in values {
    if i > 0 {
      buf.push(b'\t')
    }
    match maybe_value {
      None => {
        buf.push(b'\\')
        buf.push(b'N')
      }
      Some(value) => append_copy_text_escaped(buf, value)
    }
  }
  buf.push(b'\n')
  self.conn.send(CopyData(Bytes::from_array(buf)))
}

///|
/// Execute COPY TO STDOUT, calling handler for each data chunk.
/// Returns the number of rows copied.
pub async fn Pgsql::copy_out(
  self : Pgsql,
  sql : String,
  handler : async (Bytes) -> Unit,
) -> Int {
  self.with_operation(async fn() {
    self.conn.send(Query(sql))

    // Loop on receive until ReadyForQuery, calling handler for CopyData
    let mut row_count = 0
    let mut command_tag = ""
    let mut server_error : ServerErrorInfo? = None
    let mut handler_error : CopyCallbackFailure? = None
    while true {
      let raw_messages = self.conn.receive()
      for raw in raw_messages {
        match self.conn.dispatch(raw) {
          Ready => {
            match server_error {
              Some(info) => raise ServerError(info)
              None => ()
            }
            match handler_error {
              Some(failure) => raise CopyCallbackError(failure)
              None => ()
            }
            row_count = parse_affected_rows(command_tag)
            return row_count
          }
          Consumed => ()
          Error(info) => if server_error is None { server_error = Some(info) }
          Message(qm) =>
            match qm {
              QueryMessage::CopyOutResponse => ()
              QueryMessage::CopyData(data) =>
                if handler_error is None {
                  self.run_user_callback(async fn() { handler(data) }) catch {
                    err =>
                      handler_error = Some(CopyCallbackFailure::{
                        stage: "COPY OUT handler",
                        message: err.to_string(),
                      })
                  }
                }
              QueryMessage::CopyDone => ()
              QueryMessage::CommandComplete(tag) => command_tag = tag
              qm => raise ProtocolError(unexpected_message("COPY OUT", qm))
            }
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
pub async fn Pgsql::copy_in(
  self : Pgsql,
  sql : String,
  writer : async (CopyWriter) -> Unit,
) -> Int {
  self.with_operation(async fn() {
    self.conn.copy_in_active = false
    self.conn.send(Query(sql))

    // Wait for CopyInResponse
    let mut got_copy_in = false
    let mut startup_error : ServerErrorInfo? = None
    while not(got_copy_in) {
      let raw_messages = self.conn.receive()
      for raw in raw_messages {
        match self.conn.dispatch(raw) {
          Ready =>
            match startup_error {
              Some(info) => raise ServerError(info)
              None => raise CopyError("COPY IN was not started")
            }
          Consumed => ()
          Error(info) => if startup_error is None { startup_error = Some(info) }
          Message(qm) =>
            match qm {
              QueryMessage::CopyInResponse => got_copy_in = true
              qm =>
                raise ProtocolError(unexpected_message("COPY IN startup", qm))
            }
        }
      }
    }

    self.conn.copy_in_active = true

    // Let the caller write data
    let copy_writer = CopyWriter::{ conn: self.conn }
    self.run_user_callback(async fn() { writer(copy_writer) }) catch {
      err => {
        // On error, send CopyFail and drain until ReadyForQuery.
        // The server responds with ErrorResponse which we discard since
        // we already have the real error from the callback.
        self.conn.send(CopyFail(err.to_string()))
        self.conn.drain_until_ready()
        self.conn.copy_in_active = false
        raise CopyCallbackError(CopyCallbackFailure::{
          stage: "COPY IN writer",
          message: err.to_string(),
        })
      }
    }

    let row_count = try {
      // Send CopyDone
      self.conn.send(CopyDone)

      // Wait for completion
      let messages = self.conn.receive_until_ready()
      self.conn.copy_in_active = false

      // Extract row count from CommandComplete
      let mut copied_rows = 0
      for msg in messages {
        match msg {
          CommandComplete(tag) => copied_rows = parse_affected_rows(tag)
          qm =>
            raise ProtocolError(unexpected_message("COPY IN completion", qm))
        }
      }
      copied_rows
    } catch {
      err => {
        self.conn.copy_in_active = false
        raise err
      }
    }
    row_count
  })
}

///|
/// Append PostgreSQL COPY text escaped representation for one field.
fn append_copy_text_escaped(
  buf : Array[Byte],
  value : String,
) -> Unit raise CopyError {
  let bytes = @utf8.encode(value[:])
  for b in bytes {
    match b {
      b'\\' => {
        buf.push(b'\\')
        buf.push(b'\\')
      }
      b'\t' => {
        buf.push(b'\\')
        buf.push(b't')
      }
      b'\n' => {
        buf.push(b'\\')
        buf.push(b'n')
      }
      b'\r' => {
        buf.push(b'\\')
        buf.push(b'r')
      }
      b'\x00' => raise CopyError("COPY text format does not allow NUL bytes")
      _ => buf.push(b)
    }
  }
}
