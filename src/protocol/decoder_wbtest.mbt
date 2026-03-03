///|
/// Unit tests for the decoder
test "decode_authentication_ok" {
  let data = Bytes::from_array([
    b'R', b'\x00', b'\x00', b'\x00', b'\x08', b'\x00', b'\x00', b'\x00', b'\x00',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  inspect(messages.length(), content="1")
  match messages[0] {
    AuthenticationOk => ()
    _ => fail("Expected AuthenticationOk")
  }
}

///|
test "decode_authentication_cleartext" {
  let data = Bytes::from_array([
    b'R', b'\x00', b'\x00', b'\x00', b'\x08', b'\x00', b'\x00', b'\x00', b'\x03',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    AuthenticationCleartextPassword => ()
    _ => fail("Expected AuthenticationCleartextPassword")
  }
}

///|
test "decode_authentication_md5" {
  let data = Bytes::from_array([
    b'R', b'\x00', b'\x00', b'\x00', b'\x0C', b'\x00', b'\x00', b'\x00', b'\x05',
    b'\x01', b'\x02', b'\x03', b'\x04',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    AuthenticationMD5Password(salt) => {
      inspect(salt.length(), content="4")
      inspect(salt[0], content="b'\\x01'")
      inspect(salt[3], content="b'\\x04'")
    }
    _ => fail("Expected AuthenticationMD5Password")
  }
}

///|
test "decode_authentication_sasl" {
  // AuthenticationSASL: 'R' + length + type(10) + "SCRAM-SHA-256\0" + "\0"
  let data = Bytes::from_array([
    b'R', b'\x00', b'\x00', b'\x00', b'\x17', b'\x00', b'\x00', b'\x00', b'\x0A', // auth type = 10 (SASL)
     b'S', b'C', b'R', b'A', b'M', b'-', b'S', b'H', b'A', b'-', b'2', b'5', b'6',
    b'\x00', // "SCRAM-SHA-256\0"
     b'\x00', // terminator
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    AuthenticationSASL(mechanisms) => {
      inspect(mechanisms.length(), content="1")
      inspect(mechanisms[0], content="SCRAM-SHA-256")
    }
    _ => fail("Expected AuthenticationSASL")
  }
}

///|
test "decode_ready_for_query_idle" {
  let data = Bytes::from_array([b'Z', b'\x00', b'\x00', b'\x00', b'\x05', b'I'])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    ReadyForQuery(status) => inspect(status, content="Idle")
    _ => fail("Expected ReadyForQuery")
  }
}

///|
test "decode_ready_for_query_transaction" {
  let data = Bytes::from_array([b'Z', b'\x00', b'\x00', b'\x00', b'\x05', b'T'])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    ReadyForQuery(status) => inspect(status, content="InTransaction")
    _ => fail("Expected ReadyForQuery")
  }
}

///|
test "decode_ready_for_query_failed" {
  let data = Bytes::from_array([b'Z', b'\x00', b'\x00', b'\x00', b'\x05', b'E'])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    ReadyForQuery(status) => inspect(status, content="Failed")
    _ => fail("Expected ReadyForQuery")
  }
}

///|
test "decode_command_complete" {
  let data = Bytes::from_array([
    b'C', b'\x00', b'\x00', b'\x00', b'\x0D', b'S', b'E', b'L', b'E', b'C', b'T',
    b' ', b'5', b'\x00',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    CommandComplete(tag) => inspect(tag, content="SELECT 5")
    _ => fail("Expected CommandComplete")
  }
}

///|
test "decode_parse_complete" {
  let data = Bytes::from_array([b'1', b'\x00', b'\x00', b'\x00', b'\x04'])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    ParseComplete => ()
    _ => fail("Expected ParseComplete")
  }
}

///|
test "decode_bind_complete" {
  let data = Bytes::from_array([b'2', b'\x00', b'\x00', b'\x00', b'\x04'])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    BindComplete => ()
    _ => fail("Expected BindComplete")
  }
}

///|
test "decode_close_complete" {
  let data = Bytes::from_array([b'3', b'\x00', b'\x00', b'\x00', b'\x04'])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    CloseComplete => ()
    _ => fail("Expected CloseComplete")
  }
}

///|
test "decode_no_data" {
  let data = Bytes::from_array([b'n', b'\x00', b'\x00', b'\x00', b'\x04'])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    NoData => ()
    _ => fail("Expected NoData")
  }
}

///|
test "decode_empty_query" {
  let data = Bytes::from_array([b'I', b'\x00', b'\x00', b'\x00', b'\x04'])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    EmptyQueryResponse => ()
    _ => fail("Expected EmptyQueryResponse")
  }
}

///|
test "decode_portal_suspended" {
  let data = Bytes::from_array([b's', b'\x00', b'\x00', b'\x00', b'\x04'])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    PortalSuspended => ()
    _ => fail("Expected PortalSuspended")
  }
}

///|
test "decode_parameter_status" {
  let data = Bytes::from_array([
    b'S', b'\x00', b'\x00', b'\x00', b'\x19', b'c', b'l', b'i', b'e', b'n', b't',
    b'_', b'e', b'n', b'c', b'o', b'd', b'i', b'n', b'g', b'\x00', b'U', b'T', b'F',
    b'8', b'\x00',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    ParameterStatus(name, value) => {
      inspect(name, content="client_encoding")
      inspect(value, content="UTF8")
    }
    _ => fail("Expected ParameterStatus")
  }
}

///|
test "decode_backend_key_data" {
  let data = Bytes::from_array([
    b'K', b'\x00', b'\x00', b'\x00', b'\x0C', b'\x00', b'\x00', b'\x30', b'\x39',
    b'\x00', b'\x01', b'\x09', b'\x32',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    BackendKeyData(pid, key) => {
      inspect(pid, content="12345")
      inspect(key, content="67890")
    }
    _ => fail("Expected BackendKeyData")
  }
}

///|
test "decode_row_description" {
  let data = Bytes::from_array([
    b'T', b'\x00', b'\x00', b'\x00', b'\x1B', b'\x00', b'\x01', b'i', b'd', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x17', b'\x00', b'\x04', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\x00', b'\x00',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    RowDescription(fields) => {
      inspect(fields.length(), content="1")
      inspect(fields[0].name, content="id")
      inspect(fields[0].type_oid, content="23")
      inspect(fields[0].format, content="Text")
    }
    _ => fail("Expected RowDescription")
  }
}

///|
test "decode_data_row" {
  let data = Bytes::from_array([
    b'D', b'\x00', b'\x00', b'\x00', b'\x13', b'\x00', b'\x02', b'\x00', b'\x00',
    b'\x00', b'\x05', b'h', b'e', b'l', b'l', b'o', b'\xFF', b'\xFF', b'\xFF', b'\xFF',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    DataRow(values) => {
      inspect(values.length(), content="2")
      inspect(values[0] is Some(_), content="true")
      inspect(values[1], content="None")
    }
    _ => fail("Expected DataRow")
  }
}

///|
test "decode_error_response" {
  // ErrorResponse: 'E' + length + fields
  // S=ERROR\0(7) + C=42P01\0(7) + M=table missing\0(15) + \0(1) = 30; length=34=0x22
  let data = Bytes::from_array([
    b'E', b'\x00', b'\x00', b'\x00', b'\x22', b'S', b'E', b'R', b'R', b'O', b'R',
    b'\x00', // S=ERROR
     b'C', b'4', b'2', b'P', b'0', b'1', b'\x00', // C=42P01
     b'M', b't', b'a', b'b', b'l', b'e', b' ', b'm', b'i', b's', b's', b'i', b'n',
    b'g', b'\x00', // M=table missing
     b'\x00', // terminator
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    ErrorResponse(fields) => {
      inspect(
        fields["S"],
        content=(
          #|ERROR
        ),
      )
      inspect(
        fields["C"],
        content=(
          #|42P01
        ),
      )
      inspect(
        fields["M"],
        content=(
          #|table missing
        ),
      )
    }
    _ => fail("Expected ErrorResponse")
  }
}

///|
test "decode_notice_response" {
  // S=NOTICE\0(8) + M=hi\0(4) + \0(1) = 13; length=17=0x11
  let data = Bytes::from_array([
    b'N', b'\x00', b'\x00', b'\x00', b'\x11', b'S', b'N', b'O', b'T', b'I', b'C',
    b'E', b'\x00', // S=NOTICE
     b'M', b'h', b'i', b'\x00', // M=hi
     b'\x00',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    NoticeResponse(fields) => {
      inspect(
        fields["S"],
        content=(
          #|NOTICE
        ),
      )
      inspect(
        fields["M"],
        content=(
          #|hi
        ),
      )
    }
    _ => fail("Expected NoticeResponse")
  }
}

///|
test "decode_notification_response" {
  // NotificationResponse: 'A' + length + pid(4) + channel\0 + payload\0
  let data = Bytes::from_array([
    b'A', b'\x00', b'\x00', b'\x00', b'\x12', b'\x00', b'\x00', b'\x00', b'\x01', // pid = 1
     b'c', b'h', b'a', b'n', b'\x00', // channel = "chan"
     b'd', b'a', b't', b'a', b'\x00', // payload = "data"
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    NotificationResponse(pid, channel, payload) => {
      inspect(pid, content="1")
      inspect(channel, content="chan")
      inspect(payload, content="data")
    }
    _ => fail("Expected NotificationResponse")
  }
}

///|
test "decode_multiple_messages" {
  let data = Bytes::from_array([
    b'1', b'\x00', b'\x00', b'\x00', b'\x04', b'2', b'\x00', b'\x00', b'\x00', b'\x04',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  inspect(messages.length(), content="2")
  match messages[0] {
    ParseComplete => ()
    _ => fail("Expected ParseComplete")
  }
  match messages[1] {
    BindComplete => ()
    _ => fail("Expected BindComplete")
  }
}

///|
test "decode_partial_message" {
  let decoder = Decoder::new()
  let partial1 = Bytes::from_array([b'Z', b'\x00', b'\x00'])
  let messages1 = decoder.parse(partial1)
  inspect(messages1.length(), content="0")
  inspect(decoder.has_pending(), content="true")
  let partial2 = Bytes::from_array([b'\x00', b'\x05', b'I'])
  let messages2 = decoder.parse(partial2)
  inspect(messages2.length(), content="1")
  match messages2[0] {
    ReadyForQuery(Idle) => ()
    _ => fail("Expected ReadyForQuery(Idle)")
  }
}

///|
test "Decoder::clear" {
  let decoder = Decoder::new()
  let partial = Bytes::from_array([b'Z', b'\x00'])
  let _ = decoder.parse(partial)
  inspect(decoder.has_pending(), content="true")
  decoder.clear()
  inspect(decoder.has_pending(), content="false")
}

///|
test "Decoder::has_pending empty" {
  let decoder = Decoder::new()
  inspect(decoder.has_pending(), content="false")
}

///|
test "decode_copy_in_response" {
  // CopyInResponse: format(1) + count(2) + 2*int16(4) = 7; length=11=0x0B
  let data = Bytes::from_array([
    b'G', b'\x00', b'\x00', b'\x00', b'\x0B', b'\x00', // text format
     b'\x00', b'\x02', // 2 columns
     b'\x00', b'\x00', // column 1: text
     b'\x00', b'\x00', // column 2: text
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    CopyInResponse(fmt, col_fmts) => {
      inspect(fmt, content="Text")
      inspect(col_fmts.length(), content="2")
    }
    _ => fail("Expected CopyInResponse")
  }
}

///|
test "decode_copy_done" {
  let data = Bytes::from_array([b'c', b'\x00', b'\x00', b'\x00', b'\x04'])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    CopyDone => ()
    _ => fail("Expected CopyDone")
  }
}

///|
test "decode_parameter_description" {
  // ParameterDescription: 't' + length + count(2) + oid(4)...
  let data = Bytes::from_array([
    b't', b'\x00', b'\x00', b'\x00', b'\x0A', b'\x00', b'\x01', // 1 parameter
     b'\x00', b'\x00', b'\x00', b'\x17', // oid = 23 (int4)
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    ParameterDescription(oids) => {
      inspect(oids.length(), content="1")
      inspect(oids[0], content="23")
    }
    _ => fail("Expected ParameterDescription")
  }
}

// =============================================================================
// Malformed input tests (#29)
// =============================================================================

///|
test "decode_malformed_length_too_small" {
  // Message with length < 4 (invalid: length includes itself, minimum is 4)
  let data = Bytes::from_array([
    b'Z', b'\x00', b'\x00', b'\x00', b'\x02', b'I', // len=2, invalid
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  // Should skip the malformed message
  inspect(messages.length(), content="0")
}

///|
test "decode_truncated_header" {
  // Only 3 bytes — not even a full header
  let data = Bytes::from_array([b'Z', b'\x00', b'\x00'])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  inspect(messages.length(), content="0")
  inspect(decoder.has_pending(), content="true")
}

///|
test "decode_truncated_payload" {
  // Header says 5 bytes payload but only 2 provided
  let data = Bytes::from_array([
    b'Z', b'\x00', b'\x00', b'\x00', b'\x05', // len=5, needs 1 more byte
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  inspect(messages.length(), content="0")
  inspect(decoder.has_pending(), content="true")
}

///|
test "decode_unknown_message_type" {
  // Unknown type code 0xFF, minimal valid message (length 4)
  let data = Bytes::from_array([
    b'\xFF', b'\x00', b'\x00', b'\x00', b'\x04',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  inspect(messages.length(), content="1")
  match messages[0] {
    ErrorResponse(fields) =>
      assert_true(fields["M"].contains("Unknown message type"))
    _ => fail("Expected ErrorResponse for unknown type")
  }
}

///|
test "decode_buffer_underflow_in_payload" {
  // RowDescription header claiming 5 fields but payload is too short
  // 'T' + length(4) + field_count(2 bytes claiming 5 fields) but no field data
  let data = Bytes::from_array([
    b'T', b'\x00', b'\x00', b'\x00', b'\x06', b'\x00', b'\x05', // 5 fields, but empty
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  // Should skip the malformed message (BufferUnderflow caught)
  inspect(messages.length(), content="0")
}

// =============================================================================
// Previously untested decoder paths (#30)
// =============================================================================

///|
test "decode_copy_out_response" {
  // CopyOutResponse: same format as CopyInResponse but type 'H'
  let data = Bytes::from_array([
    b'H', b'\x00', b'\x00', b'\x00', b'\x09', b'\x01', // binary format
     b'\x00', b'\x01', // 1 column
     b'\x00', b'\x01', // column 1: binary
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    CopyOutResponse(fmt, col_fmts) => {
      inspect(fmt, content="Binary")
      inspect(col_fmts.length(), content="1")
      inspect(col_fmts[0], content="Binary")
    }
    _ => fail("Expected CopyOutResponse")
  }
}

///|
test "decode_copy_data" {
  // CopyData: 'd' + length + arbitrary data
  let data = Bytes::from_array([
    b'd', b'\x00', b'\x00', b'\x00', b'\x07', b'\x01', b'\x02', b'\x03',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    CopyData(payload) => inspect(payload.length(), content="3")
    _ => fail("Expected CopyData")
  }
}

///|
test "decode_authentication_sasl_continue" {
  // AuthenticationSASLContinue: 'R' + length + type(11) + data
  let data = Bytes::from_array([
    b'R', b'\x00', b'\x00', b'\x00', b'\x0C', b'\x00', b'\x00', b'\x00', b'\x0B',
    b'a', b'b', b'c', b'd', // 4 bytes of SASL data
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    AuthenticationSASLContinue(payload) => inspect(payload.length(), content="4")
    _ => fail("Expected AuthenticationSASLContinue")
  }
}

///|
test "decode_authentication_sasl_final" {
  // AuthenticationSASLFinal: 'R' + length + type(12) + data
  let data = Bytes::from_array([
    b'R', b'\x00', b'\x00', b'\x00', b'\x0A', b'\x00', b'\x00', b'\x00', b'\x0C',
    b'X', b'Y', // 2 bytes of SASL data
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    AuthenticationSASLFinal(payload) => inspect(payload.length(), content="2")
    _ => fail("Expected AuthenticationSASLFinal")
  }
}

///|
test "decode_unsupported_auth_type" {
  // Authentication type 99 (unsupported)
  let data = Bytes::from_array([
    b'R', b'\x00', b'\x00', b'\x00', b'\x08', b'\x00', b'\x00', b'\x00', b'\x63', // type=99
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    ErrorResponse(fields) =>
      assert_true(fields["M"].contains("Unsupported authentication"))
    _ => fail("Expected ErrorResponse for unsupported auth")
  }
}
