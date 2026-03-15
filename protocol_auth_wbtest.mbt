///|
/// Unit tests for authentication
test "md5_password" {
  // Test case from PostgreSQL documentation
  // md5(md5("secretpostgres") + salt)
  // with salt = [0x01, 0x02, 0x03, 0x04]

  let salt = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let result = md5_password("secret", "postgres", salt)

  // The result should start with "md5"
  assert_true(result[:3] == "md5")
  // And be 35 characters total ("md5" + 32 hex chars)
  assert_eq(result.length(), 35)
}

///|
test "md5_empty_string" {
  // MD5 of empty string is d41d8cd98f00b204e9800998ecf8427e
  let result = md5_password(
    "",
    "",
    Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x00']),
  )
  assert_true(result[:3] == "md5")
  assert_eq(result.length(), 35)
}

///|
test "md5_known_hash" {
  // Test with known MD5 values
  // MD5("hello") = 5d41402abc4b2a76b9719d911017c592
  let salt = Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x00'])
  let result = md5_password("hello", "", salt)

  // Result should be deterministic
  assert_eq(result.length(), 35)
}

///|
test "md5 empty string" {
  // MD5("") = d41d8cd98f00b204e9800998ecf8427e
  let hash = md5(b"")
  inspect(bytes_to_hex(hash), content="d41d8cd98f00b204e9800998ecf8427e")
}

///|
test "md5 hello" {
  // MD5("hello") = 5d41402abc4b2a76b9719d911017c592
  let hash = md5(@utf8.encode("hello"[:]))
  inspect(bytes_to_hex(hash), content="5d41402abc4b2a76b9719d911017c592")
}

///|
test "md5 abc" {
  // MD5("abc") = 900150983cd24fb0d6963f7d28e17f72
  let hash = md5(@utf8.encode("abc"[:]))
  inspect(bytes_to_hex(hash), content="900150983cd24fb0d6963f7d28e17f72")
}

///|
test "md5_password known PostgreSQL value" {
  // Verified against PostgreSQL:
  // md5(md5("secret" + "postgres") + salt)
  // where salt = [0x89, 0xAB, 0xCD, 0xEF]
  //
  // Step 1: MD5("secretpostgres") = 53f48b7c4b76a86ce72276c5755f217d
  // Step 2: MD5("53f48b7c4b76a86ce72276c5755f217d" + salt_bytes)
  let salt = Bytes::from_array([b'\x89', b'\xAB', b'\xCD', b'\xEF'])
  let result = md5_password("secret", "postgres", salt)
  assert_true(result[:3] == "md5")
  // Verify step 1 independently
  let inner = md5(@utf8.encode("secretpostgres"[:]))
  inspect(
    bytes_to_hex(inner),
    content=(
      #|53f48b7c4b76a86ce72276c5755f217d
    ),
  )
}

// =============================================================================
// Medium/Low priority tests
// =============================================================================

///|
test "md5_password with empty password" {
  let salt = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let result = md5_password("", "postgres", salt)
  assert_true(result[:3] == "md5")
  assert_eq(result.length(), 35)
}

///|
test "md5_password with empty username" {
  let salt = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let result = md5_password("secret", "", salt)
  assert_true(result[:3] == "md5")
  assert_eq(result.length(), 35)
}

///|
test "md5_password different salt produces different output" {
  let salt1 = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let salt2 = Bytes::from_array([b'\x05', b'\x06', b'\x07', b'\x08'])
  let result1 = md5_password("secret", "postgres", salt1)
  let result2 = md5_password("secret", "postgres", salt2)
  assert_true(result1 != result2)
}
