///|
/// SCRAM-SHA-256 unit tests

///|
test "scram_client_first: message format" {
  let (full, bare) = scram_client_first("user", "rOprNGfwEbeRWgbNEkqO")
  inspect(full, content="n,,n=user,r=rOprNGfwEbeRWgbNEkqO")
  inspect(bare, content="n=user,r=rOprNGfwEbeRWgbNEkqO")
}

///|
test "scram_client_first: username escaping" {
  let (full, bare) = scram_client_first("a=b,c", "nonce")
  inspect(full, content="n,,n=a=3Db=2Cc,r=nonce")
  inspect(bare, content="n=a=3Db=2Cc,r=nonce")
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
test "scram_verify_server: server error attribute raises error" {
  let mut got_error = false
  scram_verify_server("e=invalid-proof", Bytes::make(32, b'\x00')) catch {
    ScramError(msg) => {
      got_error = true
      assert_true(msg.contains("Server SCRAM error"))
    }
  }
  assert_true(got_error)
}

///|
test "scram_client_final: malformed iteration rejected" {
  let client_nonce = "abc123"
  let (_, client_first_bare) = scram_client_first("user", client_nonce)
  let server_first = "r=abc123xyz,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4x96"
  let mut got_error = false
  ignore(
    (
      scram_client_final(
        "pencil", client_first_bare, server_first, client_nonce,
      ) catch {
        ScramError(_) => {
          got_error = true
          ("", b"")
        }
      } : (String, Bytes)),
  )
  assert_true(got_error)
}

///|
test "scram_client_final: oversized iteration rejected" {
  let client_nonce = "abc123"
  let (_, client_first_bare) = scram_client_first("user", client_nonce)
  let server_first = "r=abc123xyz,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=1000001"
  let mut got_error = false
  ignore(
    (
      scram_client_final(
        "pencil", client_first_bare, server_first, client_nonce,
      ) catch {
        ScramError(_) => {
          got_error = true
          ("", b"")
        }
      } : (String, Bytes)),
  )
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
test "constant_time_bytes_equal: equal bytes" {
  let a = Bytes::from_array([b'\x01', b'\x02', b'\x03'])
  let b = Bytes::from_array([b'\x01', b'\x02', b'\x03'])
  assert_true(constant_time_bytes_equal(a, b))
}

///|
test "constant_time_bytes_equal: different bytes" {
  let a = Bytes::from_array([b'\x01', b'\x02', b'\x03'])
  let b = Bytes::from_array([b'\x01', b'\xFF', b'\x03'])
  assert_true(not(constant_time_bytes_equal(a, b)))
}

///|
test "constant_time_bytes_equal: all zeros" {
  let a = Bytes::make(32, b'\x00')
  let b = Bytes::make(32, b'\x00')
  assert_true(constant_time_bytes_equal(a, b))
}

///|
test "constant_time_bytes_equal: single bit difference" {
  let a = Bytes::make(32, b'\x00')
  let b_arr : Array[Byte] = Array::new(capacity=32)
  for i = 0; i < 32; i = i + 1 {
    b_arr.push(if i == 31 { b'\x01' } else { b'\x00' })
  }
  assert_true(not(constant_time_bytes_equal(a, Bytes::from_array(b_arr))))
}

///|
test "parse_scram_iteration_count" {
  assert_eq(parse_scram_iteration_count("4096"), 4096)
  assert_eq(parse_scram_iteration_count("1"), 1)
  assert_eq(parse_scram_iteration_count("100000"), 100000)
}

// =============================================================================
// Medium/Low priority tests
// =============================================================================

///|
test "scram_client_final: server nonce not prefixed by client nonce raises error" {
  let client_nonce = "abc123"
  let (_, client_first_bare) = scram_client_first("user", client_nonce)
  // Server nonce does NOT start with client_nonce
  let server_first = "r=WRONG_NONCExyz,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"
  let mut got_error = false
  ignore(
    (
      scram_client_final(
        "pencil", client_first_bare, server_first, client_nonce,
      ) catch {
        ScramError(msg) => {
          got_error = true
          assert_true(msg.contains("client nonce"))
          ("", b"")
        }
      } : (String, Bytes)),
  )
  assert_true(got_error)
}

///|
test "scram_client_final: invalid base64 salt raises error" {
  let client_nonce = "abc123"
  let (_, client_first_bare) = scram_client_first("user", client_nonce)
  // "!!!" is not valid base64
  let server_first = "r=abc123xyz,s=!!!invalid!!!,i=4096"
  let mut got_error = false
  ignore(
    (
      scram_client_final(
        "pencil", client_first_bare, server_first, client_nonce,
      ) catch {
        ScramError(msg) => {
          got_error = true
          assert_true(msg.contains("base64") || msg.contains("salt"))
          ("", b"")
        }
      } : (String, Bytes)),
  )
  assert_true(got_error)
}

///|
test "scram_client_final: iteration count at MAX_SCRAM_ITERATIONS succeeds" {
  let client_nonce = "abc123"
  let (_, client_first_bare) = scram_client_first("user", client_nonce)
  let server_first = "r=abc123xyz,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=1000000"
  // Should not raise — iteration count is exactly at the limit
  // We just verify it doesn't error; we don't run all iterations,
  // but the parse step should accept 1000000
  let result = try {
    ignore(
      (
        scram_client_final(
          "pencil", client_first_bare, server_first, client_nonce,
        ) : (String, Bytes)),
    )
    true
  } catch {
    ScramError(_) => false
  }
  assert_true(result)
}

///|
test "scram_client_final: iteration count = 1 succeeds" {
  let client_nonce = "abc123"
  let (_, client_first_bare) = scram_client_first("user", client_nonce)
  let server_first = "r=abc123xyz,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=1"
  let (client_final, _server_sig) = scram_client_final(
    "pencil", client_first_bare, server_first, client_nonce,
  )
  assert_true(client_final.has_prefix("c=biws,r=abc123xyz,p="))
}

///|
test "scram_verify_server: malformed server-final without v= attribute" {
  let mut got_error = false
  scram_verify_server("s=something", Bytes::make(32, b'\x00')) catch {
    ScramError(msg) => {
      got_error = true
      assert_true(msg.contains("v") || msg.contains("Missing"))
    }
  }
  assert_true(got_error)
}

///|
test "escape_scram_username: just equals sign" {
  inspect(escape_scram_username("="), content="=3D")
}

///|
test "escape_scram_username: just comma" {
  inspect(escape_scram_username(","), content="=2C")
}
