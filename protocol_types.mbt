///|
/// PostgreSQL Type System
///
/// This module defines PostgreSQL type OIDs and provides value conversion
/// between MoonBit types and PostgreSQL text format representations.

// =============================================================================
// PostgreSQL Type OIDs
// =============================================================================

// Boolean
const OID_BOOL : UInt = 16

// Numeric Types

///|
const OID_INT2 : UInt = 21 // smallint

///|
const OID_INT4 : UInt = 23 // integer

///|
const OID_INT8 : UInt = 20 // bigint

///|
const OID_FLOAT4 : UInt = 700 // real

///|
const OID_FLOAT8 : UInt = 701 // double precision

///|
const OID_NUMERIC : UInt = 1700 // numeric/decimal

// Character Types

///|
const OID_CHAR : UInt = 18 // "char" (single character)

///|
const OID_NAME : UInt = 19 // name (63 chars)

///|
const OID_TEXT : UInt = 25 // text

///|
const OID_VARCHAR : UInt = 1043 // varchar

///|
const OID_BPCHAR : UInt = 1042 // char(n)

// Binary Types

///|
const OID_BYTEA : UInt = 17 // bytea

// Date/Time Types

///|
const OID_DATE : UInt = 1082

///|
const OID_TIME : UInt = 1083

///|
const OID_TIMESTAMP : UInt = 1114

///|
const OID_TIMESTAMPTZ : UInt = 1184

///|
const OID_TIMETZ : UInt = 1266

///|
const OID_INTERVAL : UInt = 1186

// JSON Types

///|
const OID_JSON : UInt = 114

///|
const OID_JSONB : UInt = 3802

// UUID

///|
const OID_UUID : UInt = 2950

// =============================================================================
// Text Format Parsing (PostgreSQL -> MoonBit)
// =============================================================================

///|
/// Parse a PostgreSQL text-format value to a MoonBit Value
/// Returns Null if the input is None (SQL NULL)
fn parse_text_value(data : Bytes?, type_oid : UInt) -> Value {
  match data {
    None => Null
    Some(bytes) => {
      let text = @utf8.decode_lossy(bytes[:])
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
  match text {
    "t" | "true" | "TRUE" | "1" => Bool(true)
    "f" | "false" | "FALSE" | "0" => Bool(false)
    _ => String(text)
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
  Float(@strconv.parse_double(text[:])) catch {
    _ => String(text)
  }
}

///|
/// Parse bytea value (hex format: \x...)
fn parse_bytea(text : String) -> Value {
  let bytes = @utf8.encode(text[:])
  if bytes.length() >= 2 && bytes[0] == b'\\' && bytes[1] == b'x' {
    // Hex format: \xHEXHEX... — decode directly from bytes, skipping prefix
    match hex_decode_bytes(bytes, start=2) {
      Some(decoded) => Bytes(decoded)
      None => String(text)
    }
  } else {
    Bytes(bytes)
  }
}

///|
/// Decode hex bytes to binary, starting from the given offset
fn hex_decode_bytes(hex_bytes : Bytes, start? : Int = 0) -> Bytes? {
  let len = hex_bytes.length() - start
  if len % 2 != 0 {
    return None
  }
  let result : Array[Byte] = Array::new(capacity=len / 2)
  for i = start; i < hex_bytes.length(); i = i + 2 {
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
fn serialize_value(value : Value) -> Bytes? {
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
