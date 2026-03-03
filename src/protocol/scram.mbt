///| SCRAM-SHA-256 Client Implementation
///
/// Implements the client side of SCRAM-SHA-256 authentication
/// per RFC 5802 and RFC 7677 for PostgreSQL SASL authentication.

///|
/// SCRAM authentication error
pub suberror ScramError {
  ScramError(String)
}

///|
/// Build the client-first message for SCRAM-SHA-256.
/// Returns (full_message, bare_message).
/// The bare_message is needed later for computing the auth message.
pub fn scram_client_first(
  username : String,
  nonce : String,
) -> (String, String) {
  // gs2-header = "n,,"  (no channel binding, no authzid)
  // client-first-message-bare = "n=" + username + ",r=" + nonce
  let bare = "n=" + username + ",r=" + nonce
  let full = "n,," + bare
  (full, bare)
}

///|
/// Parse the server-first-message and compute the client-final message.
/// Returns (client_final_message, expected_server_signature).
///
/// server_first format: "r=<nonce>,s=<salt>,i=<iterations>"
pub fn scram_client_final(
  password : String,
  client_first_bare : String,
  server_first : String,
  client_nonce : String,
) -> (String, Bytes) raise ScramError {
  // Parse server-first-message
  let parts = split_string(server_first, ',')
  guard parts.length() >= 3 else {
    raise ScramError("Invalid server-first-message")
  }

  // Extract r=<nonce>, s=<salt>, i=<iterations>
  let mut server_nonce = ""
  let mut salt_b64 = ""
  let mut iterations = 0
  for part in parts {
    if part.has_prefix("r=") {
      server_nonce = part[2:].to_string()
    } else if part.has_prefix("s=") {
      salt_b64 = part[2:].to_string()
    } else if part.has_prefix("i=") {
      iterations = parse_int_string(part[2:].to_string())
    }
  }

  // Verify server nonce starts with our client nonce
  guard server_nonce.has_prefix(client_nonce) else {
    raise ScramError("Server nonce does not start with client nonce")
  }
  guard iterations > 0 else { raise ScramError("Invalid iteration count") }

  // Decode salt from base64
  let salt = @base64.decode(salt_b64[:]) catch {
    _ => raise ScramError("Invalid base64 in server salt")
  }

  // Compute SaltedPassword = PBKDF2(password, salt, iterations)
  let salted_password = pbkdf2_sha256(
    @utf8.encode(password[:]),
    salt,
    iterations,
  )

  // ClientKey = HMAC(SaltedPassword, "Client Key")
  let client_key = hmac_sha256(salted_password, @utf8.encode("Client Key"[:]))

  // StoredKey = SHA-256(ClientKey)
  let stored_key = @crypto.sha256(client_key).unsafe_reinterpret_as_bytes()

  // Build client-final-message-without-proof
  // channel-binding = base64("n,,") = "biws"
  let client_final_without_proof = "c=biws,r=" + server_nonce

  // AuthMessage = client-first-bare + "," + server-first + "," + client-final-without-proof
  let auth_message = client_first_bare +
    "," +
    server_first +
    "," +
    client_final_without_proof

  // ClientSignature = HMAC(StoredKey, AuthMessage)
  let client_signature = hmac_sha256(stored_key, @utf8.encode(auth_message[:]))

  // ClientProof = ClientKey XOR ClientSignature
  let client_proof_arr : FixedArray[Byte] = FixedArray::make(32, b'\x00')
  for i = 0; i < 32; i = i + 1 {
    client_proof_arr[i] = (client_key[i].to_int() ^ client_signature[i].to_int()).to_byte()
  }
  let client_proof = client_proof_arr.unsafe_reinterpret_as_bytes()

  // Encode proof as base64
  let proof_b64 = @base64.encode(client_proof[:])

  // Build client-final-message
  let client_final = client_final_without_proof + ",p=" + proof_b64

  // Compute ServerKey and ServerSignature for later verification
  let server_key = hmac_sha256(salted_password, @utf8.encode("Server Key"[:]))
  let server_signature = hmac_sha256(server_key, @utf8.encode(auth_message[:]))

  (client_final, server_signature)
}

///|
/// Verify the server-final-message matches the expected server signature.
/// server_final format: "v=<base64_signature>"
pub fn scram_verify_server(
  server_final : String,
  expected_signature : Bytes,
) -> Unit raise ScramError {
  guard server_final.has_prefix("v=") else {
    raise ScramError("Invalid server-final-message: missing v= prefix")
  }
  let sig_b64 = server_final[2:].to_string()
  let actual_signature = @base64.decode(sig_b64[:]) catch {
    _ => raise ScramError("Invalid base64 in server signature")
  }
  guard actual_signature.length() == expected_signature.length() else {
    raise ScramError("Server signature length mismatch")
  }
  for i = 0; i < actual_signature.length(); i = i + 1 {
    guard actual_signature[i] == expected_signature[i] else {
      raise ScramError("Server signature verification failed")
    }
  }
}

// =============================================================================
// Helper Functions
// =============================================================================

///|
/// Split a string by a single character delimiter
fn split_string(s : String, delim : Char) -> Array[String] {
  let parts : Array[String] = []
  let buf : Array[Char] = []
  for c in s {
    if c == delim {
      parts.push(String::from_array(buf))
      buf.clear()
    } else {
      buf.push(c)
    }
  }
  if buf.length() > 0 {
    parts.push(String::from_array(buf))
  }
  parts
}

///|
/// Parse an integer from a string
fn parse_int_string(s : String) -> Int {
  let mut result = 0
  for c in s {
    let digit = c.to_int() - '0'.to_int()
    if digit >= 0 && digit <= 9 {
      result = result * 10 + digit
    }
  }
  result
}
