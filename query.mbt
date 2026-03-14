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
/// Build a column-name-to-index map from column metadata.
/// Compute once per result set and share across all rows.
fn build_column_index(fields : Array[ColumnInfo]) -> Map[String, Int] {
  let index : Map[String, Int] = {}
  fields.eachi(fn(i, f) { index[f.name] = i })
  index
}

///|
/// Create a new Row with a precomputed column index
fn Row::new(
  values : Array[Value],
  fields : Array[ColumnInfo],
  column_index : Map[String, Int],
) -> Row {
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
  self.get(index).bind(Value::as_string)
}

///|
/// Value as Int at index
pub fn Row::int(self : Row, index : Int) -> Int? {
  self.get(index).bind(Value::as_int)
}

///|
/// Value as Int64 at index
pub fn Row::int64(self : Row, index : Int) -> Int64? {
  self.get(index).bind(Value::as_int64)
}

///|
/// Value as Double at index
pub fn Row::float(self : Row, index : Int) -> Double? {
  self.get(index).bind(Value::as_float)
}

///|
/// Value as Bool at index
pub fn Row::bool(self : Row, index : Int) -> Bool? {
  self.get(index).bind(Value::as_bool)
}

///|
/// Check if value at index is null
pub fn Row::is_null(self : Row, index : Int) -> Bool {
  self.get(index).map(Value::is_null).unwrap_or(false)
}

///|
/// Value as Date string at index
pub fn Row::date(self : Row, index : Int) -> String? {
  self.get(index).bind(Value::as_date)
}

///|
/// Value as Time string at index
pub fn Row::time(self : Row, index : Int) -> String? {
  self.get(index).bind(Value::as_time)
}

///|
/// Value as Timestamp string at index
pub fn Row::timestamp(self : Row, index : Int) -> String? {
  self.get(index).bind(Value::as_timestamp)
}

///|
/// Value as JSON string at index
pub fn Row::json(self : Row, index : Int) -> String? {
  self.get(index).bind(Value::as_json)
}

///|
/// Value as UUID string at index
pub fn Row::uuid(self : Row, index : Int) -> String? {
  self.get(index).bind(Value::as_uuid)
}
