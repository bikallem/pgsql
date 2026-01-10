///| Unit tests for the encoder

test "encode_query" {
  let msg = Query("SELECT 1")
  let bytes = encode(msg)

  // Should be: 'Q' + length(4) + "SELECT 1\0"
  assert_eq(bytes[0], b'Q')

  // Length = 4 + 9 = 13
  assert_eq(bytes[1], b'\x00')
  assert_eq(bytes[2], b'\x00')
  assert_eq(bytes[3], b'\x00')
  assert_eq(bytes[4], b'\x0D')

  // Query text should follow
  assert_eq(bytes[5], b'S')
  assert_eq(bytes[6], b'E')
}

test "encode_sync" {
  let msg = Sync
  let bytes = encode(msg)

  assert_eq(bytes.length(), 5)
  assert_eq(bytes[0], b'S')
  assert_eq(bytes[1], b'\x00')
  assert_eq(bytes[2], b'\x00')
  assert_eq(bytes[3], b'\x00')
  assert_eq(bytes[4], b'\x04')
}

test "encode_terminate" {
  let msg = Terminate
  let bytes = encode(msg)

  assert_eq(bytes.length(), 5)
  assert_eq(bytes[0], b'X')
  assert_eq(bytes[4], b'\x04')
}

test "encode_password" {
  let msg = PasswordMessage("secret")
  let bytes = encode(msg)

  assert_eq(bytes[0], b'p')
  // Length = 4 + 7 = 11 (includes null terminator)
  assert_eq(bytes[4], b'\x0B')
}

test "encode_parse" {
  let msg = Parse("stmt1", "SELECT $1", [OID_INT4])
  let bytes = encode(msg)

  assert_eq(bytes[0], b'P')
  // Should contain: stmt1\0 + SELECT $1\0 + param_count(2) + param_type(4)
}

test "encode_execute" {
  let msg = Execute("", 0)
  let bytes = encode(msg)

  assert_eq(bytes[0], b'E')
  // Portal name "" (1 byte null) + max_rows 0 (4 bytes)
  // Length = 4 + 1 + 4 = 9
  assert_eq(bytes[4], b'\x09')
}

test "encode_describe_statement" {
  let msg = Describe(b'S', "stmt1")
  let bytes = encode(msg)

  assert_eq(bytes[0], b'D')
  assert_eq(bytes[5], b'S') // 'S' for statement
}

test "encode_describe_portal" {
  let msg = Describe(b'P', "")
  let bytes = encode(msg)

  assert_eq(bytes[0], b'D')
  assert_eq(bytes[5], b'P') // 'P' for portal
}

test "encode_startup" {
  let params : Map[String, String] = {}
  params["user"] = "postgres"
  params["database"] = "test"

  let msg = StartupMessage(params)
  let bytes = encode(msg)

  // Startup message has no type code, starts with length
  // Protocol version is at bytes 4-7
  let version = (bytes[4].to_int() << 24) |
    (bytes[5].to_int() << 16) |
    (bytes[6].to_int() << 8) |
    bytes[7].to_int()
  assert_eq(version, PROTOCOL_VERSION)
}

test "encode_bind_simple" {
  let msg = Bind("", "", [], [], [])
  let bytes = encode(msg)

  assert_eq(bytes[0], b'B')
  // Two empty cstrings (2 bytes) + format count (2) + param count (2) + result count (2) = 8
  // Length = 4 + 8 = 12
}

test "encode_bind_with_params" {
  let hello_bytes = Bytes::from_array([b'h', b'e', b'l', b'l', b'o'])
  let params : Array[Bytes?] = [Some(hello_bytes), None]
  let msg = Bind("", "", [Text, Text], params, [Text])
  let bytes = encode(msg)

  assert_eq(bytes[0], b'B')
}

test "encode_close_statement" {
  let msg = Close(b'S', "stmt1")
  let bytes = encode(msg)

  assert_eq(bytes[0], b'C')
  assert_eq(bytes[5], b'S')
}

test "encode_cancel_request" {
  let msg = CancelRequest(12345, 67890)
  let bytes = encode(msg)

  assert_eq(bytes.length(), 16)
  // Length = 16
  assert_eq(bytes[0], b'\x00')
  assert_eq(bytes[1], b'\x00')
  assert_eq(bytes[2], b'\x00')
  assert_eq(bytes[3], b'\x10')
  // Cancel code: 80877102
  assert_eq(bytes[4], b'\x04')
  assert_eq(bytes[5], b'\xD2')
  assert_eq(bytes[6], b'\x16')
  assert_eq(bytes[7], b'\x2E')
}
