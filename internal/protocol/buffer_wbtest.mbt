///|
/// Unit tests for BufferWriter and BufferReader
test "BufferWriter::add_byte" {
  let writer = BufferWriter::new()
  writer.add_byte(b'\x42') |> ignore
  let result = writer.to_bytes()
  assert_eq(result.length(), 1)
  assert_eq(result[0], b'\x42')
}

///|
test "BufferWriter::add_int16" {
  let writer = BufferWriter::new()
  writer.add_int16(0x1234) |> ignore
  let result = writer.to_bytes()
  assert_eq(result.length(), 2)
  assert_eq(result[0], b'\x12')
  assert_eq(result[1], b'\x34')
}

///|
test "BufferWriter::add_int16_negative" {
  let writer = BufferWriter::new()
  writer.add_int16(-1) |> ignore
  let result = writer.to_bytes()
  assert_eq(result.length(), 2)
  assert_eq(result[0], b'\xFF')
  assert_eq(result[1], b'\xFF')
}

///|
test "BufferWriter::add_int32" {
  let writer = BufferWriter::new()
  writer.add_int32(0x12345678) |> ignore
  let result = writer.to_bytes()
  assert_eq(result.length(), 4)
  assert_eq(result[0], b'\x12')
  assert_eq(result[1], b'\x34')
  assert_eq(result[2], b'\x56')
  assert_eq(result[3], b'\x78')
}

///|
test "BufferWriter::add_cstring" {
  let writer = BufferWriter::new()
  writer.add_cstring("hello") |> ignore
  let result = writer.to_bytes()
  assert_eq(result.length(), 6) // 5 chars + null terminator
  assert_eq(result[5], b'\x00')
}

///|
test "BufferWriter::flush" {
  let writer = BufferWriter::new()
  writer.add_cstring("Q") |> ignore
  let result = writer.flush(b'X')
  // Should be: type(1) + length(4) + "Q\0"(2) = 7 bytes
  assert_eq(result.length(), 7)
  assert_eq(result[0], b'X') // type code
  // Length = 6 (includes itself, excludes type)
  assert_eq(result[1], b'\x00')
  assert_eq(result[2], b'\x00')
  assert_eq(result[3], b'\x00')
  assert_eq(result[4], b'\x06')
}

///|
test "BufferReader::int16" {
  let data = Bytes::from_array([b'\x12', b'\x34'])
  let reader = BufferReader::new(data)
  assert_eq(reader.int16(), 0x1234)
}

///|
test "BufferReader::int16_negative" {
  let data = Bytes::from_array([b'\xFF', b'\xFF'])
  let reader = BufferReader::new(data)
  assert_eq(reader.int16(), -1)
}

///|
test "BufferReader::int32" {
  let data = Bytes::from_array([b'\x12', b'\x34', b'\x56', b'\x78'])
  let reader = BufferReader::new(data)
  assert_eq(reader.int32(), 0x12345678)
}

///|
test "BufferReader::cstring" {
  let data = Bytes::from_array([b'h', b'i', b'\x00', b'x'])
  let reader = BufferReader::new(data)
  assert_eq(reader.cstring(), "hi")
  assert_eq(reader.position(), 3)
}

///|
test "BufferReader::cstring UTF-8 payload" {
  let utf8_bytes = Bytes::from_array([
    b'n', b'a', b'i', b'v', b'e', b' ', b'c', b'a', b'f', b'e', b' ', b'\xE2', b'\x98',
    b'\x95', b' ', b'\xF0', b'\x9F', b'\x9A', b'\x80',
  ])
  let text = @utf8.decode_lossy(utf8_bytes[:])
  let arr : Array[Byte] = Array::new(capacity=utf8_bytes.length() + 1)
  for i = 0; i < utf8_bytes.length(); i = i + 1 {
    arr.push(utf8_bytes[i])
  }
  arr.push(b'\x00')

  let reader = BufferReader::new(Bytes::from_array(arr))
  assert_eq(reader.cstring(), text)
}

///|
test "BufferReader::cstring rejects unterminated string" {
  let reader = BufferReader::new(Bytes::from_array([b'h', b'i']))
  let failed = try {
    let _ = reader.cstring()
    false
  } catch {
    BufferUnderflow(msg) => msg.contains("missing null terminator")
  }
  assert_true(failed)
}

///|
test "BufferReader::bytes" {
  let data = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let reader = BufferReader::new(data)
  let result = reader.bytes(2)
  assert_eq(result.length(), 2)
  assert_eq(result[0], b'\x01')
  assert_eq(result[1], b'\x02')
  assert_eq(reader.remaining(), 2)
}

///|
test "BufferReader::bytes rejects negative length" {
  let reader = BufferReader::new(Bytes::from_array([b'\x01', b'\x02']))
  let failed = try {
    let _ = reader.bytes(-1)
    false
  } catch {
    BufferUnderflow(_) => true
  }
  assert_true(failed)
}
