///| SCRAM-SHA-256 Client Implementation
///
/// Implements the client side of SCRAM-SHA-256 authentication
/// per RFC 5802 and RFC 7677 for PostgreSQL SASL authentication.

///|
/// SCRAM authentication error
priv suberror ScramError {
  ScramError(String)
}

///|
/// Upper bound to avoid untrusted iteration counts causing excessive CPU work.
const MAX_SCRAM_ITERATIONS : Int = 1000000

///|
/// Build the client-first message for SCRAM-SHA-256.
/// Returns (full_message, bare_message).
/// The bare_message is needed later for computing the auth message.
fn scram_client_first(
  username : String,
  nonce : String,
) -> (String, String) {
  // gs2-header = "n,,"  (no channel binding, no authzid)
  // client-first-message-bare = "n=" + saslname(username) + ",r=" + nonce
  let bare = "n=" + escape_scram_username(username) + ",r=" + nonce
  let full = "n,," + bare
  (full, bare)
}

///|
/// Parse the server-first-message and compute the client-final message.
/// Returns (client_final_message, expected_server_signature).
///
/// server_first format: "r=<nonce>,s=<salt>,i=<iterations>"
fn scram_client_final(
  password : String,
  client_first_bare : String,
  server_first : String,
  client_nonce : String,
) -> (String, Bytes) raise ScramError {
  // Parse and validate server-first attributes: r, s, i
  let attrs = parse_scram_attributes(
    server_first,
    context="server-first-message",
  )
  let server_nonce = require_scram_attr(
    attrs,
    "r",
    context="server-first-message",
  )
  let salt_b64 = require_scram_attr(attrs, "s", context="server-first-message")
  let iterations = parse_scram_iteration_count(
    require_scram_attr(attrs, "i", context="server-first-message"),
  )

  // Verify server nonce starts with our client nonce
  guard server_nonce.has_prefix(client_nonce) else {
    raise ScramError("Server nonce does not start with client nonce")
  }

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
fn scram_verify_server(
  server_final : String,
  expected_signature : Bytes,
) -> Unit raise ScramError {
  let attrs = parse_scram_attributes(
    server_final,
    context="server-final-message",
  )
  match attrs.get("e") {
    Some(msg) => raise ScramError("Server SCRAM error: " + msg)
    None => ()
  }
  let sig_b64 = require_scram_attr(attrs, "v", context="server-final-message")
  let actual_signature = @base64.decode(sig_b64[:]) catch {
    _ => raise ScramError("Invalid base64 in server signature")
  }
  guard actual_signature.length() == expected_signature.length() else {
    raise ScramError("Server signature length mismatch")
  }
  guard constant_time_bytes_equal(actual_signature, expected_signature) else {
    raise ScramError("Server signature verification failed")
  }
}

// =============================================================================
// Helper Functions
// =============================================================================

///|
/// Constant-time byte comparison to prevent timing side-channels.
/// Both slices must have the same length (caller must check).
fn constant_time_bytes_equal(a : Bytes, b : Bytes) -> Bool {
  let mut diff = 0
  for i = 0; i < a.length(); i = i + 1 {
    diff = diff | (a[i].to_int() ^ b[i].to_int())
  }
  diff == 0
}

///|
/// Escape username for SCRAM "saslname" format.
/// Per RFC 5802, '=' -> '=3D' and ',' -> '=2C'.
fn escape_scram_username(username : String) -> String {
  let escaped : Array[Char] = []
  for c in username {
    if c == '=' {
      escaped.push('=')
      escaped.push('3')
      escaped.push('D')
    } else if c == ',' {
      escaped.push('=')
      escaped.push('2')
      escaped.push('C')
    } else {
      escaped.push(c)
    }
  }
  String::from_array(escaped)
}

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
/// Parse strict key/value SCRAM attributes like "k=v".
fn parse_scram_attributes(
  message : String,
  context~ : String,
) -> Map[String, String] raise ScramError {
  let parts = split_string(message, ',')
  let attrs : Map[String, String] = {}
  for part in parts {
    let chars : Array[Char] = []
    for c in part {
      chars.push(c)
    }
    guard chars.length() >= 3 && chars[1] == '=' else {
      raise ScramError("Invalid attribute in " + context)
    }
    let key = String::from_array([chars[0]])
    let value_chars : Array[Char] = []
    for i = 2; i < chars.length(); i = i + 1 {
      value_chars.push(chars[i])
    }
    let value = String::from_array(value_chars)
    guard value.length() > 0 else {
      raise ScramError("Empty attribute value in " + context)
    }
    match attrs.get(key) {
      Some(_) =>
        raise ScramError("Duplicate attribute '" + key + "' in " + context)
      None => attrs[key] = value
    }
  }
  attrs
}

///|
/// Require an attribute from parsed SCRAM attributes.
fn require_scram_attr(
  attrs : Map[String, String],
  key : String,
  context~ : String,
) -> String raise ScramError {
  match attrs.get(key) {
    Some(v) => v
    None => raise ScramError("Missing attribute '" + key + "' in " + context)
  }
}

///|
/// Parse SCRAM iteration count strictly and enforce a hard upper bound.
fn parse_scram_iteration_count(raw : String) -> Int raise ScramError {
  guard raw.length() > 0 else { raise ScramError("Invalid iteration count") }
  let mut result = 0
  for c in raw {
    let digit = c.to_int() - '0'.to_int()
    guard digit >= 0 && digit <= 9 else {
      raise ScramError("Invalid iteration count")
    }
    guard result <= (MAX_SCRAM_ITERATIONS - digit) / 10 else {
      raise ScramError("Iteration count exceeds limit")
    }
    result = result * 10 + digit
  }
  guard result > 0 else { raise ScramError("Invalid iteration count") }
  guard result <= MAX_SCRAM_ITERATIONS else {
    raise ScramError("Iteration count exceeds limit")
  }
  result
}
