///| PostgreSQL Error Types
///
/// Defines error types for PostgreSQL operations.

///|
/// Connection closed error
pub suberror ConnectionClosedError

///|
/// Authentication error
pub suberror AuthError {
  AuthError(String)
}

///|
/// Server error with details
pub suberror ServerError {
  ServerError(ServerErrorInfo)
}

///|
/// Transaction error
pub suberror TxError {
  TxError(String)
}

///|
/// Prepared statement error
pub suberror PreparedStmtError {
  PreparedStmtError(String)
}

///|
/// COPY operation error
pub suberror CopyError {
  CopyError(String)
}

///|
/// Connection pool error
pub suberror PoolError {
  PoolError(String)
}

///|
/// Row stream error
pub suberror StreamError {
  StreamError(String)
}

///|
/// Detailed server error information from ErrorResponse
pub struct ServerErrorInfo {
  /// Error severity (ERROR, FATAL, PANIC)
  severity : String
  /// SQLSTATE error code
  code : String
  /// Error message
  message : String
  /// Optional detail message
  detail : String?
  /// Optional hint
  hint : String?
  /// Optional table name
  table : String?
  /// Optional column name
  column : String?
  /// Optional constraint name
  constraint : String?
} derive(Show, Eq)

///|
/// Create a ServerErrorInfo from error response fields
pub fn ServerErrorInfo::from_fields(
  fields : Map[String, String],
) -> ServerErrorInfo {
  // Get severity from S or V field
  let severity = match fields.get(@protocol.FIELD_SEVERITY) {
    Some(s) => s
    None =>
      match fields.get(@protocol.FIELD_SEVERITY_NL) {
        Some(v) => v
        None => "ERROR"
      }
  }
  {
    severity,
    code: fields.get(@protocol.FIELD_CODE).unwrap_or(""),
    message: fields.get(@protocol.FIELD_MESSAGE).unwrap_or("Unknown error"),
    detail: fields.get(@protocol.FIELD_DETAIL),
    hint: fields.get(@protocol.FIELD_HINT),
    table: fields.get(@protocol.FIELD_TABLE),
    column: fields.get(@protocol.FIELD_COLUMN),
    constraint: fields.get(@protocol.FIELD_CONSTRAINT),
  }
}

///|
/// Error severity (ERROR, FATAL, PANIC)
pub fn ServerErrorInfo::severity(self : ServerErrorInfo) -> String {
  self.severity
}

///|
/// SQLSTATE error code (e.g. "23505" for unique violation)
pub fn ServerErrorInfo::code(self : ServerErrorInfo) -> String {
  self.code
}

///|
/// Error message
pub fn ServerErrorInfo::message(self : ServerErrorInfo) -> String {
  self.message
}

///|
/// Optional detail message
pub fn ServerErrorInfo::detail(self : ServerErrorInfo) -> String? {
  self.detail
}

///|
/// Optional hint
pub fn ServerErrorInfo::hint(self : ServerErrorInfo) -> String? {
  self.hint
}

///|
/// Optional table name
pub fn ServerErrorInfo::table(self : ServerErrorInfo) -> String? {
  self.table
}

///|
/// Optional column name
pub fn ServerErrorInfo::column(self : ServerErrorInfo) -> String? {
  self.column
}

///|
/// Optional constraint name
pub fn ServerErrorInfo::constraint(self : ServerErrorInfo) -> String? {
  self.constraint
}

///|
/// Implement Show for suberrors
pub impl Show for ConnectionClosedError with output(_self, logger) {
  logger.write_string("ConnectionClosedError")
}

///|
pub impl Show for AuthError with output(self, logger) {
  let AuthError(msg) = self
  logger.write_string("AuthError: ")
  logger.write_string(msg)
}

///|
pub impl Show for ServerError with output(self, logger) {
  let ServerError(info) = self
  logger.write_string("ServerError: [")
  logger.write_string(info.code)
  logger.write_string("] ")
  logger.write_string(info.message)
}

///|
pub impl Show for TxError with output(self, logger) {
  let TxError(msg) = self
  logger.write_string("TransactionError: ")
  logger.write_string(msg)
}

///|
pub impl Show for PreparedStmtError with output(self, logger) {
  let PreparedStmtError(msg) = self
  logger.write_string("PreparedStatementError: ")
  logger.write_string(msg)
}

///|
pub impl Show for CopyError with output(self, logger) {
  let CopyError(msg) = self
  logger.write_string("CopyError: ")
  logger.write_string(msg)
}

///|
pub impl Show for PoolError with output(self, logger) {
  let PoolError(msg) = self
  logger.write_string("PoolError: ")
  logger.write_string(msg)
}

///|
pub impl Show for StreamError with output(self, logger) {
  let StreamError(msg) = self
  logger.write_string("StreamError: ")
  logger.write_string(msg)
}
