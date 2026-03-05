///| PBKDF2-HMAC-SHA-256 Implementation
///
/// Implements PBKDF2 (RFC 2898) using HMAC-SHA-256 for SCRAM-SHA-256 authentication.
/// Only produces a single 32-byte block (dkLen = 32), which is all SCRAM needs.

///|
/// Compute HMAC-SHA-256 using moonbitlang/x/crypto, returning Bytes.
fn hmac_sha256(key : Bytes, message : Bytes) -> Bytes {
  let result = @crypto.hmac(@crypto.SHA256::new(), key[:], message[:])
  result.unsafe_reinterpret_as_bytes()
}

///|
/// Compute PBKDF2-HMAC-SHA-256(password, salt, iterations) -> 32 bytes
fn pbkdf2_sha256(password : Bytes, salt : Bytes, iterations : Int) -> Bytes {
  // U1 = HMAC(password, salt || INT(1))
  // INT(1) = big-endian 32-bit encoding of 1
  let salt_with_int : Array[Byte] = Array::new(capacity=salt.length() + 4)
  for i = 0; i < salt.length(); i = i + 1 {
    salt_with_int.push(salt[i])
  }
  salt_with_int.push(b'\x00')
  salt_with_int.push(b'\x00')
  salt_with_int.push(b'\x00')
  salt_with_int.push(b'\x01')

  let mut u_prev = hmac_sha256(password, Bytes::from_array(salt_with_int))
  let result : FixedArray[Byte] = FixedArray::make(32, b'\x00')

  // Initialize result with U1
  for i = 0; i < 32; i = i + 1 {
    result[i] = u_prev[i]
  }

  // U2 through U_iterations
  for _iter = 1; _iter < iterations; _iter = _iter + 1 {
    let u_curr = hmac_sha256(password, u_prev)
    // XOR into result
    for i = 0; i < 32; i = i + 1 {
      result[i] = (result[i].to_int() ^ u_curr[i].to_int()).to_byte()
    }
    u_prev = u_curr
  }

  result.unsafe_reinterpret_as_bytes()
}
