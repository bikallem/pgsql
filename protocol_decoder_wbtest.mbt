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
      assert_eq(fields.length(), 1)
      assert_eq(fields[0].name, "id")
      assert_eq(fields[0].type_oid, 23U)
      assert_true(fields[0].format is Text)
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
  inspect(decoder.buffer.length() > 0, content="true")
  let partial2 = Bytes::from_array([b'\x00', b'\x05', b'I'])
  let messages2 = decoder.parse(partial2)
  inspect(messages2.length(), content="1")
  match messages2[0] {
    ReadyForQuery(Idle) => ()
    _ => fail("Expected ReadyForQuery(Idle)")
  }
}

///|
test "Decoder buffer clear" {
  let decoder = Decoder::new()
  let partial = Bytes::from_array([b'Z', b'\x00'])
  ignore((decoder.parse(partial) : Array[BackendMessage]))
  inspect(decoder.buffer.length() > 0, content="true")
  decoder.buffer.clear()
  inspect(decoder.buffer.length() > 0, content="false")
}

///|
test "Decoder buffer empty" {
  let decoder = Decoder::new()
  inspect(decoder.buffer.length() > 0, content="false")
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
      assert_true(fmt is Text)
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

///|
test "decode_retains_trailing_partial_frame_with_head_offset" {
  let decoder = Decoder::new()
  let first_chunk = Bytes::from_array([
    b'Z', b'\x00', b'\x00', b'\x00', b'\x05', b'I', // complete ReadyForQuery
     b'Z', b'\x00', b'\x00', // partial next frame header
  ])
  let first_messages = decoder.parse(first_chunk)
  inspect(first_messages.length(), content="1")
  assert_true(decoder.start > 0)
  assert_true(decoder.buffer.length() > decoder.start)

  let second_chunk = Bytes::from_array([b'\x00', b'\x05', b'T'])
  let second_messages = decoder.parse(second_chunk)
  inspect(second_messages.length(), content="1")
  match second_messages[0] {
    ReadyForQuery(status) => inspect(status, content="InTransaction")
    _ => fail("Expected ReadyForQuery")
  }
  inspect(decoder.buffer.length(), content="0")
  inspect(decoder.start, content="0")
}

///|
test "decode_compacts_large_consumed_prefix" {
  let decoder = Decoder::new()
  let payload : Array[Byte] = []

  for _i = 0; _i < 800; _i = _i + 1 {
    payload.push(b'Z')
    payload.push(b'\x00')
    payload.push(b'\x00')
    payload.push(b'\x00')
    payload.push(b'\x05')
    payload.push(b'I')
  }
  // Leave a small trailing incomplete frame to keep unread bytes buffered.
  payload.push(b'Z')
  payload.push(b'\x00')
  payload.push(b'\x00')

  let messages = decoder.parse(Bytes::from_array(payload))
  inspect(messages.length(), content="800")
  // Consumed prefix should compact away and keep only unread tail.
  inspect(decoder.start, content="0")
  inspect(decoder.buffer.length(), content="3")
}

// =============================================================================
// Malformed input tests (#29)
// =============================================================================

///|
fn assert_decoder_error(
  messages : Array[BackendMessage],
  contains~ : String,
) -> Unit raise {
  inspect(messages.length(), content="1")
  match messages[0] {
    ErrorResponse(fields) => assert_true(fields["M"].contains(contains))
    _ => fail("Expected ErrorResponse")
  }
}

///|
test "decode_malformed_length_too_small" {
  // Message with length < 4 (invalid: length includes itself, minimum is 4)
  let data = Bytes::from_array([b'Z', b'\x00', b'\x00', b'\x00', b'\x02', b'I'], // len=2, invalid
  )
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  assert_decoder_error(messages, contains="invalid length")
  inspect(decoder.buffer.length(), content="0")
}

///|
test "decode_truncated_header" {
  // Only 3 bytes — not even a full header
  let data = Bytes::from_array([b'Z', b'\x00', b'\x00'])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  inspect(messages.length(), content="0")
  inspect(decoder.buffer.length() > 0, content="true")
}

///|
test "decode_truncated_payload" {
  // Header says 5 bytes payload but only 2 provided
  let data = Bytes::from_array([b'Z', b'\x00', b'\x00', b'\x00', b'\x05'], // len=5, needs 1 more byte
  )
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  inspect(messages.length(), content="0")
  inspect(decoder.buffer.length() > 0, content="true")
}

///|
test "decode_unknown_message_type" {
  // Unknown type code 0xFF, minimal valid message (length 4)
  let data = Bytes::from_array([b'\xFF', b'\x00', b'\x00', b'\x00', b'\x04'])
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
  assert_decoder_error(messages, contains="Malformed protocol frame")
  inspect(decoder.buffer.length(), content="0")
}

///|
test "decode_row_description_negative_field_count" {
  let data = Bytes::from_array([
    b'T', b'\x00', b'\x00', b'\x00', b'\x06', b'\xFF', b'\xFF',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  assert_decoder_error(messages, contains="negative field count")
}

///|
test "decode_data_row_negative_column_count" {
  let data = Bytes::from_array([
    b'D', b'\x00', b'\x00', b'\x00', b'\x06', b'\xFF', b'\xFF',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  assert_decoder_error(messages, contains="negative column count")
}

///|
test "decode_data_row_invalid_negative_column_length" {
  let data = Bytes::from_array([
    b'D', b'\x00', b'\x00', b'\x00', b'\x0A', b'\x00', b'\x01', b'\xFF', b'\xFF',
    b'\xFF', b'\xFE',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  assert_decoder_error(messages, contains="invalid negative column length")
}

///|
test "decode_parameter_description_negative_count" {
  let data = Bytes::from_array([
    b't', b'\x00', b'\x00', b'\x00', b'\x06', b'\xFF', b'\xFF',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  assert_decoder_error(messages, contains="negative count")
}

///|
test "decode_copy_response_negative_column_count" {
  let data = Bytes::from_array([
    b'G', b'\x00', b'\x00', b'\x00', b'\x07', b'\x00', b'\xFF', b'\xFF',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  assert_decoder_error(messages, contains="negative column count")
}

///|
test "decode_negotiate_protocol_version_negative_count" {
  let data = Bytes::from_array([
    b'v', b'\x00', b'\x00', b'\x00', b'\x0C', b'\x00', b'\x00', b'\x00', b'\x01',
    b'\xFF', b'\xFF', b'\xFF', b'\xFF',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  assert_decoder_error(messages, contains="negative option count")
}

///|
test "decode_frame_over_max_length_returns_error_and_clears_buffer" {
  // len = 0x00800001 (8 MiB + 1), above decoder max frame length.
  let data = Bytes::from_array([b'Z', b'\x00', b'\x80', b'\x00', b'\x01'])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  inspect(messages.length(), content="1")
  match messages[0] {
    ErrorResponse(fields) =>
      assert_true(fields["M"].contains("exceeds max length"))
    _ => fail("Expected ErrorResponse")
  }
  inspect(decoder.buffer.length(), content="0")
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
      assert_true(fmt is Binary)
      inspect(col_fmts.length(), content="1")
      assert_true(col_fmts[0] is Binary)
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
    AuthenticationSASLContinue(payload) =>
      inspect(payload.length(), content="4")
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
test "decode_negotiate_protocol_version" {
  // NegotiateProtocolVersion: 'v' + length + newest_minor(4) + count(4) + option\0
  // newest_minor=1, count=1, option="_pq_.foo\0"
  let data = Bytes::from_array([
    b'v', b'\x00', b'\x00', b'\x00', b'\x15', // length=21
     b'\x00', b'\x00', b'\x00', b'\x01', // newest_minor=1
     b'\x00', b'\x00', b'\x00', b'\x01', // count=1
     b'_', b'p', b'q', b'_', b'.', b'f', b'o', b'o', b'\x00', // "_pq_.foo\0"
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    NegotiateProtocolVersion(minor, options) => {
      inspect(minor, content="1")
      inspect(options.length(), content="1")
      inspect(options[0], content="_pq_.foo")
    }
    _ => fail("Expected NegotiateProtocolVersion")
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

// =============================================================================
// Extended decoder coverage tests
// =============================================================================

///|
test "decode_row_description_multiple_columns" {
  // RowDescription with 2 columns:
  //   "id"  : table_oid=1000, col_id=1, type_oid=23 (int4), size=4, mod=-1, fmt=text(0)
  //   "name": table_oid=1000, col_id=2, type_oid=25 (text), size=-1, mod=-1, fmt=binary(1)
  // field 1: "id\0"(3) + 18 = 21 bytes
  // field 2: "name\0"(5) + 18 = 23 bytes
  // payload: field_count(2) + 21 + 23 = 46 bytes; length = 46 + 4 = 50 = 0x32
  let data = Bytes::from_array([
    b'T', b'\x00', b'\x00', b'\x00', b'\x32', b'\x00', b'\x02', // field_count = 2
    // Column 1: "id"
     b'i', b'd', b'\x00', // name
     b'\x00', b'\x00', b'\x03', b'\xE8', // table_oid = 1000
     b'\x00', b'\x01', // column_id = 1
     b'\x00', b'\x00', b'\x00', b'\x17', // type_oid = 23 (int4)
     b'\x00', b'\x04', // type_size = 4
     b'\xFF', b'\xFF', b'\xFF', b'\xFF', // type_modifier = -1
     b'\x00', b'\x00', // format = text
    // Column 2: "name"
     b'n', b'a', b'm', b'e', b'\x00', // name
     b'\x00', b'\x00', b'\x03', b'\xE8', // table_oid = 1000
     b'\x00', b'\x02', // column_id = 2
     b'\x00', b'\x00', b'\x00', b'\x19', // type_oid = 25 (text)
     b'\xFF', b'\xFF', // type_size = -1
     b'\xFF', b'\xFF', b'\xFF', b'\xFF', // type_modifier = -1
     b'\x00', b'\x01', // format = binary
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  inspect(messages.length(), content="1")
  match messages[0] {
    RowDescription(fields) => {
      assert_eq(fields.length(), 2)
      assert_eq(fields[0].name, "id")
      assert_eq(fields[0].table_oid, 1000U)
      assert_eq(fields[0].column_id, 1)
      assert_eq(fields[0].type_oid, 23U)
      assert_eq(fields[0].type_size, 4)
      assert_true(fields[0].format is Text)
      assert_eq(fields[1].name, "name")
      assert_eq(fields[1].table_oid, 1000U)
      assert_eq(fields[1].column_id, 2)
      assert_eq(fields[1].type_oid, 25U)
      assert_eq(fields[1].type_size, -1)
      assert_true(fields[1].format is Binary)
    }
    _ => fail("Expected RowDescription")
  }
}

///|
test "decode_data_row_all_nulls" {
  // DataRow with 3 columns, all NULL (-1 length each)
  // payload: col_count(2) + 3 * int32(4) = 14; length = 14 + 4 = 18 = 0x12
  let data = Bytes::from_array([
    b'D', b'\x00', b'\x00', b'\x00', b'\x12', b'\x00', b'\x03', // 3 columns
     b'\xFF', b'\xFF', b'\xFF', b'\xFF', // NULL
     b'\xFF', b'\xFF', b'\xFF', b'\xFF', // NULL
     b'\xFF', b'\xFF', b'\xFF', b'\xFF', // NULL
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  inspect(messages.length(), content="1")
  match messages[0] {
    DataRow(values) => {
      assert_eq(values.length(), 3)
      inspect(values[0], content="None")
      inspect(values[1], content="None")
      inspect(values[2], content="None")
    }
    _ => fail("Expected DataRow")
  }
}

///|
test "decode_data_row_many_columns" {
  // DataRow with 5 columns of varied data:
  //   col0: "AB" (2 bytes), col1: NULL, col2: "X" (1 byte),
  //   col3: "" (0 bytes), col4: "\x01\x02\x03\x04" (4 bytes)
  // payload: col_count(2) +
  //   len(4)+2 + len(4) + len(4)+1 + len(4)+0 + len(4)+4 = 2+6+4+5+4+8 = 29
  // length = 29 + 4 = 33 = 0x21
  let data = Bytes::from_array([
    b'D', b'\x00', b'\x00', b'\x00', b'\x21', b'\x00', b'\x05', // 5 columns
    // col 0: "AB" (length 2)
     b'\x00', b'\x00', b'\x00', b'\x02', b'A', b'B',
    // col 1: NULL
     b'\xFF', b'\xFF', b'\xFF', b'\xFF',
    // col 2: "X" (length 1)
     b'\x00', b'\x00', b'\x00', b'\x01', b'X',
    // col 3: "" (length 0)
     b'\x00', b'\x00', b'\x00', b'\x00',
    // col 4: 4 binary bytes
     b'\x00', b'\x00', b'\x00', b'\x04', b'\x01', b'\x02', b'\x03', b'\x04',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  inspect(messages.length(), content="1")
  match messages[0] {
    DataRow(values) => {
      assert_eq(values.length(), 5)
      // col 0: "AB"
      inspect(values[0] is Some(_), content="true")
      assert_eq(values[0].unwrap().length(), 2)
      // col 1: NULL
      inspect(values[1], content="None")
      // col 2: "X"
      assert_eq(values[2].unwrap().length(), 1)
      // col 3: empty
      assert_eq(values[3].unwrap().length(), 0)
      // col 4: 4 bytes
      let v4 = values[4].unwrap()
      assert_eq(v4.length(), 4)
      inspect(v4[0], content="b'\\x01'")
      inspect(v4[3], content="b'\\x04'")
    }
    _ => fail("Expected DataRow")
  }
}

///|
test "decode_command_complete_insert" {
  // "INSERT 0 3\0" = 11 bytes; length = 11 + 4 = 15 = 0x0F
  let data = Bytes::from_array([
    b'C', b'\x00', b'\x00', b'\x00', b'\x0F', b'I', b'N', b'S', b'E', b'R', b'T',
    b' ', b'0', b' ', b'3', b'\x00',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    CommandComplete(tag) => inspect(tag, content="INSERT 0 3")
    _ => fail("Expected CommandComplete")
  }
}

///|
test "decode_command_complete_update" {
  // "UPDATE 5\0" = 9 bytes; length = 9 + 4 = 13 = 0x0D
  let data = Bytes::from_array([
    b'C', b'\x00', b'\x00', b'\x00', b'\x0D', b'U', b'P', b'D', b'A', b'T', b'E',
    b' ', b'5', b'\x00',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    CommandComplete(tag) => inspect(tag, content="UPDATE 5")
    _ => fail("Expected CommandComplete")
  }
}

///|
test "decode_command_complete_delete" {
  // "DELETE 0\0" = 9 bytes; length = 9 + 4 = 13 = 0x0D
  let data = Bytes::from_array([
    b'C', b'\x00', b'\x00', b'\x00', b'\x0D', b'D', b'E', b'L', b'E', b'T', b'E',
    b' ', b'0', b'\x00',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    CommandComplete(tag) => inspect(tag, content="DELETE 0")
    _ => fail("Expected CommandComplete")
  }
}

///|
test "decode_command_complete_create_table" {
  // "CREATE TABLE\0" = 13 bytes; length = 13 + 4 = 17 = 0x11
  let data = Bytes::from_array([
    b'C', b'\x00', b'\x00', b'\x00', b'\x11', b'C', b'R', b'E', b'A', b'T', b'E',
    b' ', b'T', b'A', b'B', b'L', b'E', b'\x00',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    CommandComplete(tag) => inspect(tag, content="CREATE TABLE")
    _ => fail("Expected CommandComplete")
  }
}

///|
test "decode_command_complete_move" {
  // "MOVE 10\0" = 8 bytes; length = 8 + 4 = 12 = 0x0C
  let data = Bytes::from_array([
    b'C', b'\x00', b'\x00', b'\x00', b'\x0C', b'M', b'O', b'V', b'E', b' ', b'1',
    b'0', b'\x00',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  match messages[0] {
    CommandComplete(tag) => inspect(tag, content="MOVE 10")
    _ => fail("Expected CommandComplete")
  }
}

///|
test "decode_error_response_all_field_types" {
  // ErrorResponse with fields: S, V, C, M, D, H, t, c, n
  // S=ERROR\0       (7)
  // V=ERROR\0       (7)
  // C=23505\0       (7)
  // M=dup key\0     (9)
  // D=detail\0      (8)
  // H=hint\0        (6)
  // t=users\0       (7)
  // c=email\0       (7)
  // n=uq_email\0    (10)
  // \0 terminator   (1)
  // Total field bytes = 7+7+7+9+8+6+7+7+10+1 = 69; length = 69 + 4 = 73 = 0x49
  let data = Bytes::from_array([
    b'E', b'\x00', b'\x00', b'\x00', b'\x49',
    // S=ERROR
     b'S', b'E', b'R', b'R', b'O', b'R', b'\x00',
    // V=ERROR
     b'V', b'E', b'R', b'R', b'O', b'R', b'\x00',
    // C=23505
     b'C', b'2', b'3', b'5', b'0', b'5', b'\x00',
    // M=dup key
     b'M', b'd', b'u', b'p', b' ', b'k', b'e', b'y', b'\x00',
    // D=detail
     b'D', b'd', b'e', b't', b'a', b'i', b'l', b'\x00',
    // H=hint
     b'H', b'h', b'i', b'n', b't', b'\x00',
    // t=users
     b't', b'u', b's', b'e', b'r', b's', b'\x00',
    // c=email
     b'c', b'e', b'm', b'a', b'i', b'l', b'\x00',
    // n=uq_email
     b'n', b'u', b'q', b'_', b'e', b'm', b'a', b'i', b'l', b'\x00',
    // terminator
     b'\x00',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  inspect(messages.length(), content="1")
  match messages[0] {
    ErrorResponse(fields) => {
      inspect(
        fields["S"],
        content=(
          #|ERROR
        ),
      )
      inspect(
        fields["V"],
        content=(
          #|ERROR
        ),
      )
      inspect(
        fields["C"],
        content=(
          #|23505
        ),
      )
      inspect(
        fields["M"],
        content=(
          #|dup key
        ),
      )
      inspect(
        fields["D"],
        content=(
          #|detail
        ),
      )
      inspect(
        fields["H"],
        content=(
          #|hint
        ),
      )
      inspect(
        fields["t"],
        content=(
          #|users
        ),
      )
      inspect(
        fields["c"],
        content=(
          #|email
        ),
      )
      inspect(
        fields["n"],
        content=(
          #|uq_email
        ),
      )
    }
    _ => fail("Expected ErrorResponse")
  }
}

///|
test "decode_copy_out_response_binary_multiple_columns" {
  // CopyOutResponse: binary overall, 3 columns: binary, text, binary
  // payload: format(1) + count(2) + 3*int16(6) = 9; length = 9 + 4 = 13 = 0x0D
  let data = Bytes::from_array([
    b'H', b'\x00', b'\x00', b'\x00', b'\x0D', b'\x01', // binary overall format
     b'\x00', b'\x03', // 3 columns
     b'\x00', b'\x01', // column 1: binary
     b'\x00', b'\x00', // column 2: text
     b'\x00', b'\x01', // column 3: binary
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  inspect(messages.length(), content="1")
  match messages[0] {
    CopyOutResponse(fmt, col_fmts) => {
      assert_true(fmt is Binary)
      assert_eq(col_fmts.length(), 3)
      assert_true(col_fmts[0] is Binary)
      assert_true(col_fmts[1] is Text)
      assert_true(col_fmts[2] is Binary)
    }
    _ => fail("Expected CopyOutResponse")
  }
}

///|
test "decode_authentication_sasl_multiple_mechanisms" {
  // AuthenticationSASL with 2 mechanisms: "SCRAM-SHA-256" and "SCRAM-SHA-256-PLUS"
  // type(4) + "SCRAM-SHA-256\0"(14) + "SCRAM-SHA-256-PLUS\0"(19) + "\0"(1) = 38
  // length = 38 + 4 = 42 = 0x2A
  let data = Bytes::from_array([
    b'R', b'\x00', b'\x00', b'\x00', b'\x2A', b'\x00', b'\x00', b'\x00', b'\x0A', // auth type = 10 (SASL)
    // "SCRAM-SHA-256\0"
     b'S', b'C', b'R', b'A', b'M', b'-', b'S', b'H', b'A', b'-', b'2', b'5', b'6',
    b'\x00',
    // "SCRAM-SHA-256-PLUS\0"
     b'S', b'C', b'R', b'A', b'M', b'-', b'S', b'H', b'A', b'-', b'2', b'5', b'6',
    b'-', b'P', b'L', b'U', b'S', b'\x00',
    // terminator
     b'\x00',
  ])
  let decoder = Decoder::new()
  let messages = decoder.parse(data)
  inspect(messages.length(), content="1")
  match messages[0] {
    AuthenticationSASL(mechanisms) => {
      assert_eq(mechanisms.length(), 2)
      inspect(mechanisms[0], content="SCRAM-SHA-256")
      inspect(mechanisms[1], content="SCRAM-SHA-256-PLUS")
    }
    _ => fail("Expected AuthenticationSASL")
  }
}
