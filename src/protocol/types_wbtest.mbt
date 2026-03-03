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

///|
test "Value::is_null" {
  inspect(Null.is_null(), content="true")
  inspect(Int(0).is_null(), content="false")
  inspect(String("").is_null(), content="false")
}

///|
test "Value::as_bool" {
  inspect(Bool(true).as_bool(), content="Some(true)")
  inspect(Bool(false).as_bool(), content="Some(false)")
  inspect(String("not a bool").as_bool(), content="None")
  inspect(Null.as_bool(), content="None")
}

///|
test "Value::as_int" {
  inspect(Int(42).as_int(), content="Some(42)")
  inspect(Int64(100L).as_int(), content="Some(100)")
  inspect(Float(3.9).as_int(), content="Some(3)")
  inspect(Null.as_int(), content="None")
  inspect(String("42").as_int(), content="None")
}

///|
test "Value::as_int64" {
  inspect(Int(42).as_int64(), content="Some(42)")
  inspect(Int64(100L).as_int64(), content="Some(100)")
  inspect(Float(2.7).as_int64(), content="Some(2)")
  inspect(Null.as_int64(), content="None")
}

///|
test "Value::as_float" {
  inspect(Float(3.14).as_float(), content="Some(3.14)")
  inspect(Int(10).as_float(), content="Some(10)")
  inspect(Int64(100L).as_float(), content="Some(100)")
  inspect(Null.as_float(), content="None")
}

///|
test "Value::as_string" {
  inspect(
    String("hello").as_string(),
    content=(
      #|Some("hello")
    ),
  )
  inspect(
    Int(42).as_string(),
    content=(
      #|Some("42")
    ),
  )
  inspect(
    Int64(100L).as_string(),
    content=(
      #|Some("100")
    ),
  )
  inspect(
    Bool(true).as_string(),
    content=(
      #|Some("true")
    ),
  )
  inspect(
    Bool(false).as_string(),
    content=(
      #|Some("false")
    ),
  )
  inspect(Null.as_string(), content="None")
}

///|
test "Value::as_bytes" {
  let b = Bytes::from_array([b'\x01'])
  inspect(Bytes(b).as_bytes() is Some(_), content="true")
  inspect(Null.as_bytes(), content="None")
  inspect(Int(1).as_bytes(), content="None")
}

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
    b'9', b'9', b'9', b'9', b'9', b'9', b'9', b'9', b'9', b'9', b'9', b'9',
    b'9', b'9', b'9', b'9', b'9', b'9', b'9', b'9',
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
  let bytes = Bytes::from_array([
    b'I', b'n', b'f', b'i', b'n', b'i', b't', b'y',
  ])
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
