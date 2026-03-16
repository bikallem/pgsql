///| PostgreSQL Protocol Message Decoder
///
/// Parses backend messages from Bytes received from the server.

///|
/// Header size: 1 byte type code + 4 bytes length
const HEADER_SIZE : Int = 5

///|
/// Maximum backend frame length accepted by decoder (includes length field).
/// This bounds memory usage for incomplete frames from untrusted peers.
const MAX_FRAME_LENGTH : Int = 8 * 1024 * 1024

///|
/// Compact buffered unread bytes only after enough progress to amortize copies.
const COMPACT_THRESHOLD : Int = 4096

///|
/// Decoder for PostgreSQL protocol messages
/// Handles incremental parsing of data that may arrive in chunks
priv struct Decoder {
  /// Buffer for incomplete messages
  mut buffer : Array[Byte]
  /// Start index of unread bytes inside `buffer`.
  mut start : Int
}

///|
/// Create a new Decoder
fn Decoder::new() -> Decoder {
  { buffer: [], start: 0 }
}

///|
/// Parse messages from incoming data
/// Returns all complete messages that can be parsed from the buffer
/// Incomplete messages are buffered for the next call
fn Decoder::parse(self : Decoder, data : Bytes) -> Array[BackendMessage] {
  if self.start >= self.buffer.length() {
    self.buffer.clear()
    self.start = 0
  }

  // Append new data to buffer
  for b in data {
    self.buffer.push(b)
  }

  let messages : Array[BackendMessage] = []
  let mut offset = self.start

  // Parse as many complete messages as possible
  while offset + HEADER_SIZE <= self.buffer.length() {
    // Read message type code
    let code = self.buffer[offset]

    // Read message length (big-endian 32-bit, includes itself)
    let len = (self.buffer[offset + 1].to_int() << 24) |
      (self.buffer[offset + 2].to_int() << 16) |
      (self.buffer[offset + 3].to_int() << 8) |
      self.buffer[offset + 4].to_int()

    // Validate message length (includes itself, so minimum is 4).
    if len < 4 {
      self.buffer.clear()
      self.start = 0
      return [decoder_error("Protocol frame has invalid length")]
    }
    if len > MAX_FRAME_LENGTH {
      self.buffer.clear()
      self.start = 0
      return [decoder_error("Protocol frame exceeds max length")]
    }

    let total_len = 1 + len // code + length field + payload

    // Check if we have the complete message
    if offset + total_len > self.buffer.length() {
      break
    }

    // Extract message bytes
    let msg_arr : Array[Byte] = Array::new(capacity=len - 4)
    for i in 0..<(len - 4) {
      msg_arr.push(self.buffer[offset + HEADER_SIZE + i])
    }
    let msg_bytes = Bytes::from_array(msg_arr)

    // Parse the message; malformed payloads are fatal for protocol sync.
    try {
      let msg = parse_message(code, msg_bytes)
      messages.push(msg)
    } catch {
      BufferUnderflow(msg) => {
        self.buffer.clear()
        self.start = 0
        return [decoder_error("Malformed protocol frame: " + msg)]
      }
    }

    offset += total_len
  }

  self.start = offset
  self.compact_if_needed()

  messages
}

///|
/// Compact unread bytes to the front of the buffer when worthwhile.
fn Decoder::compact_if_needed(self : Decoder) -> Unit {
  if self.start == 0 {
    return
  }
  let len = self.buffer.length()
  if self.start >= len {
    self.buffer.clear()
    self.start = 0
    return
  }
  if self.start < COMPACT_THRESHOLD || self.start * 2 < len {
    return
  }

  let compacted : Array[Byte] = Array::new(capacity=len - self.start)
  for i in self.start..<len {
    compacted.push(self.buffer[i])
  }
  self.buffer = compacted
  self.start = 0
}

///|
/// Construct an ErrorResponse for decoder-level protocol hardening failures.
fn decoder_error(message : String) -> BackendMessage {
  let fields : Map[String, String] = {}
  fields[FIELD_MESSAGE] = message
  fields[FIELD_SEVERITY] = "ERROR"
  ErrorResponse(fields)
}

// -----------------------------------------------------------------------------
// Message Parsing Functions
// -----------------------------------------------------------------------------

///|
/// Parse a single message given its type code and payload
fn parse_message(
  code : Byte,
  data : Bytes,
) -> BackendMessage raise BufferUnderflow {
  let reader = BufferReader::new(data)
  match code {
    BACKEND_AUTH => parse_authentication(reader)
    BACKEND_KEY_DATA => parse_backend_key_data(reader)
    BACKEND_PARAM_STATUS => parse_parameter_status(reader)
    BACKEND_READY => parse_ready_for_query(reader)
    BACKEND_ROW_DESC => parse_row_description(reader)
    BACKEND_DATA_ROW => parse_data_row(reader)
    BACKEND_CMD_COMPLETE => parse_command_complete(reader)
    BACKEND_ERROR => parse_error_or_notice(reader, is_error=true)
    BACKEND_NOTICE => parse_error_or_notice(reader, is_error=false)
    BACKEND_PARSE_COMPLETE => ParseComplete
    BACKEND_BIND_COMPLETE => BindComplete
    BACKEND_CLOSE_COMPLETE => CloseComplete
    BACKEND_NO_DATA => NoData
    BACKEND_EMPTY_QUERY => EmptyQueryResponse
    BACKEND_PORTAL_SUSPENDED => PortalSuspended
    BACKEND_PARAM_DESC => parse_parameter_description(reader)
    BACKEND_NOTIFICATION => parse_notification(reader)
    BACKEND_COPY_IN => parse_copy_response(reader, is_in=true)
    BACKEND_COPY_OUT => parse_copy_response(reader, is_in=false)
    BACKEND_COPY_DATA => CopyData(data)
    BACKEND_COPY_DONE => CopyDone
    BACKEND_NEGOTIATE_VERSION => parse_negotiate_protocol_version(reader)
    // Intentional: parse() returns Array[BackendMessage] so it cannot raise errors.
    // Represent unknown message types as ErrorResponse for the connection layer to handle.
    unknown_code => {
      let fields : Map[String, String] = {}
      fields[FIELD_MESSAGE] = "Unknown message type: " +
        unknown_code.to_int().to_string()
      fields[FIELD_SEVERITY] = "ERROR"
      ErrorResponse(fields)
    }
  }
}

///|
/// Parse Authentication message
fn parse_authentication(
  reader : BufferReader,
) -> BackendMessage raise BufferUnderflow {
  match reader.int32() {
    AUTH_OK => AuthenticationOk
    AUTH_CLEARTEXT => AuthenticationCleartextPassword
    AUTH_MD5 => AuthenticationMD5Password(reader.bytes(4))
    AUTH_SASL => {
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
    }
    AUTH_SASL_CONTINUE =>
      AuthenticationSASLContinue(reader.bytes(reader.remaining()))
    AUTH_SASL_FINAL => AuthenticationSASLFinal(reader.bytes(reader.remaining()))
    auth_type => {
      let fields : Map[String, String] = {}
      fields[FIELD_MESSAGE] = "Unsupported authentication type: " +
        auth_type.to_string()
      fields[FIELD_SEVERITY] = "ERROR"
      ErrorResponse(fields)
    }
  }
}

///|
/// Parse BackendKeyData message
fn parse_backend_key_data(
  reader : BufferReader,
) -> BackendMessage raise BufferUnderflow {
  let process_id = reader.int32()
  let secret_key = reader.int32()
  BackendKeyData(process_id, secret_key)
}

///|
/// Parse ParameterStatus message
fn parse_parameter_status(
  reader : BufferReader,
) -> BackendMessage raise BufferUnderflow {
  let name = reader.cstring()
  let value = reader.cstring()
  ParameterStatus(name, value)
}

///|
/// Parse ReadyForQuery message
fn parse_ready_for_query(
  reader : BufferReader,
) -> BackendMessage raise BufferUnderflow {
  let tx_byte = reader.byte()
  let status = match tx_byte {
    TX_IDLE => Idle
    TX_IN_TRANSACTION => InTransaction
    b'E' => Failed
    unknown => {
      let fields : Map[String, String] = {}
      fields[FIELD_MESSAGE] = "Unknown transaction status byte: " +
        unknown.to_int().to_string()
      fields[FIELD_SEVERITY] = "ERROR"
      return ErrorResponse(fields)
    }
  }
  ReadyForQuery(status)
}

///|
/// Parse RowDescription message
fn parse_row_description(
  reader : BufferReader,
) -> BackendMessage raise BufferUnderflow {
  let field_count = reader.int16()
  guard field_count >= 0 else {
    raise BufferUnderflow("row description has negative field count")
  }
  let fields : Array[FieldDescription] = Array::new(capacity=field_count)

  for _i in 0..<field_count {
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
fn parse_data_row(
  reader : BufferReader,
) -> BackendMessage raise BufferUnderflow {
  let column_count = reader.int16()
  guard column_count >= 0 else {
    raise BufferUnderflow("data row has negative column count")
  }
  let values : Array[Bytes?] = Array::new(capacity=column_count)

  for _i in 0..<column_count {
    let len = reader.int32()
    if len == -1 {
      values.push(None) // NULL
    } else if len < -1 {
      raise BufferUnderflow("data row has invalid negative column length")
    } else {
      values.push(Some(reader.bytes(len)))
    }
  }

  DataRow(values)
}

///|
/// Parse CommandComplete message
fn parse_command_complete(
  reader : BufferReader,
) -> BackendMessage raise BufferUnderflow {
  let tag = reader.cstring()
  CommandComplete(tag)
}

///|
/// Parse ErrorResponse or NoticeResponse message
fn parse_error_or_notice(
  reader : BufferReader,
  is_error~ : Bool,
) -> BackendMessage raise BufferUnderflow {
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
fn parse_parameter_description(
  reader : BufferReader,
) -> BackendMessage raise BufferUnderflow {
  let param_count = reader.int16()
  guard param_count >= 0 else {
    raise BufferUnderflow("parameter description has negative count")
  }
  let type_oids : Array[UInt] = Array::new(capacity=param_count)

  for _i in 0..<param_count {
    type_oids.push(reader.uint32())
  }

  ParameterDescription(type_oids)
}

///|
/// Parse NotificationResponse message
fn parse_notification(
  reader : BufferReader,
) -> BackendMessage raise BufferUnderflow {
  let process_id = reader.int32()
  let channel = reader.cstring()
  let payload = reader.cstring()
  NotificationResponse(process_id, channel, payload)
}

///|
/// Parse CopyInResponse or CopyOutResponse message
fn parse_copy_response(
  reader : BufferReader,
  is_in~ : Bool,
) -> BackendMessage raise BufferUnderflow {
  let format_byte = reader.byte()
  let overall_format = if format_byte == b'\x00' { Text } else { Binary }

  let column_count = reader.int16()
  guard column_count >= 0 else {
    raise BufferUnderflow("copy response has negative column count")
  }
  let column_formats : Array[FormatCode] = Array::new(capacity=column_count)

  for _i in 0..<column_count {
    let fmt = reader.int16()
    column_formats.push(if fmt == 0 { Text } else { Binary })
  }

  if is_in {
    CopyInResponse(overall_format, column_formats)
  } else {
    CopyOutResponse(overall_format, column_formats)
  }
}

///|
/// Parse NegotiateProtocolVersion message
fn parse_negotiate_protocol_version(
  reader : BufferReader,
) -> BackendMessage raise BufferUnderflow {
  let newest_minor = reader.int32()
  let count = reader.int32()
  guard count >= 0 else {
    raise BufferUnderflow(
      "negotiate protocol version has negative option count",
    )
  }
  let options : Array[String] = Array::new(capacity=count)
  for _i in 0..<count {
    options.push(reader.cstring())
  }
  NegotiateProtocolVersion(newest_minor, options)
}
