///|
/// SCRAM-SHA-256 unit tests

///|
test "scram_client_first: message format" {
  let (full, bare) = scram_client_first("user", "rOprNGfwEbeRWgbNEkqO")
  inspect(full, content="n,,n=user,r=rOprNGfwEbeRWgbNEkqO")
  inspect(bare, content="n=user,r=rOprNGfwEbeRWgbNEkqO")
}

///|
test "scram_client_final: compute proof and server signature" {
  // Use RFC 5802 example values adapted for SHA-256
  let client_nonce = "rOprNGfwEbeRWgbNEkqO"
  let (_, client_first_bare) = scram_client_first("user", client_nonce)
  let server_nonce = "rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0"
  let salt_b64 = "W22ZaJ0SNY7soEsUEjb6gQ=="
  let server_first = "r=" + server_nonce + ",s=" + salt_b64 + ",i=4096"
  let (client_final, _server_sig) = scram_client_final(
    "pencil", client_first_bare, server_first, client_nonce,
  )
  // Verify the client-final starts with the expected prefix
  assert_true(client_final.has_prefix("c=biws,r=" + server_nonce + ",p="))
}

///|
test "scram_verify_server: valid signature" {
  // Manually compute a known server signature for testing
  let password = "pencil"
  let salt = @base64.decode("W22ZaJ0SNY7soEsUEjb6gQ=="[:])
  let salted_password = pbkdf2_sha256(@utf8.encode(password[:]), salt, 4096)
  let server_key = hmac_sha256(salted_password, @utf8.encode("Server Key"[:]))
  let auth_message = "test-auth-message"
  let server_signature = hmac_sha256(server_key, @utf8.encode(auth_message[:]))
  let sig_b64 = @base64.encode(server_signature[:])
  let server_final = "v=" + sig_b64
  // Should not raise
  scram_verify_server(server_final, server_signature)
}

///|
test "scram_verify_server: invalid signature raises error" {
  let bad_sig = Bytes::make(32, b'\x00')
  let different_sig = Bytes::make(32, b'\xFF')
  let sig_b64 = @base64.encode(bad_sig[:])
  let server_final = "v=" + sig_b64
  let mut got_error = false
  scram_verify_server(server_final, different_sig) catch {
    ScramError(_) => got_error = true
  }
  assert_true(got_error)
}

///|
test "split_string" {
  let parts = split_string("a,b,c", ',')
  assert_eq(parts.length(), 3)
  assert_eq(parts[0], "a")
  assert_eq(parts[1], "b")
  assert_eq(parts[2], "c")
}

///|
test "parse_int_string" {
  assert_eq(parse_int_string("4096"), 4096)
  assert_eq(parse_int_string("1"), 1)
  assert_eq(parse_int_string("100000"), 100000)
}
