///| Unit tests for Value types

test "Value::is_null" {
  inspect(@pgsql.Null.is_null(), content="true")
  inspect(@pgsql.Int(0).is_null(), content="false")
  inspect(@pgsql.String("").is_null(), content="false")
  inspect(@pgsql.Bool(false).is_null(), content="false")
}

test "Value::as_bool" {
  inspect(@pgsql.Bool(true).as_bool(), content="Some(true)")
  inspect(@pgsql.Bool(false).as_bool(), content="Some(false)")
  inspect(@pgsql.Int(1).as_bool(), content="None")
  inspect(@pgsql.Null.as_bool(), content="None")
  inspect(@pgsql.String("true").as_bool(), content="None")
}

test "Value::as_int" {
  inspect(@pgsql.Int(42).as_int(), content="Some(42)")
  inspect(@pgsql.Int(-7).as_int(), content="Some(-7)")
  inspect(@pgsql.Int64(100L).as_int(), content="Some(100)")
  inspect(@pgsql.Float(3.9).as_int(), content="Some(3)")
  inspect(@pgsql.Null.as_int(), content="None")
  inspect(@pgsql.String("42").as_int(), content="None")
  inspect(@pgsql.Bool(true).as_int(), content="None")
}

test "Value::as_int64" {
  inspect(@pgsql.Int64(9999999999L).as_int64(), content="Some(9999999999)")
  inspect(@pgsql.Int(42).as_int64(), content="Some(42)")
  inspect(@pgsql.Float(2.5).as_int64(), content="Some(2)")
  inspect(@pgsql.Null.as_int64(), content="None")
  inspect(@pgsql.String("0").as_int64(), content="None")
}

test "Value::as_float" {
  inspect(@pgsql.Float(3.14).as_float(), content="Some(3.14)")
  inspect(@pgsql.Int(10).as_float(), content="Some(10)")
  inspect(@pgsql.Int64(100L).as_float(), content="Some(100)")
  inspect(@pgsql.Null.as_float(), content="None")
  inspect(@pgsql.String("1.0").as_float(), content="None")
}

test "Value::as_string" {
  inspect(@pgsql.String("hello").as_string(), content=(
    #|Some("hello")
  ))
  inspect(@pgsql.String("").as_string(), content=(
    #|Some("")
  ))
  inspect(@pgsql.Int(42).as_string(), content=(
    #|Some("42")
  ))
  inspect(@pgsql.Int64(100L).as_string(), content=(
    #|Some("100")
  ))
  inspect(@pgsql.Float(1.5).as_string(), content=(
    #|Some("1.5")
  ))
  inspect(@pgsql.Bool(true).as_string(), content=(
    #|Some("true")
  ))
  inspect(@pgsql.Bool(false).as_string(), content=(
    #|Some("false")
  ))
  inspect(@pgsql.Null.as_string(), content="None")
}

test "Value::as_bytes" {
  let b = Bytes::from_array([b'\x01', b'\x02'])
  inspect(@pgsql.Bytes(b).as_bytes() is Some(_), content="true")
  inspect(@pgsql.Null.as_bytes(), content="None")
  inspect(@pgsql.String("hi").as_bytes(), content="None")
  inspect(@pgsql.Int(1).as_bytes(), content="None")
}

test "Value::equality" {
  inspect(@pgsql.Int(42) == @pgsql.Int(42), content="true")
  inspect(@pgsql.Int(42) == @pgsql.Int(43), content="false")
  inspect(@pgsql.Null == @pgsql.Null, content="true")
  inspect(@pgsql.String("a") == @pgsql.String("a"), content="true")
  inspect(@pgsql.Bool(true) == @pgsql.Bool(true), content="true")
}

test "ColumnInfo::getters" {
  let col = @pgsql.ColumnInfo::new("id", 23, 4)
  inspect(col.get_name(), content="id")
  inspect(col.get_type_oid(), content="23")
  inspect(col.get_type_size(), content="4")
}

test "TransactionStatus::equality" {
  inspect(@pgsql.Idle == @pgsql.Idle, content="true")
  inspect(@pgsql.InTransaction == @pgsql.InTransaction, content="true")
  inspect(@pgsql.Failed == @pgsql.Failed, content="true")
  inspect((@pgsql.Idle : @pgsql.TransactionStatus) == @pgsql.InTransaction, content="false")
}
