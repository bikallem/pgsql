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
test "parse_affected_rows COPY" {
  inspect(parse_affected_rows("COPY 100"), content="100")
}

///|
test "parse_affected_rows zero rows" {
  inspect(parse_affected_rows("DELETE 0"), content="0")
}


///|
/// Helper to create a Row in tests (computes column_index automatically)
fn test_row(values : Array[Value], cols : Array[ColumnInfo]) -> Row {
  Row::new(values, cols, build_column_index(cols))
}

///|
test "QueryResult accessors" {
  let cols : Array[ColumnInfo] = [
    { name: "id", type_oid: 23, type_size: 4 },
    { name: "name", type_oid: 25, type_size: -1 },
  ]
  let row = test_row([Int(1), String("Alice")], cols)
  let result = QueryResult::new(cols, [row], "SELECT 1")
  inspect(result.row_count(), content="1")
  inspect(result.column_count(), content="2")
  inspect(result.command_tag(), content="SELECT 1")
  inspect(result.row(0) is Some(_), content="true")
  inspect(result.row(1), content="None")
  inspect(result.row(-1), content="None")
}

///|
test "QueryResult::iter" {
  let cols : Array[ColumnInfo] = [{ name: "x", type_oid: 23, type_size: 4 }]
  let rows = [test_row([Int(1)], cols), test_row([Int(2)], cols)]
  let result = QueryResult::new(cols, rows, "SELECT 2")
  let mut sum = 0
  for row in result.iter() {
    sum += row.int(0).unwrap_or(0)
  }
  inspect(sum, content="3")
}

///|
test "QueryResult::get_fields" {
  let cols : Array[ColumnInfo] = [{ name: "id", type_oid: 23, type_size: 4 }]
  let result = QueryResult::new(cols, [], "SELECT 0")
  inspect(result.fields().length(), content="1")
  inspect(result.fields()[0].name, content="id")
}

///|
test "Row::get" {
  let cols : Array[ColumnInfo] = [{ name: "a", type_oid: 25, type_size: -1 }]
  let row = test_row([String("hello")], cols)
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
  let row = test_row([Int(1), String("Bob")], cols)
  inspect(
    row.by_name("name"),
    content=(
      #|Some(String("Bob"))
    ),
  )
  inspect(row.by_name("id"), content="Some(Int(1))")
  inspect(row.by_name("missing"), content="None")
}

///|
test "Row::get_string" {
  let cols : Array[ColumnInfo] = [{ name: "s", type_oid: 25, type_size: -1 }]
  let row = test_row([String("hello")], cols)
  inspect(
    row.string(0),
    content=(
      #|Some("hello")
    ),
  )
  inspect(row.string(1), content="None")
}

///|
test "Row::get_int" {
  let cols : Array[ColumnInfo] = [{ name: "n", type_oid: 23, type_size: 4 }]
  let row = test_row([Int(42)], cols)
  inspect(row.int(0), content="Some(42)")
  inspect(row.int(1), content="None")
}

///|
test "Row::get_int64" {
  let cols : Array[ColumnInfo] = [{ name: "n", type_oid: 20, type_size: 8 }]
  let row = test_row([Int64(9999999999L)], cols)
  inspect(row.int64(0), content="Some(9999999999)")
}

///|
test "Row::get_float" {
  let cols : Array[ColumnInfo] = [{ name: "f", type_oid: 701, type_size: 8 }]
  let row = test_row([Float(3.14)], cols)
  inspect(row.float(0), content="Some(3.14)")
}

///|
test "Row::get_bool" {
  let cols : Array[ColumnInfo] = [{ name: "b", type_oid: 16, type_size: 1 }]
  let row = test_row([Bool(true)], cols)
  inspect(row.bool(0), content="Some(true)")
}

///|
test "Row::is_null" {
  let cols : Array[ColumnInfo] = [
    { name: "a", type_oid: 25, type_size: -1 },
    { name: "b", type_oid: 25, type_size: -1 },
  ]
  let row = test_row([Null, String("ok")], cols)
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
  let row = test_row([String("x"), Int(1)], cols)
  inspect(row.column_count(), content="2")
}

///|
test "build_query_result with rows" {
  let messages : Array[@protocol.BackendMessage] = [
    @protocol.RowDescription([
      @protocol.FieldDescription::new("id", 0, 0, 23, 4, -1, @protocol.Text),
      @protocol.FieldDescription::new("name", 0, 0, 25, -1, -1, @protocol.Text),
    ]),
    @protocol.DataRow([
      Some(Bytes::from_array([b'1'])),
      Some(Bytes::from_array([b'A', b'l', b'i', b'c', b'e'])),
    ]),
    @protocol.DataRow([
      Some(Bytes::from_array([b'2'])),
      Some(Bytes::from_array([b'B', b'o', b'b'])),
    ]),
    @protocol.CommandComplete("SELECT 2"),
    @protocol.ReadyForQuery(@protocol.Idle),
  ]
  let result = build_query_result(messages)
  inspect(result.row_count(), content="2")
  inspect(result.column_count(), content="2")
  inspect(result.command_tag(), content="SELECT 2")
  inspect(result.row(0).unwrap().int(0), content="Some(1)")
  inspect(
    result.row(0).unwrap().string(1),
    content=(
      #|Some("Alice")
    ),
  )
  inspect(
    result.row(1).unwrap().string(1),
    content=(
      #|Some("Bob")
    ),
  )
}

///|
test "build_query_result empty" {
  let messages : Array[@protocol.BackendMessage] = [
    @protocol.EmptyQueryResponse,
    @protocol.ReadyForQuery(@protocol.Idle),
  ]
  let result = build_query_result(messages)
  inspect(result.row_count(), content="0")
  inspect(result.column_count(), content="0")
}

///|
test "build_query_result command only" {
  let messages : Array[@protocol.BackendMessage] = [
    @protocol.CommandComplete("INSERT 0 3"),
    @protocol.ReadyForQuery(@protocol.Idle),
  ]
  let result = build_query_result(messages)
  inspect(result.row_count(), content="0")
  inspect(result.command_tag(), content="INSERT 0 3")
}

///|
test "convert_row_values null column" {
  let columns = [ColumnInfo::new("a", 25, -1), ColumnInfo::new("b", 23, 4)]
  let raw : Array[Bytes?] = [None, Some(Bytes::from_array([b'4', b'2']))]
  let values = convert_row_values(raw, columns)
  inspect(values[0], content="Null")
  inspect(values[1], content="Int(42)")
}

///|
test "serialize_params mixed types" {
  let params : Array[Value] = [Int(42), String("hello"), Null, Bool(true)]
  let result = serialize_params(params)
  inspect(result.length(), content="4")
  inspect(result[2], content="None") // Null serializes to None
  inspect(result[0] is Some(_), content="true")
  inspect(result[1] is Some(_), content="true")
  inspect(result[3] is Some(_), content="true")
}


///|
test "build_column_index maps names to indices" {
  let cols : Array[ColumnInfo] = [
    { name: "id", type_oid: 23, type_size: 4 },
    { name: "name", type_oid: 25, type_size: -1 },
    { name: "email", type_oid: 25, type_size: -1 },
  ]
  let index = build_column_index(cols)
  inspect(index.get("id"), content="Some(0)")
  inspect(index.get("name"), content="Some(1)")
  inspect(index.get("email"), content="Some(2)")
  inspect(index.get("missing"), content="None")
}

///|
test "build_column_index empty" {
  let index = build_column_index([])
  inspect(index.get("anything"), content="None")
}

///|
test "build_column_index duplicate names uses last index" {
  let cols : Array[ColumnInfo] = [
    { name: "x", type_oid: 23, type_size: 4 },
    { name: "x", type_oid: 25, type_size: -1 },
  ]
  let index = build_column_index(cols)
  inspect(index.get("x"), content="Some(1)")
}

///|
test "parse_affected_rows large number" {
  inspect(parse_affected_rows("INSERT 0 1000000"), content="1000000")
}

///|
test "quote_identifier" {
  inspect(
    quote_identifier("simple"),
    content=(
      #|"simple"
    ),
  )
  inspect(
    quote_identifier("has\"quote"),
    content=(
      #|"has""quote"
    ),
  )
  inspect(
    quote_identifier(""),
    content=(
      #|""
    ),
  )
}
