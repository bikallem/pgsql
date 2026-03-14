///|
/// PostgreSQL Type System
///
/// This module defines PostgreSQL type OIDs and provides value conversion
/// between MoonBit types and PostgreSQL text format representations.

// =============================================================================
// PostgreSQL Type OIDs
// =============================================================================

// Boolean
pub const OID_BOOL : UInt = 16

// Numeric Types

///|
pub const OID_INT2 : UInt = 21 // smallint

///|
pub const OID_INT4 : UInt = 23 // integer

///|
pub const OID_INT8 : UInt = 20 // bigint

///|
pub const OID_FLOAT4 : UInt = 700 // real

///|
pub const OID_FLOAT8 : UInt = 701 // double precision

///|
pub const OID_NUMERIC : UInt = 1700 // numeric/decimal

// Character Types

///|
pub const OID_CHAR : UInt = 18 // "char" (single character)

///|
pub const OID_NAME : UInt = 19 // name (63 chars)

///|
pub const OID_TEXT : UInt = 25 // text

///|
pub const OID_VARCHAR : UInt = 1043 // varchar

///|
pub const OID_BPCHAR : UInt = 1042 // char(n)

// Binary Types

///|
pub const OID_BYTEA : UInt = 17 // bytea

// Date/Time Types

///|
pub const OID_DATE : UInt = 1082

///|
pub const OID_TIME : UInt = 1083

///|
pub const OID_TIMESTAMP : UInt = 1114

///|
pub const OID_TIMESTAMPTZ : UInt = 1184

///|
pub const OID_TIMETZ : UInt = 1266

///|
pub const OID_INTERVAL : UInt = 1186

// JSON Types

///|
pub const OID_JSON : UInt = 114

///|
pub const OID_JSONB : UInt = 3802

// UUID

///|
pub const OID_UUID : UInt = 2950

// =============================================================================
// Byte/String Conversion Helpers
// =============================================================================

///|
/// Convert UTF-8 bytes to string (invalid sequences are replaced).
fn bytes_to_ascii_string(data : Bytes) -> String {
  @utf8.decode_lossy(data[:])
}

// =============================================================================
// Value Type
// =============================================================================

///|
/// Represents a PostgreSQL value in MoonBit
pub(all) enum Value {
  /// NULL value
  Null
  /// Boolean value
  Bool(Bool)
  /// 32-bit integer
  Int(Int)
  /// 64-bit integer
  Int64(Int64)
  /// Floating point number
  Float(Double)
  /// String/text value
  String(String)
  /// Binary data
  Bytes(Bytes)
  /// Date value (e.g. "2024-03-15")
  Date(String)
  /// Time value (e.g. "14:30:00.123456")
  Time(String)
  /// Timestamp without timezone (e.g. "2024-03-15 14:30:00")
  Timestamp(String)
  /// Timestamp with timezone (e.g. "2024-03-15 14:30:00+00")
  TimestampTz(String)
  /// Interval value (e.g. "1 year 2 mons 3 days 04:05:06")
  Interval(String)
  /// JSON/JSONB value
  Json(String)
  /// UUID value (e.g. "550e8400-e29b-41d4-a716-446655440000")
  Uuid(String)
} derive(Show, Eq)

// =============================================================================
// Text Format Parsing (PostgreSQL -> MoonBit)
// =============================================================================

///|
/// Parse a PostgreSQL text-format value to a MoonBit Value
/// Returns Null if the input is None (SQL NULL)
pub fn parse_text_value(data : Bytes?, type_oid : UInt) -> Value {
  match data {
    None => Null
    Some(bytes) => {
      let text = bytes_to_ascii_string(bytes)
      parse_text_value_inner(text, type_oid)
    }
  }
}

///|
/// Parse text value based on type OID
fn parse_text_value_inner(text : String, type_oid : UInt) -> Value {
  // OID constants: BOOL=16, INT2=21, INT4=23, INT8=20,
  // FLOAT4=700, FLOAT8=701, NUMERIC=1700, BYTEA=17,
  // DATE=1082, TIME=1083, TIMETZ=1266, TIMESTAMP=1114,
  // TIMESTAMPTZ=1184, INTERVAL=1186, JSON=114, JSONB=3802, UUID=2950
  match type_oid {
    16 => parse_bool(text)
    21 | 23 => parse_int(text)
    20 => parse_int64(text)
    700 | 701 | 1700 => parse_float(text)
    17 => parse_bytea(text)
    1082 => Date(text)
    1083 | 1266 => Time(text)
    1114 => Timestamp(text)
    1184 => TimestampTz(text)
    1186 => Interval(text)
    114 | 3802 => Json(text)
    2950 => Uuid(text)
    _ => String(text)
  }
}

///|
/// Parse boolean value
fn parse_bool(text : String) -> Value {
  if text == "t" || text == "true" || text == "TRUE" || text == "1" {
    Bool(true)
  } else if text == "f" || text == "false" || text == "FALSE" || text == "0" {
    Bool(false)
  } else {
    String(text)
  }
}

///|
/// Parse integer value
fn parse_int(text : String) -> Value {
  let mut result = 0
  let mut negative = false
  let mut started = false
  for c in text {
    if c == '-' && not(started) {
      negative = true
      started = true
    } else if c >= '0' && c <= '9' {
      let digit = c.to_int() - '0'.to_int()
      // Overflow guard: max_int is 2147483647
      if result > 214748364 || (result == 214748364 && digit > 7) {
        return String(text)
      }
      result = result * 10 + digit
      started = true
    } else if c == '+' && not(started) {
      started = true
    } else {
      return String(text) // invalid character
    }
  }
  if not(started) {
    return String(text)
  }
  Int(if negative { -result } else { result })
}

///|
/// Parse 64-bit integer value
fn parse_int64(text : String) -> Value {
  let mut result : Int64 = 0L
  let mut negative = false
  let mut started = false
  for c in text {
    if c == '-' && not(started) {
      negative = true
      started = true
    } else if c >= '0' && c <= '9' {
      let digit = (c.to_int() - '0'.to_int()).to_int64()
      // Overflow guard: max_int64 is 9223372036854775807
      if result > 922337203685477580L ||
        (result == 922337203685477580L && digit > 7L) {
        return String(text)
      }
      result = result * 10L + digit
      started = true
    } else if c == '+' && not(started) {
      started = true
    } else {
      return String(text) // invalid character
    }
  }
  if not(started) {
    return String(text)
  }
  Int64(if negative { -result } else { result })
}

///|
/// Parse floating point value
fn parse_float(text : String) -> Value {
  // Handle PostgreSQL-specific special values not in @strconv
  if text == "nan" {
    return Float(0.0 / 0.0)
  }
  if text == "inf" {
    return Float(1.0 / 0.0)
  }
  if text == "-inf" {
    return Float(-1.0 / 0.0)
  }
  try {
    Float(@strconv.parse_double(text[:]))
  } catch {
    _ => String(text)
  }
}

///|
/// Parse bytea value (hex format: \x...)
fn parse_bytea(text : String) -> Value {
  if text.length() >= 2 {
    // Check for hex format: \xHEXHEX...
    let bytes = @utf8.encode(text[:])
    if bytes[0] == b'\\' && bytes[1] == b'x' {
      // Extract hex part (skip first 2 characters)
      let hex_str = substring_from(text, 2)
      match hex_decode(hex_str) {
        Some(decoded) => Bytes(decoded)
        None => String(text)
      }
    } else {
      // Escape format - simplified handling
      Bytes(bytes)
    }
  } else {
    Bytes(@utf8.encode(text[:]))
  }
}

///|
/// Get substring starting from given index
fn substring_from(s : String, start : Int) -> String {
  let chars : Array[Char] = []
  let mut idx = 0
  for c in s {
    if idx >= start {
      chars.push(c)
    }
    idx += 1
  }
  String::from_array(chars)
}

///|
/// Decode hex string to bytes
fn hex_decode(hex : String) -> Bytes? {
  let hex_bytes = @utf8.encode(hex[:])
  if hex_bytes.length() % 2 != 0 {
    return None
  }

  let result : Array[Byte] = []
  for i = 0; i < hex_bytes.length(); i = i + 2 {
    let high = hex_digit_value(hex_bytes[i])
    let low = hex_digit_value(hex_bytes[i + 1])
    match (high, low) {
      (Some(h), Some(l)) => result.push(((h << 4) | l).to_byte())
      _ => return None
    }
  }
  Some(Bytes::from_array(result))
}

///|
/// Get numeric value of hex digit
fn hex_digit_value(b : Byte) -> Int? {
  if b >= b'0' && b <= b'9' {
    Some(b.to_int() - b'0'.to_int())
  } else if b >= b'a' && b <= b'f' {
    Some(b.to_int() - b'a'.to_int() + 10)
  } else if b >= b'A' && b <= b'F' {
    Some(b.to_int() - b'A'.to_int() + 10)
  } else {
    None
  }
}

// =============================================================================
// Text Format Serialization (MoonBit -> PostgreSQL)
// =============================================================================

///|
/// Serialize a Value to PostgreSQL text format
/// Returns None for Null values
pub fn serialize_value(value : Value) -> Bytes? {
  match value {
    Null => None
    Bool(b) => {
      let s = if b { "t" } else { "f" }
      Some(@utf8.encode(s[:]))
    }
    Int(n) => Some(@utf8.encode(n.to_string()[:]))
    Int64(n) => Some(@utf8.encode(n.to_string()[:]))
    Float(n) => Some(@utf8.encode(n.to_string()[:]))
    String(s) => Some(@utf8.encode(s[:]))
    Bytes(b) => Some(bytea_to_hex(b))
    Date(s)
    | Time(s)
    | Timestamp(s)
    | TimestampTz(s)
    | Interval(s)
    | Json(s)
    | Uuid(s) => Some(@utf8.encode(s[:]))
  }
}

///|
/// Convert bytes to hex-encoded bytea format
fn bytea_to_hex(data : Bytes) -> Bytes {
  let result : Array[Byte] = []
  result.push(b'\\')
  result.push(b'x')
  for i = 0; i < data.length(); i = i + 1 {
    let b = data[i].to_int()
    result.push(hex_byte((b >> 4) & 0xF))
    result.push(hex_byte(b & 0xF))
  }
  Bytes::from_array(result)
}

