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
  let inner_hash = md5(string_to_bytes(inner_input))

  // Step 2: convert to hex string
  let inner_hex = bytes_to_hex(inner_hash)

  // Step 3: md5(inner_hex + salt)
  let inner_hex_bytes = string_to_bytes(inner_hex)
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
/// Convert String to Bytes
fn string_to_bytes(s : String) -> Bytes {
  let arr : Array[Byte] = []
  for c in s {
    let code = c.to_int()
    if code < 0x80 {
      arr.push(code.to_byte())
    } else if code < 0x800 {
      arr.push((0xC0 | (code >> 6)).to_byte())
      arr.push((0x80 | (code & 0x3F)).to_byte())
    } else if code < 0x10000 {
      arr.push((0xE0 | (code >> 12)).to_byte())
      arr.push((0x80 | ((code >> 6) & 0x3F)).to_byte())
      arr.push((0x80 | (code & 0x3F)).to_byte())
    } else {
      arr.push((0xF0 | (code >> 18)).to_byte())
      arr.push((0x80 | ((code >> 12) & 0x3F)).to_byte())
      arr.push((0x80 | ((code >> 6) & 0x3F)).to_byte())
      arr.push((0x80 | (code & 0x3F)).to_byte())
    }
  }
  Bytes::from_array(arr)
}

///|
/// Convert bytes to lowercase hex string
fn bytes_to_hex(data : Bytes) -> String {
  let hex_chars = "0123456789abcdef"
  let result : Array[Char] = []
  for i = 0; i < data.length(); i = i + 1 {
    let b = data[i].to_int()
    result.push(
      hex_char_at(hex_chars, (b >> 4) & 0xF).to_int().unsafe_to_char(),
    )
    result.push(hex_char_at(hex_chars, b & 0xF).to_int().unsafe_to_char())
  }
  String::from_array(result)
}

///|
/// Get hex character at index
fn hex_char_at(s : String, idx : Int) -> Byte {
  let mut i = 0
  for c in s {
    if i == idx {
      return c.to_int().to_byte()
    }
    i += 1
  }
  b'0'
}

// =============================================================================
// MD5 Implementation
// =============================================================================

///|
/// MD5 hash function
/// Returns 16-byte hash
fn md5(data : Bytes) -> Bytes {
  // MD5 initial state
  let mut a0 : UInt = 0x67452301
  let mut b0 : UInt = 0xefcdab89
  let mut c0 : UInt = 0x98badcfe
  let mut d0 : UInt = 0x10325476

  // Pre-computed shift amounts
  let s : FixedArray[Int] = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5,
    9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16,
    23, 4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ]

  // Pre-computed K constants (binary integer part of sines)
  let k : FixedArray[UInt] = [
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613,
    0xfd469501, 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193,
    0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d,
    0x02441453, 0xd8a1e681, 0xe7d3fbc8, 0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122,
    0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70, 0x289b7ec6, 0xeaa127fa,
    0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665, 0xf4292244,
    0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb,
    0xeb86d391,
  ]

  // Pad message
  let original_len = data.length()
  let original_bits = original_len * 8

  // Calculate padded length (multiple of 64 bytes = 512 bits)
  let mut padded_len = original_len + 1 // +1 for 0x80 byte
  while padded_len % 64 != 56 {
    padded_len += 1
  }
  padded_len += 8 // 64-bit length

  let padded : FixedArray[Byte] = FixedArray::make(padded_len, b'\x00')

  // Copy original data
  for i = 0; i < original_len; i = i + 1 {
    padded[i] = data[i]
  }

  // Append 0x80
  padded[original_len] = b'\x80'

  // Rest is already zero

  // Append original length in bits as 64-bit little-endian
  padded[padded_len - 8] = (original_bits & 0xFF).to_byte()
  padded[padded_len - 7] = ((original_bits >> 8) & 0xFF).to_byte()
  padded[padded_len - 6] = ((original_bits >> 16) & 0xFF).to_byte()
  padded[padded_len - 5] = ((original_bits >> 24) & 0xFF).to_byte()
  // Upper 32 bits are 0 for messages < 2^32 bits

  // Process each 64-byte chunk
  let num_chunks = padded_len / 64
  for chunk = 0; chunk < num_chunks; chunk = chunk + 1 {
    let chunk_offset = chunk * 64

    // Break chunk into 16 32-bit little-endian words
    let m : FixedArray[UInt] = FixedArray::make(16, 0U)
    for i = 0; i < 16; i = i + 1 {
      let j = chunk_offset + i * 4
      m[i] = padded[j].to_int().reinterpret_as_uint() |
        (padded[j + 1].to_int().reinterpret_as_uint() << 8) |
        (padded[j + 2].to_int().reinterpret_as_uint() << 16) |
        (padded[j + 3].to_int().reinterpret_as_uint() << 24)
    }

    // Initialize hash value for this chunk
    let mut a = a0
    let mut b = b0
    let mut c = c0
    let mut d = d0

    // Main loop
    for i = 0; i < 64; i = i + 1 {
      let mut f : UInt = 0U
      let mut g : Int = 0

      if i < 16 {
        f = (b & c) | (b.lnot() & d)
        g = i
      } else if i < 32 {
        f = (d & b) | (d.lnot() & c)
        g = (5 * i + 1) % 16
      } else if i < 48 {
        f = b ^ c ^ d
        g = (3 * i + 5) % 16
      } else {
        f = c ^ (b | d.lnot())
        g = 7 * i % 16
      }

      let temp = d
      d = c
      c = b
      let sum = a + f + k[i] + m[g]
      b = b + left_rotate(sum, s[i])
      a = temp
    }

    // Add this chunk's hash to result
    a0 = a0 + a
    b0 = b0 + b
    c0 = c0 + c
    d0 = d0 + d
  }

  // Produce final hash value (little-endian)
  let result : FixedArray[Byte] = FixedArray::make(16, b'\x00')
  result[0] = (a0 & 0xFFU).reinterpret_as_int().to_byte()
  result[1] = ((a0 >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  result[2] = ((a0 >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  result[3] = ((a0 >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  result[4] = (b0 & 0xFFU).reinterpret_as_int().to_byte()
  result[5] = ((b0 >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  result[6] = ((b0 >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  result[7] = ((b0 >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  result[8] = (c0 & 0xFFU).reinterpret_as_int().to_byte()
  result[9] = ((c0 >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  result[10] = ((c0 >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  result[11] = ((c0 >> 24) & 0xFFU).reinterpret_as_int().to_byte()
  result[12] = (d0 & 0xFFU).reinterpret_as_int().to_byte()
  result[13] = ((d0 >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  result[14] = ((d0 >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  result[15] = ((d0 >> 24) & 0xFFU).reinterpret_as_int().to_byte()

  result.unsafe_reinterpret_as_bytes()
}

///|
/// Left rotate a 32-bit unsigned integer
fn left_rotate(x : UInt, n : Int) -> UInt {
  (x << n) | (x >> (32 - n))
}
