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
} derive(Show, Eq)

///|
/// Check if value is null
pub fn Value::is_null(self : Value) -> Bool {
  match self {
    Null => true
    _ => false
  }
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
/// Get value as Int (coerces Int64 and Float)
pub fn Value::as_int(self : Value) -> Int? {
  match self {
    Int(n) => Some(n)
    Int64(n) => Some(n.to_int())
    Float(n) => Some(n.to_int())
    _ => None
  }
}

///|
/// Get value as Int64 (coerces Int and Float)
pub fn Value::as_int64(self : Value) -> Int64? {
  match self {
    Int(n) => Some(n.to_int64())
    Int64(n) => Some(n)
    Float(n) => Some(n.to_int64())
    _ => None
  }
}

///|
/// Get value as Double (coerces Int and Int64)
pub fn Value::as_float(self : Value) -> Double? {
  match self {
    Int(n) => Some(n.to_double())
    Int64(n) => Some(n.to_double())
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
/// Simplified column metadata exposed to end-users
pub struct ColumnInfo {
  /// Column name
  name : String
  /// PostgreSQL type OID
  type_oid : UInt
  /// Data type size (negative for variable-width)
  type_size : Int
} derive(Show, Eq)

///|
/// Create a new ColumnInfo
pub fn ColumnInfo::new(
  name : String,
  type_oid : UInt,
  type_size : Int,
) -> ColumnInfo {
  { name, type_oid, type_size }
}

///|
/// Get column name
pub fn ColumnInfo::get_name(self : ColumnInfo) -> String {
  self.name
}

///|
/// Get type OID
pub fn ColumnInfo::get_type_oid(self : ColumnInfo) -> UInt {
  self.type_oid
}

///|
/// Get type size
pub fn ColumnInfo::get_type_size(self : ColumnInfo) -> Int {
  self.type_size
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
