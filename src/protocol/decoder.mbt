///| PostgreSQL Protocol Message Decoder
///
/// Parses backend messages from Bytes received from the server.

///|
/// Header size: 1 byte type code + 4 bytes length
const HEADER_SIZE : Int = 5

///|
/// Decoder for PostgreSQL protocol messages
/// Handles incremental parsing of data that may arrive in chunks
pub struct Decoder {
  /// Buffer for incomplete messages
  mut buffer : Array[Byte]
}

///|
/// Create a new Decoder
pub fn Decoder::new() -> Decoder {
  { buffer: [] }
}

///|
/// Parse messages from incoming data
/// Returns all complete messages that can be parsed from the buffer
/// Incomplete messages are buffered for the next call
pub fn Decoder::parse(self : Decoder, data : Bytes) -> Array[BackendMessage] {
  // Append new data to buffer
  for i = 0; i < data.length(); i = i + 1 {
    self.buffer.push(data[i])
  }

  let messages : Array[BackendMessage] = []
  let mut offset = 0

  // Parse as many complete messages as possible
  while offset + HEADER_SIZE <= self.buffer.length() {
    // Read message type code
    let code = self.buffer[offset]

    // Read message length (big-endian 32-bit, includes itself)
    let len = (self.buffer[offset + 1].to_int() << 24) |
      (self.buffer[offset + 2].to_int() << 16) |
      (self.buffer[offset + 3].to_int() << 8) |
      self.buffer[offset + 4].to_int()

    let total_len = 1 + len // code + length field + payload

    // Check if we have the complete message
    if offset + total_len > self.buffer.length() {
      break
    }

    // Extract message bytes
    let msg_arr : Array[Byte] = Array::new(capacity=len - 4)
    for i = 0; i < len - 4; i = i + 1 {
      msg_arr.push(self.buffer[offset + HEADER_SIZE + i])
    }
    let msg_bytes = Bytes::from_array(msg_arr)

    // Parse the message
    let msg = parse_message(code, msg_bytes)
    messages.push(msg)

    offset += total_len
  }

  // Remove processed bytes from buffer
  if offset > 0 {
    let new_buffer : Array[Byte] = []
    for i = offset; i < self.buffer.length(); i = i + 1 {
      new_buffer.push(self.buffer[i])
    }
    self.buffer = new_buffer
  }

  messages
}

///|
/// Clear the decoder buffer
pub fn Decoder::clear(self : Decoder) -> Unit {
  self.buffer.clear()
}

///|
/// Check if there is pending data in the buffer
pub fn Decoder::has_pending(self : Decoder) -> Bool {
  self.buffer.length() > 0
}

// -----------------------------------------------------------------------------
// Message Parsing Functions
// -----------------------------------------------------------------------------

///|
/// Parse a single message given its type code and payload
fn parse_message(code : Byte, data : Bytes) -> BackendMessage {
  let reader = BufferReader::new(data)

  // Use byte literals directly for comparison
  // Backend message type codes
  if code == b'R' {
    // Authentication
    parse_authentication(reader)
  } else if code == b'K' {
    // BackendKeyData
    parse_backend_key_data(reader)
  } else if code == b'S' {
    // ParameterStatus
    parse_parameter_status(reader)
  } else if code == b'Z' {
    // ReadyForQuery
    parse_ready_for_query(reader)
  } else if code == b'T' {
    // RowDescription
    parse_row_description(reader)
  } else if code == b'D' {
    // DataRow
    parse_data_row(reader)
  } else if code == b'C' {
    // CommandComplete
    parse_command_complete(reader)
  } else if code == b'E' {
    // ErrorResponse
    parse_error_or_notice(reader, is_error=true)
  } else if code == b'N' {
    // NoticeResponse
    parse_error_or_notice(reader, is_error=false)
  } else if code == b'1' {
    // ParseComplete
    ParseComplete
  } else if code == b'2' {
    // BindComplete
    BindComplete
  } else if code == b'3' {
    // CloseComplete
    CloseComplete
  } else if code == b'n' {
    // NoData
    NoData
  } else if code == b'I' {
    // EmptyQueryResponse
    EmptyQueryResponse
  } else if code == b's' {
    // PortalSuspended
    PortalSuspended
  } else if code == b't' {
    // ParameterDescription
    parse_parameter_description(reader)
  } else if code == b'A' {
    // NotificationResponse
    parse_notification(reader)
  } else if code == b'G' {
    // CopyInResponse
    parse_copy_response(reader, is_in=true)
  } else if code == b'H' {
    // CopyOutResponse
    parse_copy_response(reader, is_in=false)
  } else if code == b'd' {
    // CopyData
    CopyData(data)
  } else if code == b'c' {
    // CopyDone
    CopyDone
  } else {
    // Unknown message type - create error response
    let fields : Map[String, String] = {}
    fields["M"] = "Unknown message type: " + code.to_int().to_string()
    fields["S"] = "ERROR"
    ErrorResponse(fields)
  }
}

///|
/// Parse Authentication message
fn parse_authentication(reader : BufferReader) -> BackendMessage {
  let auth_type = reader.int32()

  if auth_type == 0 {
    AuthenticationOk
  } else if auth_type == 3 {
    AuthenticationCleartextPassword
  } else if auth_type == 5 {
    // MD5 password - read 4-byte salt
    let salt = reader.bytes(4)
    AuthenticationMD5Password(salt)
  } else if auth_type == 10 {
    // SASL - read mechanism names
    let mechanisms : Array[String] = []
    while reader.remaining() > 1 {
      let mechanism = reader.cstring()
      if mechanism.length() > 0 {
        mechanisms.push(mechanism)
      } else {
        break
      }
    }
    AuthenticationSASL(mechanisms)
  } else if auth_type == 11 {
    // SASL Continue
    let data = reader.bytes(reader.remaining())
    AuthenticationSASLContinue(data)
  } else if auth_type == 12 {
    // SASL Final
    let data = reader.bytes(reader.remaining())
    AuthenticationSASLFinal(data)
  } else {
    // Unsupported auth type
    let fields : Map[String, String] = {}
    fields["M"] = "Unsupported authentication type: " + auth_type.to_string()
    fields["S"] = "ERROR"
    ErrorResponse(fields)
  }
}

///|
/// Parse BackendKeyData message
fn parse_backend_key_data(reader : BufferReader) -> BackendMessage {
  let process_id = reader.int32()
  let secret_key = reader.int32()
  BackendKeyData(process_id, secret_key)
}

///|
/// Parse ParameterStatus message
fn parse_parameter_status(reader : BufferReader) -> BackendMessage {
  let name = reader.cstring()
  let value = reader.cstring()
  ParameterStatus(name, value)
}

///|
/// Parse ReadyForQuery message
fn parse_ready_for_query(reader : BufferReader) -> BackendMessage {
  let status_byte = reader.byte()
  let status = if status_byte == b'I' {
    Idle
  } else if status_byte == b'T' {
    InTransaction
  } else {
    Failed // 'E'
  }
  ReadyForQuery(status)
}

///|
/// Parse RowDescription message
fn parse_row_description(reader : BufferReader) -> BackendMessage {
  let field_count = reader.int16()
  let fields : Array[FieldDescription] = Array::new(capacity=field_count)

  for i = 0; i < field_count; i = i + 1 {
    let name = reader.cstring()
    let table_oid = reader.uint32()
    let column_id = reader.int16()
    let type_oid = reader.uint32()
    let type_size = reader.int16()
    let type_modifier = reader.int32()
    let format_code = reader.int16()
    let format = if format_code == 0 { Text } else { Binary }

    fields.push(
      FieldDescription::new(
        name, table_oid, column_id, type_oid, type_size, type_modifier, format,
      ),
    )
  }

  RowDescription(fields)
}

///|
/// Parse DataRow message
fn parse_data_row(reader : BufferReader) -> BackendMessage {
  let column_count = reader.int16()
  let values : Array[Bytes?] = Array::new(capacity=column_count)

  for i = 0; i < column_count; i = i + 1 {
    let len = reader.int32()
    if len == -1 {
      values.push(None) // NULL
    } else {
      values.push(Some(reader.bytes(len)))
    }
  }

  DataRow(values)
}

///|
/// Parse CommandComplete message
fn parse_command_complete(reader : BufferReader) -> BackendMessage {
  let tag = reader.cstring()
  CommandComplete(tag)
}

///|
/// Parse ErrorResponse or NoticeResponse message
fn parse_error_or_notice(
  reader : BufferReader,
  is_error~ : Bool,
) -> BackendMessage {
  let fields : Map[String, String] = {}

  while reader.remaining() > 0 {
    let field_type = reader.byte()
    if field_type == b'\x00' {
      break
    }
    let value = reader.cstring()
    // Convert single byte to string for map key
    let key = String::from_array([field_type.to_int().unsafe_to_char()])
    fields[key] = value
  }

  if is_error {
    ErrorResponse(fields)
  } else {
    NoticeResponse(fields)
  }
}

///|
/// Parse ParameterDescription message
fn parse_parameter_description(reader : BufferReader) -> BackendMessage {
  let param_count = reader.int16()
  let type_oids : Array[UInt] = Array::new(capacity=param_count)

  for i = 0; i < param_count; i = i + 1 {
    type_oids.push(reader.uint32())
  }

  ParameterDescription(type_oids)
}

///|
/// Parse NotificationResponse message
fn parse_notification(reader : BufferReader) -> BackendMessage {
  let process_id = reader.int32()
  let channel = reader.cstring()
  let payload = reader.cstring()
  NotificationResponse(process_id, channel, payload)
}

///|
/// Parse CopyInResponse or CopyOutResponse message
fn parse_copy_response(reader : BufferReader, is_in~ : Bool) -> BackendMessage {
  let format_byte = reader.byte()
  let overall_format = if format_byte == b'\x00' { Text } else { Binary }

  let column_count = reader.int16()
  let column_formats : Array[FormatCode] = Array::new(capacity=column_count)

  for i = 0; i < column_count; i = i + 1 {
    let fmt = reader.int16()
    column_formats.push(if fmt == 0 { Text } else { Binary })
  }

  if is_in {
    CopyInResponse(overall_format, column_formats)
  } else {
    CopyOutResponse(overall_format, column_formats)
  }
}
