///|
/// Unit tests for query result types (white-box)
test "parse_affected_rows INSERT" {
  inspect(parse_affected_rows("INSERT 0 1"), content="1")
}

///|
test "parse_affected_rows UPDATE" {
  inspect(parse_affected_rows("UPDATE 5"), content="5")
}

///|
test "parse_affected_rows DELETE" {
  inspect(parse_affected_rows("DELETE 3"), content="3")
}

///|
test "parse_affected_rows SELECT" {
  inspect(parse_affected_rows("SELECT 10"), content="10")
}

///|
test "parse_affected_rows empty" {
  inspect(parse_affected_rows(""), content="0")
}

///|
test "parse_affected_rows CREATE TABLE" {
  inspect(parse_affected_rows("CREATE TABLE"), content="0")
}

///|
test "split_string basic" {
  inspect(
    split_string("a b c", ' '),
    content=(
      #|["a", "b", "c"]
    ),
  )
}

///|
test "split_string single" {
  inspect(
    split_string("hello", ' '),
    content=(
      #|["hello"]
    ),
  )
}

///|
test "split_string empty" {
  inspect(split_string("", ' '), content="[]")
}

///|
test "split_string multiple spaces" {
  inspect(
    split_string("a  b", ' '),
    content=(
      #|["a", "b"]
    ),
  )
}

///|
test "QueryResult accessors" {
  let cols : Array[ColumnInfo] = [
    { name: "id", type_oid: 23, type_size: 4 },
    { name: "name", type_oid: 25, type_size: -1 },
  ]
  let row = Row::new([Int(1), String("Alice")], cols)
  let result = QueryResult::new(cols, [row], "SELECT 1")
  inspect(result.row_count(), content="1")
  inspect(result.column_count(), content="2")
  inspect(result.get_command_tag(), content="SELECT 1")
  inspect(result.get_row(0) is Some(_), content="true")
  inspect(result.get_row(1), content="None")
  inspect(result.get_row(-1), content="None")
}

///|
test "QueryResult::iter" {
  let cols : Array[ColumnInfo] = [{ name: "x", type_oid: 23, type_size: 4 }]
  let rows = [Row::new([Int(1)], cols), Row::new([Int(2)], cols)]
  let result = QueryResult::new(cols, rows, "SELECT 2")
  let mut sum = 0
  for row in result.iter() {
    sum += row.get_int(0).unwrap_or(0)
  }
  inspect(sum, content="3")
}

///|
test "QueryResult::get_fields" {
  let cols : Array[ColumnInfo] = [{ name: "id", type_oid: 23, type_size: 4 }]
  let result = QueryResult::new(cols, [], "SELECT 0")
  inspect(result.get_fields().length(), content="1")
  inspect(result.get_fields()[0].name, content="id")
}

///|
test "Row::get" {
  let cols : Array[ColumnInfo] = [{ name: "a", type_oid: 25, type_size: -1 }]
  let row = Row::new([String("hello")], cols)
  inspect(
    row.get(0),
    content=(
      #|Some(String("hello"))
    ),
  )
  inspect(row.get(1), content="None")
  inspect(row.get(-1), content="None")
}

///|
test "Row::get_by_name" {
  let cols : Array[ColumnInfo] = [
    { name: "id", type_oid: 23, type_size: 4 },
    { name: "name", type_oid: 25, type_size: -1 },
  ]
  let row = Row::new([Int(1), String("Bob")], cols)
  inspect(
    row.get_by_name("name"),
    content=(
      #|Some(String("Bob"))
    ),
  )
  inspect(row.get_by_name("id"), content="Some(Int(1))")
  inspect(row.get_by_name("missing"), content="None")
}

///|
test "Row::get_string" {
  let cols : Array[ColumnInfo] = [{ name: "s", type_oid: 25, type_size: -1 }]
  let row = Row::new([String("hello")], cols)
  inspect(
    row.get_string(0),
    content=(
      #|Some("hello")
    ),
  )
  inspect(row.get_string(1), content="None")
}

///|
test "Row::get_int" {
  let cols : Array[ColumnInfo] = [{ name: "n", type_oid: 23, type_size: 4 }]
  let row = Row::new([Int(42)], cols)
  inspect(row.get_int(0), content="Some(42)")
  inspect(row.get_int(1), content="None")
}

///|
test "Row::get_int64" {
  let cols : Array[ColumnInfo] = [{ name: "n", type_oid: 20, type_size: 8 }]
  let row = Row::new([Int64(9999999999L)], cols)
  inspect(row.get_int64(0), content="Some(9999999999)")
}

///|
test "Row::get_float" {
  let cols : Array[ColumnInfo] = [{ name: "f", type_oid: 701, type_size: 8 }]
  let row = Row::new([Float(3.14)], cols)
  inspect(row.get_float(0), content="Some(3.14)")
}

///|
test "Row::get_bool" {
  let cols : Array[ColumnInfo] = [{ name: "b", type_oid: 16, type_size: 1 }]
  let row = Row::new([Bool(true)], cols)
  inspect(row.get_bool(0), content="Some(true)")
}

///|
test "Row::is_null" {
  let cols : Array[ColumnInfo] = [
    { name: "a", type_oid: 25, type_size: -1 },
    { name: "b", type_oid: 25, type_size: -1 },
  ]
  let row = Row::new([Null, String("ok")], cols)
  inspect(row.is_null(0), content="true")
  inspect(row.is_null(1), content="false")
  inspect(row.is_null(99), content="false") // out of bounds is not null
}

///|
test "Row::column_count" {
  let cols : Array[ColumnInfo] = [
    { name: "a", type_oid: 25, type_size: -1 },
    { name: "b", type_oid: 23, type_size: 4 },
  ]
  let row = Row::new([String("x"), Int(1)], cols)
  inspect(row.column_count(), content="2")
}
