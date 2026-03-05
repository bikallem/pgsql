///|
/// PostgreSQL Protocol Message Encoder
///
/// Serializes FrontendMessage values to Bytes for transmission to the server.

///|
/// Encode a FrontendMessage to Bytes
pub fn encode(msg : FrontendMessage) -> Bytes {
  match msg {
    StartupMessage(params) => encode_startup(params)
    SSLRequest => encode_ssl_request()
    CancelRequest(pid, key) => encode_cancel_request(pid, key)
    PasswordMessage(password) => enCODE_PASSWORD(password)
    SASLInitialResponse(mechanism, data) =>
      encode_sasl_initial_response(mechanism, data)
    SASLResponse(data) => encode_sasl_response(data)
    Query(sql) => enCODE_QUERY(sql)
    Parse(name, query, type_oids) => enCODE_PARSE(name, query, type_oids)
    Bind(portal, statement, param_formats, params, result_formats) =>
      enCODE_BIND(portal, statement, param_formats, params, result_formats)
    Describe(kind, name) => enCODE_DESCRIBE(kind, name)
    Execute(portal, max_rows) => enCODE_EXECUTE(portal, max_rows)
    Close(kind, name) => enCODE_CLOSE(kind, name)
    Sync => enCODE_SYNC()
    Flush => enCODE_FLUSH()
    CopyData(data) => enCODE_COPY_DATA(data)
    CopyDone => enCODE_COPY_DONE()
    CopyFail(message) => enCODE_COPY_FAIL(message)
    Terminate => enCODE_TERMINATE()
  }
}

// -----------------------------------------------------------------------------
// Startup Messages
// -----------------------------------------------------------------------------

///|
/// Encode StartupMessage
/// Format: length (4) + protocol version (4) + parameters + terminator
fn encode_startup(params : Map[String, String]) -> Bytes {
  let writer = BufferWriter::new()

  // Protocol version 3.0
  writer.add_int32(PROTOCOL_VERSION) |> ignore

  // Add parameters
  params.each(fn(key, value) {
    writer.add_cstring(key) |> ignore
    writer.add_cstring(value) |> ignore
  })

  // Null terminator for parameter list
  writer.add_byte(b'\x00') |> ignore

  writer.flush_startup()
}

///|
/// Encode SSLRequest
/// Format: length (4) + SSL request code (4)
fn encode_ssl_request() -> Bytes {
  let result = Array::new(capacity=8)
  // Length = 8
  result.push(b'\x00')
  result.push(b'\x00')
  result.push(b'\x00')
  result.push(b'\x08')
  // SSL request code: 80877103 = (1234 << 16) | 5679
  result.push(b'\x04')
  result.push(b'\xD2')
  result.push(b'\x16')
  result.push(b'\x2F')
  Bytes::from_array(result)
}

///|
/// Encode CancelRequest
/// Format: length (4) + cancel code (4) + pid (4) + key (4)
fn encode_cancel_request(process_id : Int, secret_key : Int) -> Bytes {
  let result = Array::new(capacity=16)
  // Length = 16
  result.push(b'\x00')
  result.push(b'\x00')
  result.push(b'\x00')
  result.push(b'\x10')
  // Cancel request code: 80877102 = (1234 << 16) | 5678
  result.push(b'\x04')
  result.push(b'\xD2')
  result.push(b'\x16')
  result.push(b'\x2E')
  // Process ID
  result.push(((process_id >> 24) & 0xFF).to_byte())
  result.push(((process_id >> 16) & 0xFF).to_byte())
  result.push(((process_id >> 8) & 0xFF).to_byte())
  result.push((process_id & 0xFF).to_byte())
  // Secret key
  result.push(((secret_key >> 24) & 0xFF).to_byte())
  result.push(((secret_key >> 16) & 0xFF).to_byte())
  result.push(((secret_key >> 8) & 0xFF).to_byte())
  result.push((secret_key & 0xFF).to_byte())
  Bytes::from_array(result)
}

// -----------------------------------------------------------------------------
// Authentication Messages
// -----------------------------------------------------------------------------

///|
/// Encode PasswordMessage
/// Format: 'p' + length + password (cstring)
fn enCODE_PASSWORD(password : String) -> Bytes {
  let writer = BufferWriter::new()
  writer.add_cstring(password) |> ignore
  writer.flush(CODE_PASSWORD)
}

///|
/// Encode SASLInitialResponse
fn encode_sasl_initial_response(mechanism : String, data : Bytes) -> Bytes {
  let writer = BufferWriter::new()
  writer.add_cstring(mechanism) |> ignore
  if data.length() > 0 {
    writer.add_int32(data.length()) |> ignore
    writer.add_bytes(data) |> ignore
  } else {
    writer.add_int32(-1) |> ignore // no initial response
  }
  writer.flush(CODE_PASSWORD)
}

///|
/// Encode SASLResponse
fn encode_sasl_response(data : Bytes) -> Bytes {
  let writer = BufferWriter::new()
  writer.add_bytes(data) |> ignore
  writer.flush(CODE_PASSWORD)
}

// -----------------------------------------------------------------------------
// Query Messages
// -----------------------------------------------------------------------------

///|
/// Encode Query (simple query protocol)
/// Format: 'Q' + length + query (cstring)
fn enCODE_QUERY(sql : String) -> Bytes {
  let writer = BufferWriter::new()
  writer.add_cstring(sql) |> ignore
  writer.flush(CODE_QUERY)
}

// -----------------------------------------------------------------------------
// Extended Query Protocol Messages
// -----------------------------------------------------------------------------

///|
/// Encode Parse
/// Format: 'P' + length + name (cstring) + query (cstring) + param count (int16) + param types (int32[])
fn enCODE_PARSE(
  name : String,
  query : String,
  type_oids : Array[UInt],
) -> Bytes {
  let writer = BufferWriter::new()
  writer.add_cstring(name) |> ignore
  writer.add_cstring(query) |> ignore
  writer.add_int16(type_oids.length()) |> ignore
  for oid in type_oids {
    writer.add_int32(oid.reinterpret_as_int()) |> ignore
  }
  writer.flush(CODE_PARSE)
}

///|
/// Encode Bind
/// Format: 'B' + length + portal (cstring) + statement (cstring) +
///         param format count (int16) + param formats (int16[]) +
///         param count (int16) + params (length + bytes)[] +
///         result format count (int16) + result formats (int16[])
fn enCODE_BIND(
  portal : String,
  statement : String,
  param_formats : Array[FormatCode],
  params : Array[Bytes?],
  result_formats : Array[FormatCode],
) -> Bytes {
  let writer = BufferWriter::new()

  // Portal and statement names
  writer.add_cstring(portal) |> ignore
  writer.add_cstring(statement) |> ignore

  // Parameter format codes
  writer.add_int16(param_formats.length()) |> ignore
  for fmt in param_formats {
    writer.add_int16(format_code_to_int(fmt)) |> ignore
  }

  // Parameter values
  writer.add_int16(params.length()) |> ignore
  for param in params {
    match param {
      None => writer.add_int32(-1) |> ignore // NULL
      Some(data) => {
        writer.add_int32(data.length()) |> ignore
        writer.add_bytes(data) |> ignore
      }
    }
  }

  // Result format codes
  writer.add_int16(result_formats.length()) |> ignore
  for fmt in result_formats {
    writer.add_int16(format_code_to_int(fmt)) |> ignore
  }

  writer.flush(CODE_BIND)
}

///|
/// Encode Describe
/// Format: 'D' + length + type ('S' or 'P') + name (cstring)
fn enCODE_DESCRIBE(kind : Byte, name : String) -> Bytes {
  let writer = BufferWriter::new()
  writer.add_byte(kind) |> ignore
  writer.add_cstring(name) |> ignore
  writer.flush(CODE_DESCRIBE)
}

///|
/// Encode Execute
/// Format: 'E' + length + portal (cstring) + max_rows (int32)
fn enCODE_EXECUTE(portal : String, max_rows : Int) -> Bytes {
  let writer = BufferWriter::new()
  writer.add_cstring(portal) |> ignore
  writer.add_int32(max_rows) |> ignore
  writer.flush(CODE_EXECUTE)
}

///|
/// Encode Close
/// Format: 'C' + length + type ('S' or 'P') + name (cstring)
fn enCODE_CLOSE(kind : Byte, name : String) -> Bytes {
  let writer = BufferWriter::new()
  writer.add_byte(kind) |> ignore
  writer.add_cstring(name) |> ignore
  writer.flush(CODE_CLOSE)
}

// Pre-computed constant messages for efficiency

///|
let sync_bytes : Bytes = Bytes::from_array([
  CODE_SYNC,
  b'\x00',
  b'\x00',
  b'\x00',
  b'\x04',
])

///|
let flush_bytes : Bytes = Bytes::from_array([
  CODE_FLUSH,
  b'\x00',
  b'\x00',
  b'\x00',
  b'\x04',
])

///|
let terminate_bytes : Bytes = Bytes::from_array([
  CODE_TERMINATE,
  b'\x00',
  b'\x00',
  b'\x00',
  b'\x04',
])

///|
let copy_done_bytes : Bytes = Bytes::from_array([
  CODE_COPY_DONE,
  b'\x00',
  b'\x00',
  b'\x00',
  b'\x04',
])

///|
/// Encode Sync
/// Format: 'S' + length (4)
fn enCODE_SYNC() -> Bytes {
  sync_bytes
}

///|
/// Encode Flush
/// Format: 'H' + length (4)
fn enCODE_FLUSH() -> Bytes {
  flush_bytes
}

///|
/// Encode Terminate
/// Format: 'X' + length (4)
fn enCODE_TERMINATE() -> Bytes {
  terminate_bytes
}

// -----------------------------------------------------------------------------
// Copy Messages
// -----------------------------------------------------------------------------

///|
/// Encode CopyData
/// Format: 'd' + length + data
fn enCODE_COPY_DATA(data : Bytes) -> Bytes {
  let writer = BufferWriter::new()
  writer.add_bytes(data) |> ignore
  writer.flush(CODE_COPY_DATA)
}

///|
/// Encode CopyDone
/// Format: 'c' + length (4)
fn enCODE_COPY_DONE() -> Bytes {
  copy_done_bytes
}

///|
/// Encode CopyFail
/// Format: 'f' + length + message (cstring)
fn enCODE_COPY_FAIL(message : String) -> Bytes {
  let writer = BufferWriter::new()
  writer.add_cstring(message) |> ignore
  writer.flush(CODE_COPY_FAIL)
}

// -----------------------------------------------------------------------------
// Helper Functions
// -----------------------------------------------------------------------------

///|
/// Convert FormatCode to Int16 value
fn format_code_to_int(code : FormatCode) -> Int {
  match code {
    Text => 0
    Binary => 1
  }
}
