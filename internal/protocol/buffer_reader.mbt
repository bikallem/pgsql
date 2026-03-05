///| BufferReader - Utility for parsing binary PostgreSQL protocol messages

///|
/// Error raised when a read exceeds the available data in the buffer
suberror BufferUnderflow {
  BufferUnderflow(String)
}

///|
/// A reader for parsing binary data from Bytes
struct BufferReader {
  data : Bytes
  mut offset : Int
}

///|
/// Create a new BufferReader from Bytes
pub fn BufferReader::new(data : Bytes) -> BufferReader {
  { data, offset: 0 }
}

///|
/// Get remaining bytes count
pub fn BufferReader::remaining(self : BufferReader) -> Int {
  self.data.length() - self.offset
}

///|
/// Get current offset
pub fn BufferReader::position(self : BufferReader) -> Int {
  self.offset
}

///|
/// Read a single byte
pub fn BufferReader::byte(self : BufferReader) -> Byte raise BufferUnderflow {
  guard self.remaining() >= 1 else {
    raise BufferUnderflow(
      "byte: need 1 byte but only \{self.remaining()} remaining",
    )
  }
  let b = self.data[self.offset]
  self.offset += 1
  b
}

///|
/// Read a 16-bit signed integer in big-endian format
pub fn BufferReader::int16(self : BufferReader) -> Int raise BufferUnderflow {
  guard self.remaining() >= 2 else {
    raise BufferUnderflow(
      "int16: need 2 bytes but only \{self.remaining()} remaining",
    )
  }
  let b0 = self.data[self.offset].to_int()
  let b1 = self.data[self.offset + 1].to_int()
  self.offset += 2
  // Handle sign extension for negative numbers
  let value = (b0 << 8) | b1
  if value >= 0x8000 {
    value - 0x10000
  } else {
    value
  }
}

///|
/// Read a 32-bit signed integer in big-endian format
pub fn BufferReader::int32(self : BufferReader) -> Int raise BufferUnderflow {
  guard self.remaining() >= 4 else {
    raise BufferUnderflow(
      "int32: need 4 bytes but only \{self.remaining()} remaining",
    )
  }
  let b0 = self.data[self.offset].to_int()
  let b1 = self.data[self.offset + 1].to_int()
  let b2 = self.data[self.offset + 2].to_int()
  let b3 = self.data[self.offset + 3].to_int()
  self.offset += 4
  (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
}

///|
/// Read a 32-bit unsigned integer in big-endian format
pub fn BufferReader::uint32(self : BufferReader) -> UInt raise BufferUnderflow {
  guard self.remaining() >= 4 else {
    raise BufferUnderflow(
      "uint32: need 4 bytes but only \{self.remaining()} remaining",
    )
  }
  let b0 = self.data[self.offset].to_int().reinterpret_as_uint()
  let b1 = self.data[self.offset + 1].to_int().reinterpret_as_uint()
  let b2 = self.data[self.offset + 2].to_int().reinterpret_as_uint()
  let b3 = self.data[self.offset + 3].to_int().reinterpret_as_uint()
  self.offset += 4
  (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
}

///|
/// Read a null-terminated C string (ASCII)
pub fn BufferReader::cstring(
  self : BufferReader,
) -> String raise BufferUnderflow {
  let start = self.offset
  // Find the null terminator
  while self.offset < self.data.length() && self.data[self.offset] != b'\x00' {
    self.offset += 1
  }
  guard self.offset < self.data.length() else {
    raise BufferUnderflow("cstring: missing null terminator")
  }
  // Decode UTF-8 payload between start and null terminator.
  let utf8_bytes : Array[Byte] = Array::new(capacity=self.offset - start)
  for i = start; i < self.offset; i = i + 1 {
    utf8_bytes.push(self.data[i])
  }
  // Skip the null terminator
  self.offset += 1
  @utf8.decode_lossy(Bytes::from_array(utf8_bytes)[:])
}

///|
/// Read fixed number of bytes
pub fn BufferReader::bytes(
  self : BufferReader,
  len : Int,
) -> Bytes raise BufferUnderflow {
  guard len >= 0 else {
    raise BufferUnderflow("bytes: length must be non-negative")
  }
  guard self.remaining() >= len else {
    raise BufferUnderflow(
      "bytes: need \{len} bytes but only \{self.remaining()} remaining",
    )
  }
  let arr : Array[Byte] = Array::new(capacity=len)
  for i = 0; i < len; i = i + 1 {
    arr.push(self.data[self.offset + i])
  }
  self.offset += len
  Bytes::from_array(arr)
}

///|
/// Skip bytes without reading
pub fn BufferReader::skip(self : BufferReader, count : Int) -> Unit {
  self.offset += count
}
