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
  if type_oid == OID_BOOL {
    parse_bool(text)
  } else if type_oid == OID_INT2 || type_oid == OID_INT4 {
    parse_int(text)
  } else if type_oid == OID_INT8 {
    parse_int64(text)
  } else if type_oid == OID_FLOAT4 ||
    type_oid == OID_FLOAT8 ||
    type_oid == OID_NUMERIC {
    parse_float(text)
  } else if type_oid == OID_BYTEA {
    parse_bytea(text)
  } else if type_oid == OID_DATE {
    Date(text)
  } else if type_oid == OID_TIME || type_oid == OID_TIMETZ {
    Time(text)
  } else if type_oid == OID_TIMESTAMP {
    Timestamp(text)
  } else if type_oid == OID_TIMESTAMPTZ {
    TimestampTz(text)
  } else if type_oid == OID_INTERVAL {
    Interval(text)
  } else if type_oid == OID_JSON || type_oid == OID_JSONB {
    Json(text)
  } else if type_oid == OID_UUID {
    Uuid(text)
  } else {
    // Default: treat as string
    String(text)
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
  // Handle special float values
  if text == "NaN" || text == "nan" {
    return Float(0.0 / 0.0)
  }
  if text == "Infinity" || text == "inf" {
    return Float(1.0 / 0.0)
  }
  if text == "-Infinity" || text == "-inf" {
    return Float(-1.0 / 0.0)
  }
  // Simple float parsing: integer part + optional decimal
  let mut int_part : Double = 0.0
  let mut frac_part : Double = 0.0
  let mut frac_div : Double = 1.0
  let mut negative = false
  let mut in_fraction = false
  let mut started = false
  let mut in_exponent = false
  let mut exp_value = 0
  let mut exp_negative = false

  for c in text {
    if c == '-' && not(started) && not(in_exponent) {
      negative = true
      started = true
    } else if c == '-' && in_exponent {
      exp_negative = true
    } else if c == '+' && not(started) {
      started = true
    } else if c == '+' && in_exponent {
      // skip
      ()
    } else if c == '.' && not(in_fraction) && not(in_exponent) {
      in_fraction = true
      started = true
    } else if (c == 'e' || c == 'E') && not(in_exponent) {
      in_exponent = true
    } else if c >= '0' && c <= '9' {
      if in_exponent {
        exp_value = exp_value * 10 + (c.to_int() - '0'.to_int())
      } else if in_fraction {
        frac_div = frac_div * 10.0
        frac_part = frac_part +
          (c.to_int() - '0'.to_int()).to_double() / frac_div
      } else {
        int_part = int_part * 10.0 + (c.to_int() - '0'.to_int()).to_double()
      }
      started = true
    } else {
      return String(text) // invalid character
    }
  }
  if not(started) {
    return String(text)
  }
  let mut result = int_part + frac_part
  if negative {
    result = -result
  }
  // Apply exponent
  if in_exponent {
    let mut exp_mult : Double = 1.0
    for i = 0; i < exp_value; i = i + 1 {
      exp_mult = exp_mult * 10.0
    }
    if exp_negative {
      result = result / exp_mult
    } else {
      result = result * exp_mult
    }
  }
  Float(result)
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

// =============================================================================
// Value Helper Methods
// =============================================================================

///|
/// Check if value is null
pub fn Value::is_null(self : Value) -> Bool {
  match self {
    Null => true
    _ => false
  }
}

///|
/// Get value as Bool (returns None if not Bool or Null)
pub fn Value::as_bool(self : Value) -> Bool? {
  match self {
    Bool(b) => Some(b)
    _ => None
  }
}

///|
/// Get value as Int (returns None if not numeric or Null)
pub fn Value::as_int(self : Value) -> Int? {
  match self {
    Int(n) => Some(n)
    Int64(n) => Some(n.to_int())
    Float(n) => Some(n.to_int())
    _ => None
  }
}

///|
/// Get value as Int64 (returns None if not numeric or Null)
pub fn Value::as_int64(self : Value) -> Int64? {
  match self {
    Int(n) => Some(n.to_int64())
    Int64(n) => Some(n)
    Float(n) => Some(n.to_int64())
    _ => None
  }
}

///|
/// Get value as Double (returns None if not numeric or Null)
pub fn Value::as_float(self : Value) -> Double? {
  match self {
    Int(n) => Some(n.to_double())
    Int64(n) => Some(n.to_double())
    Float(n) => Some(n)
    _ => None
  }
}

///|
/// Get value as String (returns None if Null, converts other types)
pub fn Value::as_string(self : Value) -> String? {
  match self {
    Null => None
    Bool(b) => Some(if b { "true" } else { "false" })
    Int(n) => Some(n.to_string())
    Int64(n) => Some(n.to_string())
    Float(n) => Some(n.to_string())
    String(s) => Some(s)
    Bytes(b) => Some(bytes_to_ascii_string(b))
    Date(s)
    | Time(s)
    | Timestamp(s)
    | TimestampTz(s)
    | Interval(s)
    | Json(s)
    | Uuid(s) => Some(s)
  }
}

///|
/// Get value as Bytes (returns None if not Bytes or Null)
pub fn Value::as_bytes(self : Value) -> Bytes? {
  match self {
    Bytes(b) => Some(b)
    String(s) => Some(@utf8.encode(s[:]))
    _ => None
  }
}

///|
/// Get value as Date string
pub fn Value::as_date(self : Value) -> String? {
  match self {
    Date(s) => Some(s)
    _ => None
  }
}

///|
/// Get value as Time string
pub fn Value::as_time(self : Value) -> String? {
  match self {
    Time(s) => Some(s)
    _ => None
  }
}

///|
/// Get value as Timestamp string
pub fn Value::as_timestamp(self : Value) -> String? {
  match self {
    Timestamp(s) | TimestampTz(s) => Some(s)
    _ => None
  }
}

///|
/// Get value as Interval string
pub fn Value::as_interval(self : Value) -> String? {
  match self {
    Interval(s) => Some(s)
    _ => None
  }
}

///|
/// Get value as JSON string
pub fn Value::as_json(self : Value) -> String? {
  match self {
    Json(s) => Some(s)
    _ => None
  }
}

///|
/// Get value as UUID string
pub fn Value::as_uuid(self : Value) -> String? {
  match self {
    Uuid(s) => Some(s)
    _ => None
  }
}
