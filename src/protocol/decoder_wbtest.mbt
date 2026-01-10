///| Unit tests for the decoder

test "decode_authentication_ok" {
  // AuthenticationOk: 'R' + length(8) + type(0)
  let data = Bytes::from_array([
    b'R', // type
    b'\x00', b'\x00', b'\x00', b'\x08', // length = 8
    b'\x00', b'\x00', b'\x00', b'\x00', // auth type = 0 (OK)
  ])

  let decoder = Decoder::new()
  let messages = decoder.parse(data)

  assert_eq(messages.length(), 1)
  match messages[0] {
    AuthenticationOk => ()
    _ => fail("Expected AuthenticationOk")
  }
}

test "decode_authentication_md5" {
  // AuthenticationMD5Password: 'R' + length(12) + type(5) + salt(4)
  let data = Bytes::from_array([
    b'R', // type
    b'\x00', b'\x00', b'\x00', b'\x0C', // length = 12
    b'\x00', b'\x00', b'\x00', b'\x05', // auth type = 5 (MD5)
    b'\x01', b'\x02', b'\x03', b'\x04', // salt
  ])

  let decoder = Decoder::new()
  let messages = decoder.parse(data)

  assert_eq(messages.length(), 1)
  match messages[0] {
    AuthenticationMD5Password(salt) => {
      assert_eq(salt.length(), 4)
      assert_eq(salt[0], b'\x01')
      assert_eq(salt[3], b'\x04')
    }
    _ => fail("Expected AuthenticationMD5Password")
  }
}

test "decode_ready_for_query_idle" {
  // ReadyForQuery: 'Z' + length(5) + status('I')
  let data = Bytes::from_array([
    b'Z', b'\x00', b'\x00', b'\x00', b'\x05', b'I',
  ])

  let decoder = Decoder::new()
  let messages = decoder.parse(data)

  assert_eq(messages.length(), 1)
  match messages[0] {
    ReadyForQuery(status) => assert_eq(status, Idle)
    _ => fail("Expected ReadyForQuery")
  }
}

test "decode_ready_for_query_transaction" {
  let data = Bytes::from_array([
    b'Z', b'\x00', b'\x00', b'\x00', b'\x05', b'T',
  ])

  let decoder = Decoder::new()
  let messages = decoder.parse(data)

  match messages[0] {
    ReadyForQuery(status) => assert_eq(status, InTransaction)
    _ => fail("Expected ReadyForQuery")
  }
}

test "decode_ready_for_query_failed" {
  let data = Bytes::from_array([
    b'Z', b'\x00', b'\x00', b'\x00', b'\x05', b'E',
  ])

  let decoder = Decoder::new()
  let messages = decoder.parse(data)

  match messages[0] {
    ReadyForQuery(status) => assert_eq(status, Failed)
    _ => fail("Expected ReadyForQuery")
  }
}

test "decode_command_complete" {
  // CommandComplete: 'C' + length + "SELECT 5\0"
  let data = Bytes::from_array([
    b'C', b'\x00', b'\x00', b'\x00', b'\x0D', // length = 13
    b'S', b'E', b'L', b'E', b'C', b'T', b' ', b'5', b'\x00',
  ])

  let decoder = Decoder::new()
  let messages = decoder.parse(data)

  match messages[0] {
    CommandComplete(tag) => assert_eq(tag, "SELECT 5")
    _ => fail("Expected CommandComplete")
  }
}

test "decode_parse_complete" {
  // ParseComplete: '1' + length(4)
  let data = Bytes::from_array([b'1', b'\x00', b'\x00', b'\x00', b'\x04'])

  let decoder = Decoder::new()
  let messages = decoder.parse(data)

  match messages[0] {
    ParseComplete => ()
    _ => fail("Expected ParseComplete")
  }
}

test "decode_bind_complete" {
  let data = Bytes::from_array([b'2', b'\x00', b'\x00', b'\x00', b'\x04'])

  let decoder = Decoder::new()
  let messages = decoder.parse(data)

  match messages[0] {
    BindComplete => ()
    _ => fail("Expected BindComplete")
  }
}

test "decode_no_data" {
  let data = Bytes::from_array([b'n', b'\x00', b'\x00', b'\x00', b'\x04'])

  let decoder = Decoder::new()
  let messages = decoder.parse(data)

  match messages[0] {
    NoData => ()
    _ => fail("Expected NoData")
  }
}

test "decode_empty_query" {
  let data = Bytes::from_array([b'I', b'\x00', b'\x00', b'\x00', b'\x04'])

  let decoder = Decoder::new()
  let messages = decoder.parse(data)

  match messages[0] {
    EmptyQueryResponse => ()
    _ => fail("Expected EmptyQueryResponse")
  }
}

test "decode_parameter_status" {
  // ParameterStatus: 'S' + length + name\0 + value\0
  let correct_data = Bytes::from_array([
    b'S', b'\x00', b'\x00', b'\x00', b'\x19', // length = 25
    b'c', b'l', b'i', b'e', b'n', b't', b'_', b'e', b'n', b'c', b'o', b'd', b'i',
    b'n', b'g', b'\x00', // "client_encoding\0" = 16 bytes
    b'U', b'T', b'F', b'8', b'\x00', // "UTF8\0" = 5 bytes
  ])

  let decoder = Decoder::new()
  let messages = decoder.parse(correct_data)

  match messages[0] {
    ParameterStatus(name, value) => {
      assert_eq(name, "client_encoding")
      assert_eq(value, "UTF8")
    }
    _ => fail("Expected ParameterStatus")
  }
}

test "decode_backend_key_data" {
  // BackendKeyData: 'K' + length(12) + pid(4) + key(4)
  let data = Bytes::from_array([
    b'K', b'\x00', b'\x00', b'\x00', b'\x0C', // length = 12
    b'\x00', b'\x00', b'\x30', b'\x39', // pid = 12345
    b'\x00', b'\x01', b'\x09', b'\x32', // key = 67890
  ])

  let decoder = Decoder::new()
  let messages = decoder.parse(data)

  match messages[0] {
    BackendKeyData(pid, key) => {
      assert_eq(pid, 12345)
      assert_eq(key, 67890)
    }
    _ => fail("Expected BackendKeyData")
  }
}

test "decode_row_description" {
  // RowDescription with 1 column
  let data = Bytes::from_array([
    b'T', b'\x00', b'\x00', b'\x00', b'\x1B', // length = 27
    b'\x00', b'\x01', // field count = 1
    b'i', b'd', b'\x00', // name = "id\0"
    b'\x00', b'\x00', b'\x00', b'\x00', // table oid = 0
    b'\x00', b'\x00', // column id = 0
    b'\x00', b'\x00', b'\x00', b'\x17', // type oid = 23 (int4)
    b'\x00', b'\x04', // type size = 4
    b'\xFF', b'\xFF', b'\xFF', b'\xFF', // type modifier = -1
    b'\x00', b'\x00', // format = text
  ])

  let decoder = Decoder::new()
  let messages = decoder.parse(data)

  match messages[0] {
    RowDescription(fields) => {
      assert_eq(fields.length(), 1)
      assert_eq(fields[0].name, "id")
      assert_eq(fields[0].type_oid, OID_INT4)
      assert_eq(fields[0].format, Text)
    }
    _ => fail("Expected RowDescription")
  }
}

test "decode_data_row" {
  // DataRow with 2 columns: "hello" and NULL
  // Length = 4 (length field) + 2 (column count) + 4 (len1) + 5 (data1) + 4 (len2) = 19
  let data = Bytes::from_array([
    b'D', b'\x00', b'\x00', b'\x00', b'\x13', // length = 19
    b'\x00', b'\x02', // column count = 2
    b'\x00', b'\x00', b'\x00', b'\x05', // length = 5
    b'h', b'e', b'l', b'l', b'o', // "hello"
    b'\xFF', b'\xFF', b'\xFF', b'\xFF', // length = -1 (NULL)
  ])

  let decoder = Decoder::new()
  let messages = decoder.parse(data)

  match messages[0] {
    DataRow(values) => {
      assert_eq(values.length(), 2)
      match values[0] {
        Some(v) => assert_eq(test_bytes_to_string(v), "hello")
        None => fail("Expected value, got NULL")
      }
      match values[1] {
        None => ()
        Some(_) => fail("Expected NULL")
      }
    }
    _ => fail("Expected DataRow")
  }
}

test "decode_multiple_messages" {
  // Two messages: ParseComplete + BindComplete
  let data = Bytes::from_array([
    b'1', b'\x00', b'\x00', b'\x00', b'\x04', // ParseComplete
    b'2', b'\x00', b'\x00', b'\x00', b'\x04', // BindComplete
  ])

  let decoder = Decoder::new()
  let messages = decoder.parse(data)

  assert_eq(messages.length(), 2)
  match messages[0] {
    ParseComplete => ()
    _ => fail("Expected ParseComplete")
  }
  match messages[1] {
    BindComplete => ()
    _ => fail("Expected BindComplete")
  }
}

test "decode_partial_message" {
  let decoder = Decoder::new()

  // Send partial message (only header)
  let partial1 = Bytes::from_array([b'Z', b'\x00', b'\x00'])
  let messages1 = decoder.parse(partial1)
  assert_eq(messages1.length(), 0)

  // Send rest of message
  let partial2 = Bytes::from_array([b'\x00', b'\x05', b'I'])
  let messages2 = decoder.parse(partial2)
  assert_eq(messages2.length(), 1)

  match messages2[0] {
    ReadyForQuery(Idle) => ()
    _ => fail("Expected ReadyForQuery(Idle)")
  }
}
