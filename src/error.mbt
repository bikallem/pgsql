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
pub suberror ServerErr {
  ServerErr(ServerErrorInfo)
}

///|
/// Transaction error
pub suberror TxError {
  TxError(String)
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
  let severity = match fields.get("S") {
    Some(s) => s
    None =>
      match fields.get("V") {
        Some(v) => v
        None => "ERROR"
      }
  }
  {
    severity,
    code: fields.get("C").unwrap_or(""),
    message: fields.get("M").unwrap_or("Unknown error"),
    detail: fields.get("D"),
    hint: fields.get("H"),
    table: fields.get("t"),
    column: fields.get("c"),
    constraint: fields.get("n"),
  }
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
pub impl Show for ServerErr with output(self, logger) {
  let ServerErr(info) = self
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
