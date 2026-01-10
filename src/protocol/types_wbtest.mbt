///| Unit tests for type conversions

/// Helper to convert bytes to ASCII string for test assertions
fn test_bytes_to_string(data : Bytes) -> String {
  let chars : Array[Char] = Array::new(capacity=data.length())
  for i = 0; i < data.length(); i = i + 1 {
    chars.push(data[i].to_int().unsafe_to_char())
  }
  String::from_array(chars)
}

test "parse_text_value_null" {
  let result = parse_text_value(None, OID_TEXT)
  assert_eq(result, Null)
}

test "parse_text_value_bool_true" {
  let bytes = Bytes::from_array([b't'])
  let result = parse_text_value(Some(bytes), OID_BOOL)
  assert_eq(result, Bool(true))
}

test "parse_text_value_bool_false" {
  let bytes = Bytes::from_array([b'f'])
  let result = parse_text_value(Some(bytes), OID_BOOL)
  assert_eq(result, Bool(false))
}

test "parse_text_value_int" {
  let bytes = Bytes::from_array([b'1', b'2', b'3', b'4', b'5'])
  let result = parse_text_value(Some(bytes), OID_INT4)
  assert_eq(result, Int(12345))
}

test "parse_text_value_negative_int" {
  let bytes = Bytes::from_array([b'-', b'4', b'2'])
  let result = parse_text_value(Some(bytes), OID_INT4)
  assert_eq(result, Int(-42))
}

test "parse_text_value_float" {
  let bytes = Bytes::from_array([b'3', b'.', b'1', b'4'])
  let result = parse_text_value(Some(bytes), OID_FLOAT8)
  match result {
    Float(n) => assert_true(n > 3.13 && n < 3.15)
    _ => fail("Expected Float")
  }
}

test "parse_text_value_text" {
  let bytes = Bytes::from_array([b'h', b'e', b'l', b'l', b'o', b' ', b'w', b'o', b'r', b'l', b'd'])
  let result = parse_text_value(Some(bytes), OID_TEXT)
  assert_eq(result, String("hello world"))
}

test "serialize_value_null" {
  let result = serialize_value(Null)
  match result {
    None => ()
    Some(_) => fail("Expected None")
  }
}

test "serialize_value_bool_true" {
  let result = serialize_value(Bool(true))
  match result {
    Some(b) => assert_eq(test_bytes_to_string(b), "t")
    None => fail("Expected Some")
  }
}

test "serialize_value_bool_false" {
  let result = serialize_value(Bool(false))
  match result {
    Some(b) => assert_eq(test_bytes_to_string(b), "f")
    None => fail("Expected Some")
  }
}

test "serialize_value_int" {
  let result = serialize_value(Int(42))
  match result {
    Some(b) => assert_eq(test_bytes_to_string(b), "42")
    None => fail("Expected Some")
  }
}

test "serialize_value_string" {
  let result = serialize_value(String("hello"))
  match result {
    Some(b) => assert_eq(test_bytes_to_string(b), "hello")
    None => fail("Expected Some")
  }
}

test "value_as_bool" {
  let v : Value = Bool(true)
  assert_eq(v.as_bool(), Some(true))

  let v2 : Value = String("not a bool")
  assert_eq(v2.as_bool(), None)
}

test "value_as_int" {
  let v : Value = Int(42)
  assert_eq(v.as_int(), Some(42))

  let v2 : Value = Int64(100L)
  assert_eq(v2.as_int(), Some(100))
}

test "value_as_string" {
  let v : Value = String("hello")
  assert_eq(v.as_string(), Some("hello"))

  let v2 : Value = Int(42)
  assert_eq(v2.as_string(), Some("42"))

  let v3 : Value = Null
  assert_eq(v3.as_string(), None)
}

test "value_is_null" {
  let v1 : Value = Null
  assert_true(v1.is_null())
  let v2 : Value = Int(0)
  assert_false(v2.is_null())
  let v3 : Value = String("")
  assert_false(v3.is_null())
}
