///| Query Results
///
/// Types for representing PostgreSQL query results.

///|
/// Result of a query execution
struct QueryResult {
  /// Column descriptions
  fields : Array[ColumnInfo]
  /// Result rows
  rows : Array[Row]
  /// Command tag (e.g., "SELECT 5", "INSERT 0 1")
  command_tag : String
} derive(Show)

///|
/// A single row of query results
struct Row {
  /// Column values
  values : Array[Value]
  /// Reference to column info
  fields : Array[ColumnInfo]
  /// Precomputed column-name-to-index map for O(1) lookup
  column_index : Map[String, Int]
} derive(Show)

///|
/// Create a new QueryResult
fn QueryResult::new(
  fields : Array[ColumnInfo],
  rows : Array[Row],
  command_tag : String,
) -> QueryResult {
  { fields, rows, command_tag }
}

///|
/// Get column info
pub fn QueryResult::get_fields(self : QueryResult) -> Array[ColumnInfo] {
  self.fields
}

///|
/// Get rows
pub fn QueryResult::get_rows(self : QueryResult) -> Array[Row] {
  self.rows
}

///|
/// Get command tag
pub fn QueryResult::get_command_tag(self : QueryResult) -> String {
  self.command_tag
}

///|
/// Get row count
pub fn QueryResult::row_count(self : QueryResult) -> Int {
  self.rows.length()
}

///|
/// Get column count
pub fn QueryResult::column_count(self : QueryResult) -> Int {
  self.fields.length()
}

///|
/// Get a row by index
pub fn QueryResult::get_row(self : QueryResult, index : Int) -> Row? {
  if index >= 0 && index < self.rows.length() {
    Some(self.rows[index])
  } else {
    None
  }
}

///|
/// Iterator over rows
pub fn QueryResult::iter(self : QueryResult) -> Iter[Row] {
  self.rows.iter()
}

// =============================================================================
// Row Methods
// =============================================================================

///|
/// Create a new Row
fn Row::new(values : Array[Value], fields : Array[ColumnInfo]) -> Row {
  let column_index : Map[String, Int] = {}
  for i = 0; i < fields.length(); i = i + 1 {
    column_index[fields[i].name] = i
  }
  { values, fields, column_index }
}

///|
/// Get column count
pub fn Row::column_count(self : Row) -> Int {
  self.values.length()
}

///|
/// Get value at index
pub fn Row::get(self : Row, index : Int) -> Value? {
  if index >= 0 && index < self.values.length() {
    Some(self.values[index])
  } else {
    None
  }
}

///|
/// Get value by column name (O(1) via precomputed index)
pub fn Row::get_by_name(self : Row, name : String) -> Value? {
  match self.column_index.get(name) {
    Some(i) => Some(self.values[i])
    None => None
  }
}

///|
/// Get value as String at index
pub fn Row::get_string(self : Row, index : Int) -> String? {
  match self.get(index) {
    Some(v) => v.as_string()
    None => None
  }
}

///|
/// Get value as Int at index
pub fn Row::get_int(self : Row, index : Int) -> Int? {
  match self.get(index) {
    Some(v) => v.as_int()
    None => None
  }
}

///|
/// Get value as Int64 at index
pub fn Row::get_int64(self : Row, index : Int) -> Int64? {
  match self.get(index) {
    Some(v) => v.as_int64()
    None => None
  }
}

///|
/// Get value as Double at index
pub fn Row::get_float(self : Row, index : Int) -> Double? {
  match self.get(index) {
    Some(v) => v.as_float()
    None => None
  }
}

///|
/// Get value as Bool at index
pub fn Row::get_bool(self : Row, index : Int) -> Bool? {
  match self.get(index) {
    Some(v) => v.as_bool()
    None => None
  }
}

///|
/// Check if value at index is null
pub fn Row::is_null(self : Row, index : Int) -> Bool {
  match self.get(index) {
    Some(v) => v.is_null()
    None => false
  }
}
