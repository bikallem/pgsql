///| Protocol Conversion Functions
///
/// Private functions to convert between user-facing types and
/// internal protocol types.

/// Convert protocol Value to public Value
fn value_from_protocol(v : @protocol.Value) -> Value {
  match v {
    @protocol.Null => Null
    @protocol.Bool(b) => Bool(b)
    @protocol.Int(n) => Int(n)
    @protocol.Int64(n) => Int64(n)
    @protocol.Float(f) => Float(f)
    @protocol.String(s) => String(s)
    @protocol.Bytes(b) => Bytes(b)
  }
}

/// Convert public Value to protocol Value
fn value_to_protocol(v : Value) -> @protocol.Value {
  match v {
    Null => @protocol.Null
    Bool(b) => @protocol.Bool(b)
    Int(n) => @protocol.Int(n)
    Int64(n) => @protocol.Int64(n)
    Float(f) => @protocol.Float(f)
    String(s) => @protocol.String(s)
    Bytes(b) => @protocol.Bytes(b)
  }
}

/// Convert protocol FieldDescription to public ColumnInfo
fn column_info_from_field(fd : @protocol.FieldDescription) -> ColumnInfo {
  { name: fd.name, type_oid: fd.type_oid, type_size: fd.type_size }
}

/// Convert protocol TransactionStatus to public TransactionStatus
fn tx_status_from_protocol(s : @protocol.TransactionStatus) -> TransactionStatus {
  match s {
    @protocol.Idle => Idle
    @protocol.InTransaction => InTransaction
    @protocol.Failed => Failed
  }
}
