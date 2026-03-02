///| Unit tests for conversion functions (white-box)

test "value_from_protocol round-trip" {
  let cases : Array[@protocol.Value] = [
    @protocol.Null,
    @protocol.Bool(true),
    @protocol.Bool(false),
    @protocol.Int(42),
    @protocol.Int(-1),
    @protocol.Int64(9999999999L),
    @protocol.Float(3.14),
    @protocol.String("hello"),
    @protocol.Bytes(Bytes::from_array([b'\x01', b'\x02'])),
  ]
  for proto_val in cases {
    let pub_val = value_from_protocol(proto_val)
    let back = value_to_protocol(pub_val)
    inspect(back == proto_val, content="true")
  }
}

test "value_from_protocol Null" {
  inspect(value_from_protocol(@protocol.Null), content="Null")
}

test "value_from_protocol Bool" {
  inspect(value_from_protocol(@protocol.Bool(true)), content="Bool(true)")
  inspect(value_from_protocol(@protocol.Bool(false)), content="Bool(false)")
}

test "value_from_protocol Int" {
  inspect(value_from_protocol(@protocol.Int(42)), content="Int(42)")
}

test "value_from_protocol Int64" {
  inspect(value_from_protocol(@protocol.Int64(100L)), content="Int64(100)")
}

test "value_from_protocol Float" {
  inspect(value_from_protocol(@protocol.Float(1.5)), content="Float(1.5)")
}

test "value_from_protocol String" {
  inspect(value_from_protocol(@protocol.String("hi")), content=(
    #|String("hi")
  ))
}

test "value_to_protocol Null" {
  inspect(value_to_protocol(Null), content="Null")
}

test "value_to_protocol String" {
  inspect(value_to_protocol(String("abc")), content=(
    #|String("abc")
  ))
}

test "column_info_from_field" {
  let fd = @protocol.FieldDescription::new(
    "name", 0, 0, 25, -1, -1, @protocol.Text,
  )
  let col = column_info_from_field(fd)
  inspect(col.name, content="name")
  inspect(col.type_oid, content="25")
  inspect(col.type_size, content="-1")
}

test "tx_status_from_protocol" {
  inspect(tx_status_from_protocol(@protocol.Idle), content="Idle")
  inspect(tx_status_from_protocol(@protocol.InTransaction), content="InTransaction")
  inspect(tx_status_from_protocol(@protocol.Failed), content="Failed")
}
