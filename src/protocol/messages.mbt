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

// =============================================================================
// Backend Message Type Codes (Server -> Client)
// =============================================================================

///|
/// Authentication message
const BACKEND_AUTH : Byte = b'R'

///|
/// Backend key data (process ID and secret key)
const BACKEND_KEY_DATA : Byte = b'K'

///|
/// Parameter status
const BACKEND_PARAM_STATUS : Byte = b'S'

///|
/// Ready for query
const BACKEND_READY : Byte = b'Z'

///|
/// Row description (column metadata)
const BACKEND_ROW_DESC : Byte = b'T'

///|
/// Data row
const BACKEND_DATA_ROW : Byte = b'D'

///|
/// Command complete
const BACKEND_CMD_COMPLETE : Byte = b'C'

///|
/// Error response
const BACKEND_ERROR : Byte = b'E'

///|
/// Notice response
const BACKEND_NOTICE : Byte = b'N'

///|
/// Parse complete
const BACKEND_PARSE_COMPLETE : Byte = b'1'

///|
/// Bind complete
const BACKEND_BIND_COMPLETE : Byte = b'2'

///|
/// Close complete
const BACKEND_CLOSE_COMPLETE : Byte = b'3'

///|
/// No data
const BACKEND_NO_DATA : Byte = b'n'

///|
/// Empty query response
const BACKEND_EMPTY_QUERY : Byte = b'I'

///|
/// Portal suspended
const BACKEND_PORTAL_SUSPENDED : Byte = b's'

///|
/// Parameter description
const BACKEND_PARAM_DESC : Byte = b't'

///|
/// Notification response
const BACKEND_NOTIFICATION : Byte = b'A'

///|
/// Copy in response
const BACKEND_COPY_IN : Byte = b'G'

///|
/// Copy out response
const BACKEND_COPY_OUT : Byte = b'H'

///|
/// Copy data
const BACKEND_COPY_DATA : Byte = b'd'

///|
/// Copy done
const BACKEND_COPY_DONE : Byte = b'c'

// =============================================================================
// Frontend Message Type Codes (Client -> Server)
// =============================================================================

///|
/// Simple query
const CODE_QUERY : Byte = b'Q'

///|
/// Parse
const CODE_PARSE : Byte = b'P'

///|
/// Bind
const CODE_BIND : Byte = b'B'

///|
/// Execute
const CODE_EXECUTE : Byte = b'E'

///|
/// Describe
const CODE_DESCRIBE : Byte = b'D'

///|
/// Close
const CODE_CLOSE : Byte = b'C'

///|
/// Sync
const CODE_SYNC : Byte = b'S'

///|
/// Flush
const CODE_FLUSH : Byte = b'H'

///|
/// Terminate
const CODE_TERMINATE : Byte = b'X'

///|
/// Password / SASL response
const CODE_PASSWORD : Byte = b'p'

///|
/// Copy data (frontend)
const CODE_COPY_DATA : Byte = b'd'

///|
/// Copy done (frontend)
const CODE_COPY_DONE : Byte = b'c'

///|
/// Copy fail
const CODE_COPY_FAIL : Byte = b'f'

// =============================================================================
// Transaction Status Bytes
// =============================================================================

///|
/// Idle (not in transaction)
const TX_IDLE : Byte = b'I'

///|
/// In transaction block
const TX_IN_TRANSACTION : Byte = b'T'

// =============================================================================
// Describe/Close Target Types
// =============================================================================

///|
/// Statement target for Describe and Close messages
pub const TARGET_STATEMENT : Byte = b'S'

///|
/// Portal target for Describe and Close messages
pub const TARGET_PORTAL : Byte = b'P'

// =============================================================================
// Error/Notice Field Keys
// =============================================================================

///|
/// Severity field (localized)
pub const FIELD_SEVERITY : String = "S"

///|
/// Severity field (non-localized)
pub const FIELD_SEVERITY_NL : String = "V"

///|
/// SQLSTATE error code
pub const FIELD_CODE : String = "C"

///|
/// Human-readable error message
pub const FIELD_MESSAGE : String = "M"

///|
/// Detail message
pub const FIELD_DETAIL : String = "D"

///|
/// Hint message
pub const FIELD_HINT : String = "H"

///|
/// Table name
pub const FIELD_TABLE : String = "t"

///|
/// Column name
pub const FIELD_COLUMN : String = "c"

///|
/// Constraint name
pub const FIELD_CONSTRAINT : String = "n"

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
struct FieldDescription {
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
/// Column name
pub fn FieldDescription::name(self : FieldDescription) -> String {
  self.name
}

///|
/// OID of the field's data type
pub fn FieldDescription::type_oid(self : FieldDescription) -> UInt {
  self.type_oid
}

///|
/// Data type size (negative for variable-width types)
pub fn FieldDescription::type_size(self : FieldDescription) -> Int {
  self.type_size
}

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
