///| Unit tests for type conversions

///|
/// Helper to convert bytes to ASCII string for test assertions
fn test_bytes_to_string(data : Bytes) -> String {
  let chars : Array[Char] = Array::new(capacity=data.length())
  for i = 0; i < data.length(); i = i + 1 {
    chars.push(data[i].to_int().unsafe_to_char())
  }
  String::from_array(chars)
}

// =============================================================================
// parse_text_value tests
// =============================================================================

///|
test "parse_text_value null" {
  inspect(parse_text_value(None, OID_TEXT), content="Null")
}

///|
test "parse_text_value bool true" {
  let bytes = Bytes::from_array([b't'])
  inspect(parse_text_value(Some(bytes), OID_BOOL), content="Bool(true)")
}

///|
test "parse_text_value bool false" {
  let bytes = Bytes::from_array([b'f'])
  inspect(parse_text_value(Some(bytes), OID_BOOL), content="Bool(false)")
}

///|
test "parse_text_value bool TRUE" {
  let bytes = Bytes::from_array([b'T', b'R', b'U', b'E'])
  inspect(parse_text_value(Some(bytes), OID_BOOL), content="Bool(true)")
}

///|
test "parse_text_value int" {
  let bytes = Bytes::from_array([b'1', b'2', b'3', b'4', b'5'])
  inspect(parse_text_value(Some(bytes), OID_INT4), content="Int(12345)")
}

///|
test "parse_text_value negative int" {
  let bytes = Bytes::from_array([b'-', b'4', b'2'])
  inspect(parse_text_value(Some(bytes), OID_INT4), content="Int(-42)")
}

///|
test "parse_text_value int2" {
  let bytes = Bytes::from_array([b'3', b'2', b'7', b'6', b'7'])
  inspect(parse_text_value(Some(bytes), OID_INT2), content="Int(32767)")
}

///|
test "parse_text_value int64" {
  let bytes = Bytes::from_array([
    b'9', b'9', b'9', b'9', b'9', b'9', b'9', b'9', b'9', b'9',
  ])
  inspect(parse_text_value(Some(bytes), OID_INT8), content="Int64(9999999999)")
}

///|
test "parse_text_value negative int64" {
  let bytes = Bytes::from_array([b'-', b'1', b'0', b'0'])
  inspect(parse_text_value(Some(bytes), OID_INT8), content="Int64(-100)")
}

///|
test "parse_text_value float" {
  let bytes = Bytes::from_array([b'3', b'.', b'1', b'4'])
  match parse_text_value(Some(bytes), OID_FLOAT8) {
    Float(n) => assert_true(n > 3.13 && n < 3.15)
    _ => fail("Expected Float")
  }
}

///|
test "parse_text_value float4" {
  let bytes = Bytes::from_array([b'1', b'.', b'5'])
  inspect(parse_text_value(Some(bytes), OID_FLOAT4), content="Float(1.5)")
}

///|
test "parse_text_value float scientific notation" {
  let bytes = Bytes::from_array([b'1', b'.', b'5', b'e', b'2'])
  inspect(parse_text_value(Some(bytes), OID_FLOAT8), content="Float(150)")
}

///|
test "parse_text_value float negative exponent" {
  let bytes = Bytes::from_array([b'1', b'e', b'-', b'1'])
  inspect(parse_text_value(Some(bytes), OID_FLOAT8), content="Float(0.1)")
}

///|
test "parse_text_value numeric" {
  let bytes = Bytes::from_array([b'4', b'2', b'.', b'0'])
  inspect(parse_text_value(Some(bytes), OID_NUMERIC), content="Float(42)")
}

///|
test "parse_text_value text" {
  let bytes = Bytes::from_array([
    b'h', b'e', b'l', b'l', b'o', b' ', b'w', b'o', b'r', b'l', b'd',
  ])
  inspect(
    parse_text_value(Some(bytes), OID_TEXT),
    content=(
      #|String("hello world")
    ),
  )
}

///|
test "parse_text_value text UTF-8" {
  let bytes = Bytes::from_array([
    b'\xE3', b'\x81', b'\x93', b'\xE3', b'\x82', b'\x93', b'\xE3', b'\x81', b'\xAB',
    b'\xE3', b'\x81', b'\xA1', b'\xE3', b'\x81', b'\xAF', b' ', b'\xF0', b'\x9F',
    b'\x9A', b'\x80',
  ])
  let expected = @utf8.decode_lossy(bytes[:])
  match parse_text_value(Some(bytes), OID_TEXT) {
    String(actual) => assert_eq(actual, expected)
    _ => fail("Expected String")
  }
}

///|
test "parse_text_value varchar" {
  let bytes = Bytes::from_array([b'a', b'b', b'c'])
  inspect(
    parse_text_value(Some(bytes), OID_VARCHAR),
    content=(
      #|String("abc")
    ),
  )
}

///|
test "parse_text_value bytea hex" {
  // \x48656c6c6f = "Hello"
  let bytes = Bytes::from_array([
    b'\\', b'x', b'4', b'8', b'6', b'5', b'6', b'c', b'6', b'c', b'6', b'f',
  ])
  match parse_text_value(Some(bytes), OID_BYTEA) {
    Bytes(b) => {
      inspect(b.length(), content="5")
      inspect(b[0], content="b'\\x48'")
      inspect(test_bytes_to_string(b), content="Hello")
    }
    _ => fail("Expected Bytes")
  }
}

///|
test "parse_text_value bytea empty hex" {
  let bytes = Bytes::from_array([b'\\', b'x'])
  match parse_text_value(Some(bytes), OID_BYTEA) {
    Bytes(b) => inspect(b.length(), content="0")
    _ => fail("Expected Bytes")
  }
}

// =============================================================================
// serialize_value tests
// =============================================================================

///|
test "serialize_value Null" {
  inspect(serialize_value(Null), content="None")
}

///|
test "serialize_value Bool true" {
  match serialize_value(Bool(true)) {
    Some(b) => inspect(test_bytes_to_string(b), content="t")
    None => fail("Expected Some")
  }
}

///|
test "serialize_value Bool false" {
  match serialize_value(Bool(false)) {
    Some(b) => inspect(test_bytes_to_string(b), content="f")
    None => fail("Expected Some")
  }
}

///|
test "serialize_value Int" {
  match serialize_value(Int(42)) {
    Some(b) => inspect(test_bytes_to_string(b), content="42")
    None => fail("Expected Some")
  }
}

///|
test "serialize_value Int negative" {
  match serialize_value(Int(-7)) {
    Some(b) => inspect(test_bytes_to_string(b), content="-7")
    None => fail("Expected Some")
  }
}

///|
test "serialize_value Int64" {
  match serialize_value(Int64(9999999999L)) {
    Some(b) => inspect(test_bytes_to_string(b), content="9999999999")
    None => fail("Expected Some")
  }
}

///|
test "serialize_value Float" {
  match serialize_value(Float(3.14)) {
    Some(b) => {
      let s = test_bytes_to_string(b)
      inspect(s, content="3.14")
    }
    None => fail("Expected Some")
  }
}

///|
test "serialize_value String" {
  match serialize_value(String("hello")) {
    Some(b) => inspect(test_bytes_to_string(b), content="hello")
    None => fail("Expected Some")
  }
}

///|
test "serialize_value String UTF-8" {
  let value = @utf8.decode_lossy(
    Bytes::from_array([
      b'\xE4', b'\xBD', b'\xA0', b'\xE5', b'\xA5', b'\xBD', b' ', b'\xF0', b'\x9F',
      b'\x8C', b'\x8D',
    ])[:],
  )
  match serialize_value(String(value)) {
    Some(b) => assert_eq(@utf8.decode_lossy(b[:]), value)
    None => fail("Expected Some")
  }
}

///|
test "serialize_value Bytes round-trip" {
  let original = Bytes::from_array([b'\x01', b'\x02', b'\xAB'])
  match serialize_value(Bytes(original)) {
    Some(b) => {
      // Should be hex-encoded
      inspect(b[0], content="b'\\x5C'") // backslash
      inspect(b[1], content="b'\\x78'") // 'x'
    }
    None => fail("Expected Some")
  }
}

// =============================================================================
// Value helper methods
// =============================================================================
// Edge cases
// =============================================================================

///|
test "parse_int with plus sign" {
  let bytes = Bytes::from_array([b'+', b'5'])
  inspect(parse_text_value(Some(bytes), OID_INT4), content="Int(5)")
}

///|
test "parse_int64 with plus sign" {
  let bytes = Bytes::from_array([b'+', b'1', b'0'])
  inspect(parse_text_value(Some(bytes), OID_INT8), content="Int64(10)")
}

///|
test "parse_float with plus sign" {
  let bytes = Bytes::from_array([b'+', b'1', b'.', b'0'])
  inspect(parse_text_value(Some(bytes), OID_FLOAT8), content="Float(1)")
}

// =============================================================================
// Edge case tests for parsing (#31)
// =============================================================================

///|
test "parse_bool unrecognized falls back to String" {
  let bytes = Bytes::from_array([b'y', b'e', b's'])
  inspect(
    parse_text_value(Some(bytes), OID_BOOL),
    content=(
      #|String("yes")
    ),
  )
}

///|
test "parse_int overflow falls back to String" {
  // 9999999999 overflows Int (max ~2.1B)
  let bytes = Bytes::from_array([
    b'9', b'9', b'9', b'9', b'9', b'9', b'9', b'9', b'9', b'9',
  ])
  inspect(
    parse_text_value(Some(bytes), OID_INT4),
    content=(
      #|String("9999999999")
    ),
  )
}

///|
test "parse_int64 overflow falls back to String" {
  // 99999999999999999999 overflows Int64 (max ~9.2e18)
  let bytes = Bytes::from_array([
    b'9', b'9', b'9', b'9', b'9', b'9', b'9', b'9', b'9', b'9', b'9', b'9', b'9',
    b'9', b'9', b'9', b'9', b'9', b'9', b'9',
  ])
  inspect(
    parse_text_value(Some(bytes), OID_INT8),
    content=(
      #|String("99999999999999999999")
    ),
  )
}

///|
test "parse_int invalid char falls back to String" {
  let bytes = Bytes::from_array([b'1', b'2', b'a'])
  inspect(
    parse_text_value(Some(bytes), OID_INT4),
    content=(
      #|String("12a")
    ),
  )
}

///|
test "parse_float NaN" {
  let bytes = Bytes::from_array([b'N', b'a', b'N'])
  match parse_text_value(Some(bytes), OID_FLOAT8) {
    Float(n) => assert_true(n != n) // NaN != NaN is true
    _ => fail("Expected Float(NaN)")
  }
}

///|
test "parse_float Infinity" {
  let bytes = Bytes::from_array([b'I', b'n', b'f', b'i', b'n', b'i', b't', b'y'])
  match parse_text_value(Some(bytes), OID_FLOAT8) {
    Float(n) => assert_true(n > 1.0e300)
    _ => fail("Expected Float(Infinity)")
  }
}

///|
test "parse_float -Infinity" {
  let bytes = Bytes::from_array([
    b'-', b'I', b'n', b'f', b'i', b'n', b'i', b't', b'y',
  ])
  match parse_text_value(Some(bytes), OID_FLOAT8) {
    Float(n) => assert_true(n < -1.0e300)
    _ => fail("Expected Float(-Infinity)")
  }
}

///|
test "parse_int empty string falls back to String" {
  let bytes = Bytes::from_array([])
  inspect(
    parse_text_value(Some(bytes), OID_INT4),
    content=(
      #|String("")
    ),
  )
}

///|
test "parse_float empty string falls back to String" {
  let bytes = Bytes::from_array([])
  inspect(
    parse_text_value(Some(bytes), OID_FLOAT8),
    content=(
      #|String("")
    ),
  )
}

// =============================================================================
// Date/Time/JSON/UUID type parsing tests
// =============================================================================

///|
test "parse_text_value date" {
  let bytes = Bytes::from_array([
    b'2', b'0', b'2', b'4', b'-', b'0', b'3', b'-', b'1', b'5',
  ])
  inspect(
    parse_text_value(Some(bytes), OID_DATE),
    content=(
      #|Date("2024-03-15")
    ),
  )
}

///|
test "parse_text_value time" {
  let bytes = Bytes::from_array([b'1', b'4', b':', b'3', b'0', b':', b'0', b'0'])
  inspect(
    parse_text_value(Some(bytes), OID_TIME),
    content=(
      #|Time("14:30:00")
    ),
  )
}

///|
test "parse_text_value timestamp" {
  let bytes = Bytes::from_array([
    b'2', b'0', b'2', b'4', b'-', b'0', b'3', b'-', b'1', b'5', b' ', b'1', b'4',
    b':', b'3', b'0', b':', b'0', b'0',
  ])
  inspect(
    parse_text_value(Some(bytes), OID_TIMESTAMP),
    content=(
      #|Timestamp("2024-03-15 14:30:00")
    ),
  )
}

///|
test "parse_text_value timestamptz" {
  let bytes = Bytes::from_array([
    b'2', b'0', b'2', b'4', b'-', b'0', b'3', b'-', b'1', b'5', b' ', b'1', b'4',
    b':', b'3', b'0', b':', b'0', b'0', b'+', b'0', b'0',
  ])
  inspect(
    parse_text_value(Some(bytes), OID_TIMESTAMPTZ),
    content=(
      #|TimestampTz("2024-03-15 14:30:00+00")
    ),
  )
}

///|
test "parse_text_value interval" {
  let bytes = Bytes::from_array([b'1', b' ', b'd', b'a', b'y'])
  inspect(
    parse_text_value(Some(bytes), OID_INTERVAL),
    content=(
      #|Interval("1 day")
    ),
  )
}

///|
test "parse_text_value json" {
  let bytes = Bytes::from_array([
    b'{', b'"', b'k', b'"', b':', b'"', b'v', b'"', b'}',
  ])
  inspect(
    parse_text_value(Some(bytes), OID_JSON),
    content=(
      #|Json("{\"k\":\"v\"}")
    ),
  )
}

///|
test "parse_text_value jsonb" {
  let bytes = Bytes::from_array([b'{', b'"', b'a', b'"', b':', b'1', b'}'])
  inspect(
    parse_text_value(Some(bytes), OID_JSONB),
    content=(
      #|Json("{\"a\":1}")
    ),
  )
}

///|
test "parse_text_value uuid" {
  let bytes = Bytes::from_array([
    b'5', b'5', b'0', b'e', b'8', b'4', b'0', b'0', b'-', b'e', b'2', b'9', b'b',
    b'-', b'4', b'1', b'd', b'4', b'-', b'a', b'7', b'1', b'6', b'-', b'4', b'4',
    b'6', b'6', b'5', b'5', b'4', b'4', b'0', b'0', b'0', b'0',
  ])
  inspect(
    parse_text_value(Some(bytes), OID_UUID),
    content=(
      #|Uuid("550e8400-e29b-41d4-a716-446655440000")
    ),
  )
}

///|
test "parse_text_value date null" {
  inspect(parse_text_value(None, OID_DATE), content="Null")
}

///|
test "serialize_value Date" {
  match serialize_value(Date("2024-03-15")) {
    Some(b) => inspect(test_bytes_to_string(b), content="2024-03-15")
    None => fail("Expected Some")
  }
}

///|
test "serialize_value Json" {
  match serialize_value(Json("{\"k\":\"v\"}")) {
    Some(b) =>
      inspect(
        test_bytes_to_string(b),
        content=(
          #|{"k":"v"}
        ),
      )
    None => fail("Expected Some")
  }
}

///|
test "serialize_value Uuid" {
  match serialize_value(Uuid("550e8400-e29b-41d4-a716-446655440000")) {
    Some(b) =>
      inspect(
        test_bytes_to_string(b),
        content="550e8400-e29b-41d4-a716-446655440000",
      )
    None => fail("Expected Some")
  }
}
