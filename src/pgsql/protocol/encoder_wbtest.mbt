///| Unit tests for the encoder

test "encode_query" {
  let bytes = encode(Query("SELECT 1"))
  inspect(bytes[0], content="b'\\x51'") // 'Q'
  // Length = 4 + 9 = 13
  inspect(bytes[4], content="b'\\x0D'")
  inspect(bytes[5], content="b'\\x53'") // 'S'
}

test "encode_sync" {
  let bytes = encode(Sync)
  inspect(bytes.length(), content="5")
  inspect(bytes[0], content="b'\\x53'") // 'S'
  inspect(bytes[4], content="b'\\x04'")
}

test "encode_terminate" {
  let bytes = encode(Terminate)
  inspect(bytes.length(), content="5")
  inspect(bytes[0], content="b'\\x58'") // 'X'
  inspect(bytes[4], content="b'\\x04'")
}

test "encode_flush" {
  let bytes = encode(Flush)
  inspect(bytes.length(), content="5")
  inspect(bytes[0], content="b'\\x48'") // 'H'
  inspect(bytes[4], content="b'\\x04'")
}

test "encode_password" {
  let bytes = encode(PasswordMessage("secret"))
  inspect(bytes[0], content="b'\\x70'") // 'p'
  // Length = 4 + 7 = 11 (includes null terminator)
  inspect(bytes[4], content="b'\\x0B'")
}

test "encode_parse" {
  let bytes = encode(Parse("stmt1", "SELECT $1", [OID_INT4]))
  inspect(bytes[0], content="b'\\x50'") // 'P'
}

test "encode_parse_no_params" {
  let bytes = encode(Parse("", "SELECT 1", []))
  inspect(bytes[0], content="b'\\x50'") // 'P'
}

test "encode_execute" {
  let bytes = encode(Execute("", 0))
  inspect(bytes[0], content="b'\\x45'") // 'E'
  // Portal name "" (1 byte null) + max_rows 0 (4 bytes)
  // Length = 4 + 1 + 4 = 9
  inspect(bytes[4], content="b'\\x09'")
}

test "encode_execute_with_limit" {
  let bytes = encode(Execute("portal1", 100))
  inspect(bytes[0], content="b'\\x45'") // 'E'
}

test "encode_describe_statement" {
  let bytes = encode(Describe(b'S', "stmt1"))
  inspect(bytes[0], content="b'\\x44'") // 'D'
  inspect(bytes[5], content="b'\\x53'") // 'S'
}

test "encode_describe_portal" {
  let bytes = encode(Describe(b'P', ""))
  inspect(bytes[0], content="b'\\x44'") // 'D'
  inspect(bytes[5], content="b'\\x50'") // 'P'
}

test "encode_startup" {
  let params : Map[String, String] = {}
  params["user"] = "postgres"
  params["database"] = "test"
  let bytes = encode(StartupMessage(params))
  // Protocol version at bytes 4-7
  let version = (bytes[4].to_int() << 24) | (bytes[5].to_int() << 16) |
    (bytes[6].to_int() << 8) | bytes[7].to_int()
  inspect(version, content="196608")
}

test "encode_bind_simple" {
  let bytes = encode(Bind("", "", [], [], []))
  inspect(bytes[0], content="b'\\x42'") // 'B'
}

test "encode_bind_with_params" {
  let hello_bytes = Bytes::from_array([b'h', b'e', b'l', b'l', b'o'])
  let params : Array[Bytes?] = [Some(hello_bytes), None]
  let bytes = encode(Bind("", "", [Text, Text], params, [Text]))
  inspect(bytes[0], content="b'\\x42'") // 'B'
}

test "encode_close_statement" {
  let bytes = encode(Close(b'S', "stmt1"))
  inspect(bytes[0], content="b'\\x43'") // 'C'
  inspect(bytes[5], content="b'\\x53'") // 'S'
}

test "encode_close_portal" {
  let bytes = encode(Close(b'P', "portal1"))
  inspect(bytes[0], content="b'\\x43'") // 'C'
  inspect(bytes[5], content="b'\\x50'") // 'P'
}

test "encode_cancel_request" {
  let bytes = encode(CancelRequest(12345, 67890))
  inspect(bytes.length(), content="16")
  // Length = 16
  inspect(bytes[3], content="b'\\x10'")
  // Cancel code: 80877102
  inspect(bytes[4], content="b'\\x04'")
  inspect(bytes[5], content="b'\\xD2'")
  inspect(bytes[6], content="b'\\x16'")
  inspect(bytes[7], content="b'\\x2E'")
}

test "encode_ssl_request" {
  let bytes = encode(SSLRequest)
  inspect(bytes.length(), content="8")
  // Length = 8
  inspect(bytes[3], content="b'\\x08'")
  // SSL request code: 80877103
  inspect(bytes[4], content="b'\\x04'")
  inspect(bytes[5], content="b'\\xD2'")
  inspect(bytes[6], content="b'\\x16'")
  inspect(bytes[7], content="b'\\x2F'")
}

test "encode_sasl_initial_response" {
  let data = Bytes::from_array([b'n', b',', b','])
  let bytes = encode(SASLInitialResponse("SCRAM-SHA-256", data))
  inspect(bytes[0], content="b'\\x70'") // 'p'
}

test "encode_sasl_initial_response_empty" {
  let bytes = encode(SASLInitialResponse("SCRAM-SHA-256", Bytes::new(0)))
  inspect(bytes[0], content="b'\\x70'") // 'p'
}

test "encode_sasl_response" {
  let data = Bytes::from_array([b'c', b'='])
  let bytes = encode(SASLResponse(data))
  inspect(bytes[0], content="b'\\x70'") // 'p'
}

test "encode_copy_data" {
  let data = Bytes::from_array([b'1', b'\t', b'a', b'\n'])
  let bytes = encode(CopyData(data))
  inspect(bytes[0], content="b'\\x64'") // 'd'
  // Length = 4 + 4 = 8
  inspect(bytes[4], content="b'\\x08'")
}

test "encode_copy_done" {
  let bytes = encode(CopyDone)
  inspect(bytes.length(), content="5")
  inspect(bytes[0], content="b'\\x63'") // 'c'
  inspect(bytes[4], content="b'\\x04'")
}

test "encode_copy_fail" {
  let bytes = encode(CopyFail("bad data"))
  inspect(bytes[0], content="b'\\x66'") // 'f'
  // Length = 4 + 9 = 13 ("bad data\0")
  inspect(bytes[4], content="b'\\x0D'")
}
