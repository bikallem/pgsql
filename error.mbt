///| PostgreSQL Error Types
///
/// Defines error types for PostgreSQL operations.

///|
/// Connection closed error
pub suberror ConnectionClosedError

///|
/// Client usage error
pub suberror ClientUsageError {
  ClientUsageError(String)
}

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
/// Structured details for user callback failures in COPY operations.
pub struct CopyCallbackFailure {
  /// Callback stage where failure happened.
  stage : String
  /// Original callback error rendered as text.
  message : String
} derive(Show, Eq)

///|
/// COPY operation error
pub suberror CopyError {
  CopyError(String)
  CopyCallbackError(CopyCallbackFailure)
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
fn ServerErrorInfo::from_fields(
  fields : Map[String, String],
) -> ServerErrorInfo {
  let severity = fields
    .get(FIELD_SEVERITY)
    .unwrap_or_else(fn() { fields.get(FIELD_SEVERITY_NL).unwrap_or("ERROR") })
  {
    severity,
    code: fields.get(FIELD_CODE).unwrap_or(""),
    message: fields.get(FIELD_MESSAGE).unwrap_or("Unknown error"),
    detail: fields.get(FIELD_DETAIL),
    hint: fields.get(FIELD_HINT),
    table: fields.get(FIELD_TABLE),
    column: fields.get(FIELD_COLUMN),
    constraint: fields.get(FIELD_CONSTRAINT),
  }
}

///|
/// Implement Show for suberrors
pub impl Show for ConnectionClosedError with output(_self, logger) {
  logger.write_string("ConnectionClosedError")
}

///|
pub impl Show for ClientUsageError with output(self, logger) {
  let ClientUsageError(msg) = self
  logger.write_string("ClientUsageError: ")
  logger.write_string(msg)
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
  match self {
    CopyError(msg) => {
      logger.write_string("CopyError: ")
      logger.write_string(msg)
    }
    CopyCallbackError(failure) => {
      logger.write_string("CopyCallbackError[")
      logger.write_string(failure.stage)
      logger.write_string("]: ")
      logger.write_string(failure.message)
    }
  }
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
