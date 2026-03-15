///|
/// Unit tests for the encoder
test "encode_query" {
  let bytes = encode(Query("SELECT 1"))
  inspect(bytes[0], content="b'\\x51'") // 'Q'
  // Length = 4 + 9 = 13
  inspect(bytes[4], content="b'\\x0D'")
  inspect(bytes[5], content="b'\\x53'") // 'S'
}

///|
test "encode_sync" {
  let bytes = encode(Sync)
  inspect(bytes.length(), content="5")
  inspect(bytes[0], content="b'\\x53'") // 'S'
  inspect(bytes[4], content="b'\\x04'")
}

///|
test "encode_terminate" {
  let bytes = encode(Terminate)
  inspect(bytes.length(), content="5")
  inspect(bytes[0], content="b'\\x58'") // 'X'
  inspect(bytes[4], content="b'\\x04'")
}

///|
test "encode_flush" {
  let bytes = encode(Flush)
  inspect(bytes.length(), content="5")
  inspect(bytes[0], content="b'\\x48'") // 'H'
  inspect(bytes[4], content="b'\\x04'")
}

///|
test "encode_password" {
  let bytes = encode(PasswordMessage("secret"))
  inspect(bytes[0], content="b'\\x70'") // 'p'
  // Length = 4 + 7 = 11 (includes null terminator)
  inspect(bytes[4], content="b'\\x0B'")
}

///|
test "encode_parse" {
  let bytes = encode(Parse("stmt1", "SELECT $1", [OID_INT4]))
  inspect(bytes[0], content="b'\\x50'") // 'P'
}

///|
test "encode_parse_no_params" {
  let bytes = encode(Parse("", "SELECT 1", []))
  inspect(bytes[0], content="b'\\x50'") // 'P'
}

///|
test "encode_execute" {
  let bytes = encode(Execute("", 0))
  inspect(bytes[0], content="b'\\x45'") // 'E'
  // Portal name "" (1 byte null) + max_rows 0 (4 bytes)
  // Length = 4 + 1 + 4 = 9
  inspect(bytes[4], content="b'\\x09'")
}

///|
test "encode_execute_with_limit" {
  let bytes = encode(Execute("portal1", 100))
  inspect(bytes[0], content="b'\\x45'") // 'E'
}

///|
test "encode_describe_statement" {
  let bytes = encode(Describe(b'S', "stmt1"))
  inspect(bytes[0], content="b'\\x44'") // 'D'
  inspect(bytes[5], content="b'\\x53'") // 'S'
}

///|
test "encode_describe_portal" {
  let bytes = encode(Describe(b'P', ""))
  inspect(bytes[0], content="b'\\x44'") // 'D'
  inspect(bytes[5], content="b'\\x50'") // 'P'
}

///|
test "encode_startup" {
  let params : Map[String, String] = {}
  params["user"] = "postgres"
  params["database"] = "test"
  let bytes = encode(StartupMessage(params))
  // Protocol version at bytes 4-7
  let version = (bytes[4].to_int() << 24) |
    (bytes[5].to_int() << 16) |
    (bytes[6].to_int() << 8) |
    bytes[7].to_int()
  inspect(version, content="196608")
}

///|
test "encode_bind_simple" {
  let bytes = encode(Bind("", "", [], [], []))
  inspect(bytes[0], content="b'\\x42'") // 'B'
}

///|
test "encode_bind_with_params" {
  let hello_bytes = Bytes::from_array([b'h', b'e', b'l', b'l', b'o'])
  let params : Array[Bytes?] = [Some(hello_bytes), None]
  let bytes = encode(Bind("", "", [Text, Text], params, [Text]))
  inspect(bytes[0], content="b'\\x42'") // 'B'
}

///|
test "encode_close_statement" {
  let bytes = encode(Close(b'S', "stmt1"))
  inspect(bytes[0], content="b'\\x43'") // 'C'
  inspect(bytes[5], content="b'\\x53'") // 'S'
}

///|
test "encode_close_portal" {
  let bytes = encode(Close(b'P', "portal1"))
  inspect(bytes[0], content="b'\\x43'") // 'C'
  inspect(bytes[5], content="b'\\x50'") // 'P'
}

///|
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

///|
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

///|
test "encode_sasl_initial_response" {
  let data = Bytes::from_array([b'n', b',', b','])
  let bytes = encode(SASLInitialResponse("SCRAM-SHA-256", data))
  inspect(bytes[0], content="b'\\x70'") // 'p'
}

///|
test "encode_sasl_initial_response_empty" {
  let bytes = encode(SASLInitialResponse("SCRAM-SHA-256", Bytes::new(0)))
  inspect(bytes[0], content="b'\\x70'") // 'p'
}

///|
test "encode_sasl_response" {
  let data = Bytes::from_array([b'c', b'='])
  let bytes = encode(SASLResponse(data))
  inspect(bytes[0], content="b'\\x70'") // 'p'
}

///|
test "encode_copy_data" {
  let data = Bytes::from_array([b'1', b'\t', b'a', b'\n'])
  let bytes = encode(CopyData(data))
  inspect(bytes[0], content="b'\\x64'") // 'd'
  // Length = 4 + 4 = 8
  inspect(bytes[4], content="b'\\x08'")
}

///|
test "encode_copy_done" {
  let bytes = encode(CopyDone)
  inspect(bytes.length(), content="5")
  inspect(bytes[0], content="b'\\x63'") // 'c'
  inspect(bytes[4], content="b'\\x04'")
}

///|
test "encode_copy_fail" {
  let bytes = encode(CopyFail("bad data"))
  inspect(bytes[0], content="b'\\x66'") // 'f'
  // Length = 4 + 9 = 13 ("bad data\0")
  inspect(bytes[4], content="b'\\x0D'")
}

// =============================================================================
// Roundtrip / Wire Format Verification Tests
// =============================================================================

///|
test "encode_parse_multiple_oids_wire_format" {
  let bytes = encode(Parse("stmt", "SELECT $1, $2, $3", [OID_INT4, OID_TEXT, OID_BOOL]))
  // Type code 'P'
  inspect(bytes[0], content="b'\\x50'")
  // Skip past: type(1) + length(4)
  // Statement name "stmt\0" starts at byte 5
  inspect(bytes[5], content="b'\\x73'") // 's'
  inspect(bytes[6], content="b'\\x74'") // 't'
  inspect(bytes[7], content="b'\\x6D'") // 'm'
  inspect(bytes[8], content="b'\\x74'") // 't'
  inspect(bytes[9], content="b'\\x00'") // null terminator
  // Query "SELECT $1, $2, $3\0" starts at byte 10, length 17+1=18
  let query_end = 10 + 17
  inspect(bytes[query_end], content="b'\\x00'") // null terminator after query
  // Parameter count (int16) = 3
  let count_offset = query_end + 1
  inspect(bytes[count_offset], content="b'\\x00'")
  inspect(bytes[count_offset + 1], content="b'\\x03'")
  // OID_INT4 = 23 = 0x00000017
  let oid1_offset = count_offset + 2
  inspect(bytes[oid1_offset], content="b'\\x00'")
  inspect(bytes[oid1_offset + 1], content="b'\\x00'")
  inspect(bytes[oid1_offset + 2], content="b'\\x00'")
  inspect(bytes[oid1_offset + 3], content="b'\\x17'")
  // OID_TEXT = 25 = 0x00000019
  let oid2_offset = oid1_offset + 4
  inspect(bytes[oid2_offset], content="b'\\x00'")
  inspect(bytes[oid2_offset + 1], content="b'\\x00'")
  inspect(bytes[oid2_offset + 2], content="b'\\x00'")
  inspect(bytes[oid2_offset + 3], content="b'\\x19'")
  // OID_BOOL = 16 = 0x00000010
  let oid3_offset = oid2_offset + 4
  inspect(bytes[oid3_offset], content="b'\\x00'")
  inspect(bytes[oid3_offset + 1], content="b'\\x00'")
  inspect(bytes[oid3_offset + 2], content="b'\\x00'")
  inspect(bytes[oid3_offset + 3], content="b'\\x10'")
  // Total length should equal end of last OID
  inspect(bytes.length(), content=(oid3_offset + 4).to_string())
}

///|
test "encode_bind_mixed_null_and_non_null_wire_format" {
  let val1 = Bytes::from_array([b'A', b'B'])
  let val3 = Bytes::from_array([b'\x01'])
  let params : Array[Bytes?] = [Some(val1), None, Some(val3)]
  let bytes = encode(
    Bind("p1", "s1", [Text, Text, Binary], params, [Binary]),
  )
  // Type code 'B'
  inspect(bytes[0], content="b'\\x42'")
  // Portal "p1\0" starts at byte 5
  inspect(bytes[5], content="b'\\x70'") // 'p'
  inspect(bytes[6], content="b'\\x31'") // '1'
  inspect(bytes[7], content="b'\\x00'") // null
  // Statement "s1\0" at byte 8
  inspect(bytes[8], content="b'\\x73'") // 's'
  inspect(bytes[9], content="b'\\x31'") // '1'
  inspect(bytes[10], content="b'\\x00'") // null
  // Param format count (int16) = 3
  inspect(bytes[11], content="b'\\x00'")
  inspect(bytes[12], content="b'\\x03'")
  // Format codes: Text=0, Text=0, Binary=1
  inspect(bytes[13], content="b'\\x00'") // Text high
  inspect(bytes[14], content="b'\\x00'") // Text low
  inspect(bytes[15], content="b'\\x00'")
  inspect(bytes[16], content="b'\\x00'")
  inspect(bytes[17], content="b'\\x00'")
  inspect(bytes[18], content="b'\\x01'") // Binary
  // Param count (int16) = 3
  inspect(bytes[19], content="b'\\x00'")
  inspect(bytes[20], content="b'\\x03'")
  // Param 1: length=2, data=[A,B]
  inspect(bytes[21], content="b'\\x00'")
  inspect(bytes[22], content="b'\\x00'")
  inspect(bytes[23], content="b'\\x00'")
  inspect(bytes[24], content="b'\\x02'") // length 2
  inspect(bytes[25], content="b'\\x41'") // 'A'
  inspect(bytes[26], content="b'\\x42'") // 'B'
  // Param 2: NULL = -1 (0xFFFFFFFF)
  inspect(bytes[27], content="b'\\xFF'")
  inspect(bytes[28], content="b'\\xFF'")
  inspect(bytes[29], content="b'\\xFF'")
  inspect(bytes[30], content="b'\\xFF'")
  // Param 3: length=1, data=[0x01]
  inspect(bytes[31], content="b'\\x00'")
  inspect(bytes[32], content="b'\\x00'")
  inspect(bytes[33], content="b'\\x00'")
  inspect(bytes[34], content="b'\\x01'") // length 1
  inspect(bytes[35], content="b'\\x01'") // data
  // Result format count (int16) = 1
  inspect(bytes[36], content="b'\\x00'")
  inspect(bytes[37], content="b'\\x01'")
  // Result format: Binary=1
  inspect(bytes[38], content="b'\\x00'")
  inspect(bytes[39], content="b'\\x01'")
  inspect(bytes.length(), content="40")
}

///|
test "encode_execute_max_rows_zero_vs_hundred" {
  // max_rows = 0 (unlimited)
  let bytes0 = encode(Execute("", 0))
  inspect(bytes0[0], content="b'\\x45'") // 'E'
  // Portal "" -> 1 byte null terminator, then max_rows int32
  // length = 4 + 1 + 4 = 9
  inspect(bytes0[1], content="b'\\x00'")
  inspect(bytes0[2], content="b'\\x00'")
  inspect(bytes0[3], content="b'\\x00'")
  inspect(bytes0[4], content="b'\\x09'")
  inspect(bytes0[5], content="b'\\x00'") // portal null
  // max_rows = 0 = 0x00000000
  inspect(bytes0[6], content="b'\\x00'")
  inspect(bytes0[7], content="b'\\x00'")
  inspect(bytes0[8], content="b'\\x00'")
  inspect(bytes0[9], content="b'\\x00'")

  // max_rows = 100 = 0x00000064
  let bytes100 = encode(Execute("", 100))
  inspect(bytes100[6], content="b'\\x00'")
  inspect(bytes100[7], content="b'\\x00'")
  inspect(bytes100[8], content="b'\\x00'")
  inspect(bytes100[9], content="b'\\x64'")
}

///|
test "encode_startup_multiple_params_wire_format" {
  let params : Map[String, String] = {}
  params["user"] = "pg"
  params["database"] = "db"
  params["application_name"] = "test"
  let bytes = encode(StartupMessage(params))
  // No type code for startup messages; first 4 bytes are length
  // Protocol version at bytes 4-7 = 196608 = 0x00030000
  inspect(bytes[4], content="b'\\x00'")
  inspect(bytes[5], content="b'\\x03'")
  inspect(bytes[6], content="b'\\x00'")
  inspect(bytes[7], content="b'\\x00'")
  // The last byte should be the double-null terminator (end of params)
  inspect(bytes[bytes.length() - 1], content="b'\\x00'")
  // Read total length from header
  let total_len = (bytes[0].to_int() << 24) |
    (bytes[1].to_int() << 16) |
    (bytes[2].to_int() << 8) |
    bytes[3].to_int()
  assert_eq(total_len, bytes.length())
}

// =============================================================================
// Edge Case Tests
// =============================================================================

///|
test "encode_parse_empty_name_and_query" {
  let bytes = encode(Parse("", "", []))
  inspect(bytes[0], content="b'\\x50'") // 'P'
  // Empty name: just null terminator at byte 5
  inspect(bytes[5], content="b'\\x00'")
  // Empty query: just null terminator at byte 6
  inspect(bytes[6], content="b'\\x00'")
  // Param count = 0 (int16)
  inspect(bytes[7], content="b'\\x00'")
  inspect(bytes[8], content="b'\\x00'")
  // Total: type(1) + length(4) + name_null(1) + query_null(1) + count(2) = 9
  inspect(bytes.length(), content="9")
  // Length field = 4 + 1 + 1 + 2 = 8
  inspect(bytes[1], content="b'\\x00'")
  inspect(bytes[2], content="b'\\x00'")
  inspect(bytes[3], content="b'\\x00'")
  inspect(bytes[4], content="b'\\x08'")
}

///|
test "encode_bind_all_null_params" {
  let params : Array[Bytes?] = [None, None, None]
  let bytes = encode(Bind("", "", [Text, Text, Text], params, []))
  inspect(bytes[0], content="b'\\x42'") // 'B'
  // Portal "" null at byte 5
  inspect(bytes[5], content="b'\\x00'")
  // Statement "" null at byte 6
  inspect(bytes[6], content="b'\\x00'")
  // Format count = 3 at bytes 7-8
  inspect(bytes[7], content="b'\\x00'")
  inspect(bytes[8], content="b'\\x03'")
  // Three Text format codes (0,0,0) = 6 bytes at 9-14
  // Param count = 3 at bytes 15-16
  inspect(bytes[15], content="b'\\x00'")
  inspect(bytes[16], content="b'\\x03'")
  // All three params are NULL: -1 (0xFFFFFFFF) each
  // Param 1 NULL
  inspect(bytes[17], content="b'\\xFF'")
  inspect(bytes[18], content="b'\\xFF'")
  inspect(bytes[19], content="b'\\xFF'")
  inspect(bytes[20], content="b'\\xFF'")
  // Param 2 NULL
  inspect(bytes[21], content="b'\\xFF'")
  inspect(bytes[22], content="b'\\xFF'")
  inspect(bytes[23], content="b'\\xFF'")
  inspect(bytes[24], content="b'\\xFF'")
  // Param 3 NULL
  inspect(bytes[25], content="b'\\xFF'")
  inspect(bytes[26], content="b'\\xFF'")
  inspect(bytes[27], content="b'\\xFF'")
  inspect(bytes[28], content="b'\\xFF'")
  // Result format count = 0
  inspect(bytes[29], content="b'\\x00'")
  inspect(bytes[30], content="b'\\x00'")
  inspect(bytes.length(), content="31")
}

///|
test "encode_copy_data_empty" {
  let bytes = encode(CopyData(Bytes::new(0)))
  inspect(bytes[0], content="b'\\x64'") // 'd'
  // Length = 4 (just the length field, no payload)
  inspect(bytes[1], content="b'\\x00'")
  inspect(bytes[2], content="b'\\x00'")
  inspect(bytes[3], content="b'\\x00'")
  inspect(bytes[4], content="b'\\x04'")
  inspect(bytes.length(), content="5")
}

///|
test "encode_copy_fail_empty_message" {
  let bytes = encode(CopyFail(""))
  inspect(bytes[0], content="b'\\x66'") // 'f'
  // Length = 4 + 1 = 5 (just the null terminator)
  inspect(bytes[1], content="b'\\x00'")
  inspect(bytes[2], content="b'\\x00'")
  inspect(bytes[3], content="b'\\x00'")
  inspect(bytes[4], content="b'\\x05'")
  // Null terminator for the empty string
  inspect(bytes[5], content="b'\\x00'")
  inspect(bytes.length(), content="6")
}

///|
test "encode_query_utf8" {
  let bytes = encode(Query("SELECT '日本語'"))
  inspect(bytes[0], content="b'\\x51'") // 'Q'
  // "SELECT '日本語'" in UTF-8:
  // "SELECT '" = 8 bytes, each CJK char = 3 bytes (9 bytes), "'" = 1 byte
  // Total query string = 8 + 9 + 1 = 18 bytes, + null = 19
  // Length field = 4 + 19 = 23 = 0x17
  inspect(bytes[1], content="b'\\x00'")
  inspect(bytes[2], content="b'\\x00'")
  inspect(bytes[3], content="b'\\x00'")
  inspect(bytes[4], content="b'\\x17'")
  // Last byte should be null terminator
  inspect(bytes[bytes.length() - 1], content="b'\\x00'")
  // Total = type(1) + length(4) + query(18) + null(1) = 24
  inspect(bytes.length(), content="24")
}
