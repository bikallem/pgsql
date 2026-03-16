///|
/// Unit tests for Value types
test "Value::is_null" {
  inspect(@pgsql.Null.is_null(), content="true")
  inspect(@pgsql.Int(0).is_null(), content="false")
  inspect(@pgsql.String("").is_null(), content="false")
  inspect(@pgsql.Bool(false).is_null(), content="false")
}

///|
test "Value::as_bool" {
  inspect(@pgsql.Bool(true).as_bool(), content="Some(true)")
  inspect(@pgsql.Bool(false).as_bool(), content="Some(false)")
  inspect(@pgsql.Int(1).as_bool(), content="None")
  inspect(@pgsql.Null.as_bool(), content="None")
  inspect(@pgsql.String("true").as_bool(), content="None")
}

///|
test "Value::as_int" {
  inspect(@pgsql.Int(42).as_int(), content="Some(42)")
  inspect(@pgsql.Int(-7).as_int(), content="Some(-7)")
  // No lossy coercions — Int64 and Float return None
  inspect(@pgsql.Int64(100L).as_int(), content="None")
  inspect(@pgsql.Float(3.9).as_int(), content="None")
  inspect(@pgsql.Null.as_int(), content="None")
  inspect(@pgsql.String("42").as_int(), content="None")
  inspect(@pgsql.Bool(true).as_int(), content="None")
}

///|
test "Value::as_int64" {
  inspect(@pgsql.Int64(9999999999L).as_int64(), content="Some(9999999999)")
  inspect(@pgsql.Int(42).as_int64(), content="Some(42)")
  // No lossy coercion — Float returns None
  inspect(@pgsql.Float(2.5).as_int64(), content="None")
  inspect(@pgsql.Null.as_int64(), content="None")
  inspect(@pgsql.String("0").as_int64(), content="None")
}

///|
test "Value::as_float" {
  inspect(@pgsql.Float(3.14).as_float(), content="Some(3.14)")
  inspect(@pgsql.Int(10).as_float(), content="Some(10)")
  // No lossy coercion — Int64 returns None (precision loss for large values)
  inspect(@pgsql.Int64(100L).as_float(), content="None")
  inspect(@pgsql.Null.as_float(), content="None")
  inspect(@pgsql.String("1.0").as_float(), content="None")
}

///|
test "Value::as_string" {
  inspect(
    @pgsql.String("hello").as_string(),
    content=(
      #|Some("hello")
    ),
  )
  inspect(
    @pgsql.String("").as_string(),
    content=(
      #|Some("")
    ),
  )
  inspect(
    @pgsql.Int(42).as_string(),
    content=(
      #|Some("42")
    ),
  )
  inspect(
    @pgsql.Int64(100L).as_string(),
    content=(
      #|Some("100")
    ),
  )
  inspect(
    @pgsql.Float(1.5).as_string(),
    content=(
      #|Some("1.5")
    ),
  )
  inspect(
    @pgsql.Bool(true).as_string(),
    content=(
      #|Some("true")
    ),
  )
  inspect(
    @pgsql.Bool(false).as_string(),
    content=(
      #|Some("false")
    ),
  )
  inspect(@pgsql.Null.as_string(), content="None")
}

///|
test "Value::as_bytes" {
  let b = Bytes::from_array([b'\x01', b'\x02'])
  inspect(@pgsql.Bytes(b).as_bytes() is Some(_), content="true")
  inspect(@pgsql.Null.as_bytes(), content="None")
  inspect(@pgsql.String("hi").as_bytes(), content="None")
  inspect(@pgsql.Int(1).as_bytes(), content="None")
}

///|
test "Value::equality" {
  inspect(@pgsql.Int(42) == @pgsql.Int(42), content="true")
  inspect(@pgsql.Int(42) == @pgsql.Int(43), content="false")
  inspect(@pgsql.Null == @pgsql.Null, content="true")
  inspect(@pgsql.String("a") == @pgsql.String("a"), content="true")
  inspect(@pgsql.Bool(true) == @pgsql.Bool(true), content="true")
}

///|
test "Value::as_date" {
  inspect(
    @pgsql.Date("2024-03-15").as_date(),
    content=(
      #|Some("2024-03-15")
    ),
  )
  inspect(@pgsql.String("2024-03-15").as_date(), content="None")
  inspect(@pgsql.Null.as_date(), content="None")
}

///|
test "Value::as_time" {
  inspect(
    @pgsql.Time("14:30:00").as_time(),
    content=(
      #|Some("14:30:00")
    ),
  )
  inspect(@pgsql.Null.as_time(), content="None")
}

///|
test "Value::as_timestamp" {
  inspect(
    @pgsql.Timestamp("2024-03-15 14:30:00").as_timestamp(),
    content=(
      #|Some("2024-03-15 14:30:00")
    ),
  )
  inspect(
    @pgsql.TimestampTz("2024-03-15 14:30:00+00").as_timestamp(),
    content=(
      #|Some("2024-03-15 14:30:00+00")
    ),
  )
  inspect(@pgsql.Null.as_timestamp(), content="None")
}

///|
test "Value::as_json" {
  inspect(
    @pgsql.Json("{\"key\":\"val\"}").as_json(),
    content=(
      #|Some("{\"key\":\"val\"}")
    ),
  )
  inspect(@pgsql.String("{\"key\":\"val\"}").as_json(), content="None")
  inspect(@pgsql.Null.as_json(), content="None")
}

///|
test "Value::as_uuid" {
  inspect(
    @pgsql.Uuid("550e8400-e29b-41d4-a716-446655440000").as_uuid(),
    content=(
      #|Some("550e8400-e29b-41d4-a716-446655440000")
    ),
  )
  inspect(@pgsql.Null.as_uuid(), content="None")
}

///|
test "Value::as_string with new types" {
  inspect(
    @pgsql.Date("2024-03-15").as_string(),
    content=(
      #|Some("2024-03-15")
    ),
  )
  inspect(
    @pgsql.Json("{\"a\":1}").as_string(),
    content=(
      #|Some("{\"a\":1}")
    ),
  )
  inspect(
    @pgsql.Uuid("abc-def").as_string(),
    content=(
      #|Some("abc-def")
    ),
  )
}

///|
test "TransactionStatus::equality" {
  inspect(@pgsql.Idle == @pgsql.Idle, content="true")
  inspect(@pgsql.InTransaction == @pgsql.InTransaction, content="true")
  inspect(@pgsql.Failed == @pgsql.Failed, content="true")
  inspect(
    (@pgsql.Idle : @pgsql.TransactionStatus) == @pgsql.InTransaction,
    content="false",
  )
}
