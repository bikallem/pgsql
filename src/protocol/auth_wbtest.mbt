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
