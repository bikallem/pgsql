///| PostgreSQL Protocol Message Encoder
///
/// Serializes FrontendMessage values to Bytes for transmission to the server.

// Protocol version 3.0 = (3 << 16) | 0 = 196608
let encoder_protocol_version : Int = 196608

// Message type codes (Frontend -> Backend)
let code_query : Byte = b'Q'
let code_parse : Byte = b'P'
let code_bind : Byte = b'B'
let code_execute : Byte = b'E'
let code_describe : Byte = b'D'
let code_close : Byte = b'C'
let code_sync : Byte = b'S'
let code_flush : Byte = b'H'
let code_terminate : Byte = b'X'
let code_password : Byte = b'p'
let code_copy_data : Byte = b'd'
let code_copy_done : Byte = b'c'
let code_copy_fail : Byte = b'f'


/// Encode a FrontendMessage to Bytes
pub fn encode(msg : FrontendMessage) -> Bytes {
  match msg {
    StartupMessage(params) => encode_startup(params)
    SSLRequest => encode_ssl_request()
    CancelRequest(pid, key) => encode_cancel_request(pid, key)
    PasswordMessage(password) => encode_password(password)
    SASLInitialResponse(mechanism, data) =>
      encode_sasl_initial_response(mechanism, data)
    SASLResponse(data) => encode_sasl_response(data)
    Query(sql) => encode_query(sql)
    Parse(name, query, type_oids) => encode_parse(name, query, type_oids)
    Bind(portal, statement, param_formats, params, result_formats) =>
      encode_bind(portal, statement, param_formats, params, result_formats)
    Describe(kind, name) => encode_describe(kind, name)
    Execute(portal, max_rows) => encode_execute(portal, max_rows)
    Close(kind, name) => encode_close(kind, name)
    Sync => encode_sync()
    Flush => encode_flush()
    CopyData(data) => encode_copy_data(data)
    CopyDone => encode_copy_done()
    CopyFail(message) => encode_copy_fail(message)
    Terminate => encode_terminate()
  }
}

// -----------------------------------------------------------------------------
// Startup Messages
// -----------------------------------------------------------------------------

/// Encode StartupMessage
/// Format: length (4) + protocol version (4) + parameters + terminator
fn encode_startup(params : Map[String, String]) -> Bytes {
  let writer = BufferWriter::new()

  // Protocol version 3.0
  writer.add_int32(encoder_protocol_version) |> ignore

  // Add parameters
  params.each(fn(key, value) {
    writer.add_cstring(key) |> ignore
    writer.add_cstring(value) |> ignore
  })

  // Null terminator for parameter list
  writer.add_byte(b'\x00') |> ignore

  writer.flush_startup()
}

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

/// Encode PasswordMessage
/// Format: 'p' + length + password (cstring)
fn encode_password(password : String) -> Bytes {
  let writer = BufferWriter::new()
  writer.add_cstring(password) |> ignore
  writer.flush(code_password)
}

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
  writer.flush(code_password)
}

/// Encode SASLResponse
fn encode_sasl_response(data : Bytes) -> Bytes {
  let writer = BufferWriter::new()
  writer.add_bytes(data) |> ignore
  writer.flush(code_password)
}

// -----------------------------------------------------------------------------
// Query Messages
// -----------------------------------------------------------------------------

/// Encode Query (simple query protocol)
/// Format: 'Q' + length + query (cstring)
fn encode_query(sql : String) -> Bytes {
  let writer = BufferWriter::new()
  writer.add_cstring(sql) |> ignore
  writer.flush(code_query)
}

// -----------------------------------------------------------------------------
// Extended Query Protocol Messages
// -----------------------------------------------------------------------------

/// Encode Parse
/// Format: 'P' + length + name (cstring) + query (cstring) + param count (int16) + param types (int32[])
fn encode_parse(
  name : String,
  query : String,
  type_oids : Array[UInt]
) -> Bytes {
  let writer = BufferWriter::new()
  writer.add_cstring(name) |> ignore
  writer.add_cstring(query) |> ignore
  writer.add_int16(type_oids.length()) |> ignore
  for oid in type_oids {
    writer.add_int32(oid.reinterpret_as_int()) |> ignore
  }
  writer.flush(code_parse)
}

/// Encode Bind
/// Format: 'B' + length + portal (cstring) + statement (cstring) +
///         param format count (int16) + param formats (int16[]) +
///         param count (int16) + params (length + bytes)[] +
///         result format count (int16) + result formats (int16[])
fn encode_bind(
  portal : String,
  statement : String,
  param_formats : Array[FormatCode],
  params : Array[Bytes?],
  result_formats : Array[FormatCode]
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

  writer.flush(code_bind)
}

/// Encode Describe
/// Format: 'D' + length + type ('S' or 'P') + name (cstring)
fn encode_describe(kind : Byte, name : String) -> Bytes {
  let writer = BufferWriter::new()
  writer.add_byte(kind) |> ignore
  writer.add_cstring(name) |> ignore
  writer.flush(code_describe)
}

/// Encode Execute
/// Format: 'E' + length + portal (cstring) + max_rows (int32)
fn encode_execute(portal : String, max_rows : Int) -> Bytes {
  let writer = BufferWriter::new()
  writer.add_cstring(portal) |> ignore
  writer.add_int32(max_rows) |> ignore
  writer.flush(code_execute)
}

/// Encode Close
/// Format: 'C' + length + type ('S' or 'P') + name (cstring)
fn encode_close(kind : Byte, name : String) -> Bytes {
  let writer = BufferWriter::new()
  writer.add_byte(kind) |> ignore
  writer.add_cstring(name) |> ignore
  writer.flush(code_close)
}

// Pre-computed constant messages for efficiency
let sync_bytes : Bytes = Bytes::from_array([code_sync, b'\x00', b'\x00', b'\x00', b'\x04'])
let flush_bytes : Bytes = Bytes::from_array([code_flush, b'\x00', b'\x00', b'\x00', b'\x04'])
let terminate_bytes : Bytes = Bytes::from_array([code_terminate, b'\x00', b'\x00', b'\x00', b'\x04'])
let copy_done_bytes : Bytes = Bytes::from_array([code_copy_done, b'\x00', b'\x00', b'\x00', b'\x04'])

/// Encode Sync
/// Format: 'S' + length (4)
fn encode_sync() -> Bytes {
  sync_bytes
}

/// Encode Flush
/// Format: 'H' + length (4)
fn encode_flush() -> Bytes {
  flush_bytes
}

/// Encode Terminate
/// Format: 'X' + length (4)
fn encode_terminate() -> Bytes {
  terminate_bytes
}

// -----------------------------------------------------------------------------
// Copy Messages
// -----------------------------------------------------------------------------

/// Encode CopyData
/// Format: 'd' + length + data
fn encode_copy_data(data : Bytes) -> Bytes {
  let writer = BufferWriter::new()
  writer.add_bytes(data) |> ignore
  writer.flush(code_copy_data)
}

/// Encode CopyDone
/// Format: 'c' + length (4)
fn encode_copy_done() -> Bytes {
  copy_done_bytes
}

/// Encode CopyFail
/// Format: 'f' + length + message (cstring)
fn encode_copy_fail(message : String) -> Bytes {
  let writer = BufferWriter::new()
  writer.add_cstring(message) |> ignore
  writer.flush(code_copy_fail)
}

// -----------------------------------------------------------------------------
// Helper Functions
// -----------------------------------------------------------------------------

/// Convert FormatCode to Int16 value
fn format_code_to_int(code : FormatCode) -> Int {
  match code {
    Text => 0
    Binary => 1
  }
}
