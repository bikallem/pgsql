///| Query Results
///
/// Types for representing PostgreSQL query results.

/// Result of a query execution
pub struct QueryResult {
  /// Column descriptions
  fields : Array[@protocol.FieldDescription]
  /// Result rows
  rows : Array[Row]
  /// Command tag (e.g., "SELECT 5", "INSERT 0 1")
  command_tag : String
} derive(Show)

/// A single row of query results
pub struct Row {
  /// Column values
  values : Array[@protocol.Value]
  /// Reference to field descriptions
  fields : Array[@protocol.FieldDescription]
} derive(Show)

/// Create a new QueryResult
pub fn QueryResult::new(
  fields : Array[@protocol.FieldDescription],
  rows : Array[Row],
  command_tag : String
) -> QueryResult {
  { fields, rows, command_tag }
}

/// Get field descriptions
pub fn QueryResult::get_fields(self : QueryResult) -> Array[@protocol.FieldDescription] {
  self.fields
}

/// Get rows
pub fn QueryResult::get_rows(self : QueryResult) -> Array[Row] {
  self.rows
}

/// Get command tag
pub fn QueryResult::get_command_tag(self : QueryResult) -> String {
  self.command_tag
}

/// Get row count
pub fn QueryResult::row_count(self : QueryResult) -> Int {
  self.rows.length()
}

/// Get column count
pub fn QueryResult::column_count(self : QueryResult) -> Int {
  self.fields.length()
}

/// Get a row by index
pub fn QueryResult::get_row(self : QueryResult, index : Int) -> Row? {
  if index >= 0 && index < self.rows.length() {
    Some(self.rows[index])
  } else {
    None
  }
}

/// Iterator over rows
pub fn QueryResult::iter(self : QueryResult) -> Iter[Row] {
  self.rows.iter()
}

// =============================================================================
// Row Methods
// =============================================================================

/// Create a new Row
pub fn Row::new(
  values : Array[@protocol.Value],
  fields : Array[@protocol.FieldDescription]
) -> Row {
  { values, fields }
}

/// Get column count
pub fn Row::column_count(self : Row) -> Int {
  self.values.length()
}

/// Get value at index
pub fn Row::get(self : Row, index : Int) -> @protocol.Value? {
  if index >= 0 && index < self.values.length() {
    Some(self.values[index])
  } else {
    None
  }
}

/// Get value by column name
pub fn Row::get_by_name(self : Row, name : String) -> @protocol.Value? {
  for i = 0; i < self.fields.length(); i = i + 1 {
    if self.fields[i].name == name {
      return Some(self.values[i])
    }
  }
  None
}

/// Get value as String at index
pub fn Row::get_string(self : Row, index : Int) -> String? {
  match self.get(index) {
    Some(v) => v.as_string()
    None => None
  }
}

/// Get value as Int at index
pub fn Row::get_int(self : Row, index : Int) -> Int? {
  match self.get(index) {
    Some(v) => v.as_int()
    None => None
  }
}

/// Get value as Int64 at index
pub fn Row::get_int64(self : Row, index : Int) -> Int64? {
  match self.get(index) {
    Some(v) => v.as_int64()
    None => None
  }
}

/// Get value as Double at index
pub fn Row::get_float(self : Row, index : Int) -> Double? {
  match self.get(index) {
    Some(v) => v.as_float()
    None => None
  }
}

/// Get value as Bool at index
pub fn Row::get_bool(self : Row, index : Int) -> Bool? {
  match self.get(index) {
    Some(v) => v.as_bool()
    None => None
  }
}

/// Check if value at index is null
pub fn Row::is_null(self : Row, index : Int) -> Bool {
  match self.get(index) {
    Some(v) => v.is_null()
    None => true
  }
}
