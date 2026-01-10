///| BufferReader - Utility for parsing binary PostgreSQL protocol messages

///|
/// A reader for parsing binary data from Bytes
pub struct BufferReader {
  data : Bytes
  mut offset : Int
}

///|
/// Create a new BufferReader from Bytes
pub fn BufferReader::new(data : Bytes) -> BufferReader {
  { data, offset: 0 }
}

///|
/// Create an empty BufferReader
pub fn BufferReader::empty() -> BufferReader {
  { data: Bytes::new(0), offset: 0 }
}

///|
/// Get remaining bytes count
pub fn BufferReader::remaining(self : BufferReader) -> Int {
  self.data.length() - self.offset
}

///|
/// Check if there are enough bytes remaining
pub fn BufferReader::has_remaining(self : BufferReader, count : Int) -> Bool {
  self.remaining() >= count
}

///|
/// Get current offset
pub fn BufferReader::position(self : BufferReader) -> Int {
  self.offset
}

///|
/// Read a single byte
pub fn BufferReader::byte(self : BufferReader) -> Byte {
  let b = self.data[self.offset]
  self.offset += 1
  b
}

///|
/// Read a 16-bit signed integer in big-endian format
pub fn BufferReader::int16(self : BufferReader) -> Int {
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
/// Read a 16-bit unsigned integer in big-endian format
pub fn BufferReader::uint16(self : BufferReader) -> Int {
  let b0 = self.data[self.offset].to_int()
  let b1 = self.data[self.offset + 1].to_int()
  self.offset += 2
  (b0 << 8) | b1
}

///|
/// Read a 32-bit signed integer in big-endian format
pub fn BufferReader::int32(self : BufferReader) -> Int {
  let b0 = self.data[self.offset].to_int()
  let b1 = self.data[self.offset + 1].to_int()
  let b2 = self.data[self.offset + 2].to_int()
  let b3 = self.data[self.offset + 3].to_int()
  self.offset += 4
  (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
}

///|
/// Read a 32-bit unsigned integer in big-endian format
pub fn BufferReader::uint32(self : BufferReader) -> UInt {
  let b0 = self.data[self.offset].to_int().reinterpret_as_uint()
  let b1 = self.data[self.offset + 1].to_int().reinterpret_as_uint()
  let b2 = self.data[self.offset + 2].to_int().reinterpret_as_uint()
  let b3 = self.data[self.offset + 3].to_int().reinterpret_as_uint()
  self.offset += 4
  (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
}

///|
/// Read a fixed-length ASCII string (each byte becomes one character)
pub fn BufferReader::string(self : BufferReader, len : Int) -> String {
  let chars : Array[Char] = Array::new(capacity=len)
  for i = 0; i < len; i = i + 1 {
    chars.push(self.data[self.offset + i].to_int().unsafe_to_char())
  }
  self.offset += len
  String::from_array(chars)
}

///|
/// Read a null-terminated C string (ASCII/UTF-8)
pub fn BufferReader::cstring(self : BufferReader) -> String {
  let start = self.offset
  // Find the null terminator
  while self.offset < self.data.length() && self.data[self.offset] != b'\x00' {
    self.offset += 1
  }
  // Convert bytes to chars
  let chars : Array[Char] = Array::new(capacity=self.offset - start)
  for i = start; i < self.offset; i = i + 1 {
    chars.push(self.data[i].to_int().unsafe_to_char())
  }
  // Skip the null terminator
  if self.offset < self.data.length() {
    self.offset += 1
  }
  String::from_array(chars)
}

///|
/// Read fixed number of bytes
pub fn BufferReader::bytes(self : BufferReader, len : Int) -> Bytes {
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

///|
/// Peek at the next byte without consuming it
pub fn BufferReader::peek_byte(self : BufferReader) -> Byte {
  self.data[self.offset]
}
