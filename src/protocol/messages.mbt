///| PostgreSQL Protocol Message Definitions
///
/// This file contains all message type definitions for the PostgreSQL
/// wire protocol (version 3.0).

// =============================================================================
// Protocol Constants
// =============================================================================

///|
/// Protocol version 3.0 (major=3, minor=0)
/// Encoded as Int32: (3 << 16) | 0 = 196608
pub const PROTOCOL_VERSION : Int = 196608

// Message type codes (Backend -> Frontend) - for documentation reference
// Note: decoder.mbt uses literal bytes directly for performance

///|
let _code_authentication : Byte = b'R'

///|
let _code_backend_key_data : Byte = b'K'

///|
let _code_parameter_status : Byte = b'S'

///|
let _code_ready_for_query : Byte = b'Z'

///|
let _code_row_description : Byte = b'T'

///|
let _code_data_row : Byte = b'D'

///|
let _code_command_complete : Byte = b'C'

///|
let _code_error_response : Byte = b'E'

///|
let _code_notice_response : Byte = b'N'

///|
let _code_parse_complete : Byte = b'1'

///|
let _code_bind_complete : Byte = b'2'

///|
let _code_close_complete : Byte = b'3'

///|
let _code_no_data : Byte = b'n'

///|
let _code_empty_query : Byte = b'I'

///|
let _code_portal_suspended : Byte = b's'

///|
let _code_parameter_description : Byte = b't'

///|
let _code_notification : Byte = b'A'

///|
let _code_copy_in_response : Byte = b'G'

///|
let _code_copy_out_response : Byte = b'H'

///|
let _code_copy_data : Byte = b'd'

///|
let _code_copy_done : Byte = b'c'

// Message type codes (Frontend -> Backend) - for documentation reference

///|
let _code_query : Byte = b'Q'

///|
let _code_parse : Byte = b'P'

///|
let _code_bind : Byte = b'B'

///|
let _code_execute : Byte = b'E'

///|
let _code_describe : Byte = b'D'

///|
let _code_close : Byte = b'C'

///|
let _code_sync : Byte = b'S'

///|
let _code_flush : Byte = b'H'

///|
let _code_terminate : Byte = b'X'

///|
let _code_password : Byte = b'p'

///|
let _code_copy_fail : Byte = b'f'

// =============================================================================
// Common Types
// =============================================================================

///|
/// Transaction status indicator from ReadyForQuery message
pub(all) enum TransactionStatus {
  /// Not in a transaction block
  Idle
  /// In a transaction block
  InTransaction
  /// In a failed transaction block (queries will be rejected until ROLLBACK)
  Failed
} derive(Show, Eq)

///|
/// Format code for data transmission
pub(all) enum FormatCode {
  /// Text format (default, human-readable)
  Text
  /// Binary format (more efficient, type-specific encoding)
  Binary
} derive(Show, Eq)

///|
/// Description of a field/column in query results
pub struct FieldDescription {
  /// Column name
  name : String
  /// OID of the table (0 if not a table column)
  table_oid : UInt
  /// Attribute number of the column (0 if not a table column)
  column_id : Int
  /// OID of the field's data type
  type_oid : UInt
  /// Data type size (negative for variable-width types)
  type_size : Int
  /// Type-specific modifier
  type_modifier : Int
  /// Format code (text or binary)
  format : FormatCode
} derive(Show)

///|
/// Create a new FieldDescription
pub fn FieldDescription::new(
  name : String,
  table_oid : UInt,
  column_id : Int,
  type_oid : UInt,
  type_size : Int,
  type_modifier : Int,
  format : FormatCode,
) -> FieldDescription {
  { name, table_oid, column_id, type_oid, type_size, type_modifier, format }
}

// =============================================================================
// Backend Messages (Server -> Client)
// =============================================================================

///|
/// Messages sent from PostgreSQL server to client
pub(all) enum BackendMessage {
  // --- Authentication Messages ---
  /// Authentication successful
  AuthenticationOk
  /// Server requests cleartext password
  AuthenticationCleartextPassword
  /// Server requests MD5-hashed password with salt
  AuthenticationMD5Password(Bytes) // 4-byte salt
  /// Server requests SASL authentication
  AuthenticationSASL(Array[String]) // list of mechanism names
  /// SASL authentication continue
  AuthenticationSASLContinue(Bytes)
  /// SASL authentication final
  AuthenticationSASLFinal(Bytes)

  // --- Connection Setup Messages ---
  /// Backend key data for cancel requests
  BackendKeyData(Int, Int) // process_id, secret_key
  /// Server parameter status
  ParameterStatus(String, String) // name, value
  /// Server ready for queries
  ReadyForQuery(TransactionStatus)
  /// Protocol version negotiation
  NegotiateProtocolVersion(Int, Array[String]) // newest_minor, unrecognized_options

  // --- Query Response Messages ---
  /// Row description (column metadata)
  RowDescription(Array[FieldDescription])
  /// Data row (column values)
  DataRow(Array[Bytes?]) // None = NULL
  /// Command completed successfully
  CommandComplete(String) // command tag
  /// Empty query string response
  EmptyQueryResponse

  // --- Extended Query Response Messages ---
  /// Parse completed
  ParseComplete
  /// Bind completed
  BindComplete
  /// Close completed
  CloseComplete
  /// No data to return
  NoData
  /// Parameter description
  ParameterDescription(Array[UInt]) // type OIDs
  /// Portal suspended (row limit reached)
  PortalSuspended

  // --- Error and Notice Messages ---
  /// Error occurred
  ErrorResponse(Map[String, String]) // field code -> value
  /// Warning/informational notice
  NoticeResponse(Map[String, String]) // field code -> value

  // --- Notification Messages ---
  /// Asynchronous notification
  NotificationResponse(Int, String, String) // process_id, channel, payload

  // --- Copy Messages ---
  /// Server ready for COPY IN
  CopyInResponse(FormatCode, Array[FormatCode]) // overall format, column formats
  /// Server sending COPY OUT data
  CopyOutResponse(FormatCode, Array[FormatCode])
  /// COPY data chunk
  CopyData(Bytes)
  /// COPY completed
  CopyDone
} derive(Show)

// =============================================================================
// Frontend Messages (Client -> Server)
// =============================================================================

///|
/// Messages sent from client to PostgreSQL server
pub(all) enum FrontendMessage {
  // --- Startup Messages ---
  /// Initial connection message
  StartupMessage(Map[String, String]) // parameters: user, database, etc.
  /// SSL request
  SSLRequest
  /// Cancel request (sent on separate connection)
  CancelRequest(Int, Int) // process_id, secret_key

  // --- Authentication Messages ---
  /// Password response (cleartext or MD5-hashed)
  PasswordMessage(String)
  /// SASL initial response
  SASLInitialResponse(String, Bytes) // mechanism, data
  /// SASL response
  SASLResponse(Bytes)

  // --- Simple Query ---
  /// Simple query (one or more SQL statements)
  Query(String)

  // --- Extended Query Protocol ---
  /// Parse SQL statement into prepared statement
  Parse(String, String, Array[UInt]) // name, query, param_type_oids
  /// Bind parameters to prepared statement, create portal
  Bind(String, String, Array[FormatCode], Array[Bytes?], Array[FormatCode]) // portal, statement, param_formats, params, result_formats
  /// Describe prepared statement or portal
  Describe(Byte, String) // 'S' or 'P', name
  /// Execute portal
  Execute(String, Int) // portal, max_rows (0 = unlimited)
  /// Close prepared statement or portal
  Close(Byte, String) // 'S' or 'P', name
  /// Sync (end of extended query, triggers commit/rollback)
  Sync
  /// Flush (force server to send pending output)
  Flush

  // --- Copy Messages ---
  /// Send COPY data
  CopyData(Bytes)
  /// COPY completed
  CopyDone
  /// COPY failed
  CopyFail(String) // error message

  // --- Termination ---
  /// Close connection
  Terminate
} derive(Show)

// =============================================================================
// Error Field Codes
// =============================================================================

///|
/// Error/Notice field identifiers
/// See https://www.postgresql.org/docs/current/protocol-error-fields.html
let _error_field_severity : String = "S"

///|
let _error_field_severity_v : String = "V" // non-localized severity

///|
let _error_field_code : String = "C" // SQLSTATE code

///|
let _error_field_message : String = "M"

///|
let _error_field_detail : String = "D"

///|
let _error_field_hint : String = "H"

///|
let _error_field_position : String = "P"

///|
let _error_field_internal_position : String = "p"

///|
let _error_field_internal_query : String = "q"

///|
let _error_field_where : String = "W"

///|
let _error_field_schema : String = "s"

///|
let _error_field_table : String = "t"

///|
let _error_field_column : String = "c"

///|
let _error_field_datatype : String = "d"

///|
let _error_field_constraint : String = "n"

///|
let _error_field_file : String = "F"

///|
let _error_field_line : String = "L"

///|
let _error_field_routine : String = "R"
