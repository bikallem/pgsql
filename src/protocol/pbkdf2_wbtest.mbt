///|
/// PBKDF2-HMAC-SHA-256 unit tests

///|
test "pbkdf2_sha256: RFC 7914 vector" {
  // From RFC 7914 Section 11: PBKDF2-HMAC-SHA-256("passwd", "salt", 1)
  let result = pbkdf2_sha256(
    @utf8.encode("passwd"[:]),
    @utf8.encode("salt"[:]),
    1,
  )
  inspect(
    bytes_to_hex(result),
    content="55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc",
  )
}

///|
test "pbkdf2_sha256: password/salt with 4096 iterations" {
  // From RFC 7914: PBKDF2-HMAC-SHA-256("Password", "NaCl", 80000)
  // Using a smaller iteration count for test speed.
  // Known vector: PBKDF2-HMAC-SHA-256("password", "salt", 4096)
  let result = pbkdf2_sha256(
    @utf8.encode("password"[:]),
    @utf8.encode("salt"[:]),
    4096,
  )
  inspect(
    bytes_to_hex(result),
    content="c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a",
  )
}
