///| BufferWriter - Utility for building binary PostgreSQL protocol messages
///
/// PostgreSQL messages have the format:
/// - 1 byte: message type code (except StartupMessage)
/// - 4 bytes: message length (includes itself, excludes type code)
/// - N bytes: message payload

///|
/// A buffer for building binary messages
pub struct BufferWriter {
  data : Array[Byte]
}

///|
/// Create a new BufferWriter with optional initial capacity
pub fn BufferWriter::new(capacity? : Int = 256) -> BufferWriter {
  { data: Array::new(capacity~) }
}

///|
/// Get the current length of the buffer
pub fn BufferWriter::length(self : BufferWriter) -> Int {
  self.data.length()
}

///|
/// Add a single byte
pub fn BufferWriter::add_byte(
  self : BufferWriter,
  value : Byte,
) -> BufferWriter {
  self.data.push(value)
  self
}

///|
/// Add a 16-bit signed integer in big-endian format
pub fn BufferWriter::add_int16(
  self : BufferWriter,
  value : Int,
) -> BufferWriter {
  self.data.push(((value >> 8) & 0xFF).to_byte())
  self.data.push((value & 0xFF).to_byte())
  self
}

///|
/// Add a 32-bit signed integer in big-endian format
pub fn BufferWriter::add_int32(
  self : BufferWriter,
  value : Int,
) -> BufferWriter {
  self.data.push(((value >> 24) & 0xFF).to_byte())
  self.data.push(((value >> 16) & 0xFF).to_byte())
  self.data.push(((value >> 8) & 0xFF).to_byte())
  self.data.push((value & 0xFF).to_byte())
  self
}

///|
/// Add a null-terminated C string (UTF-8 encoded)
pub fn BufferWriter::add_cstring(
  self : BufferWriter,
  value : String,
) -> BufferWriter {
  let bytes = @utf8.encode(value[:])
  for i = 0; i < bytes.length(); i = i + 1 {
    self.data.push(bytes[i])
  }
  self.data.push(b'\x00') // null terminator
  self
}

///|
/// Add a string without null terminator (for length-prefixed strings)
pub fn BufferWriter::add_string(
  self : BufferWriter,
  value : String,
) -> BufferWriter {
  let bytes = @utf8.encode(value[:])
  for i = 0; i < bytes.length(); i = i + 1 {
    self.data.push(bytes[i])
  }
  self
}

///|
/// Add raw bytes
pub fn BufferWriter::add_bytes(
  self : BufferWriter,
  value : Bytes,
) -> BufferWriter {
  for i = 0; i < value.length(); i = i + 1 {
    self.data.push(value[i])
  }
  self
}

///|
/// Add raw bytes from a FixedArray
pub fn BufferWriter::add_fixed_array(
  self : BufferWriter,
  value : FixedArray[Byte],
) -> BufferWriter {
  for b in value {
    self.data.push(b)
  }
  self
}

///|
/// Clear the buffer for reuse
pub fn BufferWriter::clear(self : BufferWriter) -> Unit {
  self.data.clear()
}

///|
/// Convert to Bytes
pub fn BufferWriter::to_bytes(self : BufferWriter) -> Bytes {
  Bytes::from_array(self.data)
}

///|
/// Flush the buffer as a complete message with type code
/// The length field includes itself (4 bytes) but not the type code
pub fn BufferWriter::flush(self : BufferWriter, code : Byte) -> Bytes {
  let payload_len = self.data.length()
  let msg_len = payload_len + 4 // length includes itself
  let result = Array::new(capacity=payload_len + 5)

  // Add type code
  result.push(code)

  // Add length (big-endian 32-bit)
  result.push(((msg_len >> 24) & 0xFF).to_byte())
  result.push(((msg_len >> 16) & 0xFF).to_byte())
  result.push(((msg_len >> 8) & 0xFF).to_byte())
  result.push((msg_len & 0xFF).to_byte())

  // Add payload
  for b in self.data {
    result.push(b)
  }

  self.data.clear()
  Bytes::from_array(result)
}

///|
/// Flush the buffer as a startup message (no type code)
/// StartupMessage format: length (4 bytes) + protocol version + parameters
pub fn BufferWriter::flush_startup(self : BufferWriter) -> Bytes {
  let payload_len = self.data.length()
  let msg_len = payload_len + 4 // length includes itself
  let result = Array::new(capacity=payload_len + 4)

  // Add length (big-endian 32-bit) - no type code for startup
  result.push(((msg_len >> 24) & 0xFF).to_byte())
  result.push(((msg_len >> 16) & 0xFF).to_byte())
  result.push(((msg_len >> 8) & 0xFF).to_byte())
  result.push((msg_len & 0xFF).to_byte())

  // Add payload
  for b in self.data {
    result.push(b)
  }

  self.data.clear()
  Bytes::from_array(result)
}
