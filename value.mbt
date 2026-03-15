///| User-Facing Value Types
///
/// Public types that wrap internal protocol types so end-users
/// never need to import the protocol package directly.

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

///|
/// Check if value is null
pub fn Value::is_null(self : Value) -> Bool {
  self is Null
}

///|
/// Get value as Bool
pub fn Value::as_bool(self : Value) -> Bool? {
  match self {
    Bool(b) => Some(b)
    _ => None
  }
}

///|
/// Get value as Int (exact match only)
pub fn Value::as_int(self : Value) -> Int? {
  match self {
    Int(n) => Some(n)
    _ => None
  }
}

///|
/// Get value as Int64 (widens Int losslessly)
pub fn Value::as_int64(self : Value) -> Int64? {
  match self {
    Int(n) => Some(n.to_int64())
    Int64(n) => Some(n)
    _ => None
  }
}

///|
/// Get value as Double (widens Int losslessly)
pub fn Value::as_float(self : Value) -> Double? {
  match self {
    Int(n) => Some(n.to_double())
    Float(n) => Some(n)
    _ => None
  }
}

///|
/// Get value as String (converts all non-Null types)
pub fn Value::as_string(self : Value) -> String? {
  match self {
    Null => None
    Bool(b) => Some(if b { "true" } else { "false" })
    Int(n) => Some(n.to_string())
    Int64(n) => Some(n.to_string())
    Float(n) => Some(n.to_string())
    String(s) => Some(s)
    Bytes(_) => None
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
/// Get value as Bytes
pub fn Value::as_bytes(self : Value) -> Bytes? {
  match self {
    Bytes(b) => Some(b)
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
/// Get value as Timestamp string (accepts both Timestamp and TimestampTz)
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

///|
/// Simplified column metadata exposed to end-users
struct ColumnInfo {
  /// Column name
  name : String
  /// PostgreSQL type OID
  type_oid : UInt
  /// Data type size (negative for variable-width)
  type_size : Int
} derive(Show, Eq)

///|
/// Create a new ColumnInfo
fn ColumnInfo::new(
  name : String,
  type_oid : UInt,
  type_size : Int,
) -> ColumnInfo {
  { name, type_oid, type_size }
}

///|
/// Column name
pub fn ColumnInfo::name(self : ColumnInfo) -> String {
  self.name
}

///|
/// Type OID
pub fn ColumnInfo::type_oid(self : ColumnInfo) -> UInt {
  self.type_oid
}

///|
/// Type size
pub fn ColumnInfo::type_size(self : ColumnInfo) -> Int {
  self.type_size
}

///|
/// Convert FieldDescription to user-facing ColumnInfo
fn column_info_from_field(fd : FieldDescription) -> ColumnInfo {
  ColumnInfo::new(fd.name(), fd.type_oid(), fd.type_size())
}

///|
/// Transaction status indicator
pub(all) enum TransactionStatus {
  /// Not in a transaction block
  Idle
  /// In a transaction block
  InTransaction
  /// In a failed transaction block
  Failed
} derive(Show, Eq)
