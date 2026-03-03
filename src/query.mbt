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
/// Column info
pub fn QueryResult::fields(self : QueryResult) -> Array[ColumnInfo] {
  self.fields
}

///|
/// Rows
pub fn QueryResult::rows(self : QueryResult) -> Array[Row] {
  self.rows
}

///|
/// Command tag
pub fn QueryResult::command_tag(self : QueryResult) -> String {
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
/// Row by index
pub fn QueryResult::row(self : QueryResult, index : Int) -> Row? {
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
/// Value by column name (O(1) via precomputed index)
pub fn Row::by_name(self : Row, name : String) -> Value? {
  match self.column_index.get(name) {
    Some(i) => Some(self.values[i])
    None => None
  }
}

///|
/// Value as String at index
pub fn Row::string(self : Row, index : Int) -> String? {
  match self.get(index) {
    Some(v) => v.as_string()
    None => None
  }
}

///|
/// Value as Int at index
pub fn Row::int(self : Row, index : Int) -> Int? {
  match self.get(index) {
    Some(v) => v.as_int()
    None => None
  }
}

///|
/// Value as Int64 at index
pub fn Row::int64(self : Row, index : Int) -> Int64? {
  match self.get(index) {
    Some(v) => v.as_int64()
    None => None
  }
}

///|
/// Value as Double at index
pub fn Row::float(self : Row, index : Int) -> Double? {
  match self.get(index) {
    Some(v) => v.as_float()
    None => None
  }
}

///|
/// Value as Bool at index
pub fn Row::bool(self : Row, index : Int) -> Bool? {
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
