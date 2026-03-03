///| PostgreSQL Authentication Helpers
///
/// Implements MD5 password hashing as required by PostgreSQL authentication.
/// PostgreSQL MD5 auth format: "md5" + md5(md5(password + username) + salt)

///|
/// Compute MD5 password hash for PostgreSQL authentication
/// Returns the string to send in PasswordMessage
pub fn md5_password(
  password : String,
  username : String,
  salt : Bytes,
) -> String {
  // Step 1: md5(password + username)
  let inner_input = password + username
  let inner_hash = md5(@utf8.encode(inner_input[:]))

  // Step 2: convert to hex string
  let inner_hex = bytes_to_hex(inner_hash)

  // Step 3: md5(inner_hex + salt)
  let inner_hex_bytes = @utf8.encode(inner_hex[:])
  let outer_input : FixedArray[Byte] = FixedArray::make(
    inner_hex_bytes.length() + salt.length(),
    b'\x00',
  )
  for i = 0; i < inner_hex_bytes.length(); i = i + 1 {
    outer_input[i] = inner_hex_bytes[i]
  }
  for i = 0; i < salt.length(); i = i + 1 {
    outer_input[inner_hex_bytes.length() + i] = salt[i]
  }
  let outer_hash = md5(outer_input.unsafe_reinterpret_as_bytes())

  // Step 4: "md5" + hex
  "md5" + bytes_to_hex(outer_hash)
}

///|
/// Lookup table for hex digit bytes
let hex_table : FixedArray[Byte] = [
  b'0', b'1', b'2', b'3', b'4', b'5', b'6', b'7', b'8', b'9', b'a', b'b', b'c', b'd',
  b'e', b'f',
]

///|
/// Get hex digit byte for a value 0-15 in O(1)
fn hex_byte(value : Int) -> Byte {
  hex_table[value]
}

///|
/// Convert bytes to lowercase hex string
fn bytes_to_hex(data : Bytes) -> String {
  let result : Array[Char] = []
  for i = 0; i < data.length(); i = i + 1 {
    let b = data[i].to_int()
    result.push(hex_byte((b >> 4) & 0xF).to_int().unsafe_to_char())
    result.push(hex_byte(b & 0xF).to_int().unsafe_to_char())
  }
  String::from_array(result)
}

///|
/// MD5 hash function using moonbitlang/x/crypto
/// Returns 16-byte hash
fn md5(data : Bytes) -> Bytes {
  @crypto.md5(data).unsafe_reinterpret_as_bytes()
}
