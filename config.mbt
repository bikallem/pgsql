///| Connection Configuration
///
/// Defines configuration options for PostgreSQL connections.

///|
/// SSL/TLS mode for the connection
pub(all) enum SslMode {
  /// Never use TLS
  Disable
  /// Try TLS, fall back to plain if server refuses
  Prefer
  /// Must use TLS, skip certificate verification
  Require
  /// TLS with certificate verification
  VerifyFull
} derive(Show, Eq)

///|
/// Configuration for PostgreSQL connection
struct Config {
  /// Hostname of the PostgreSQL server
  host : String
  /// Port number (default: 5432)
  port : Int
  /// Username for authentication
  user : String
  /// Password for authentication
  password : String
  /// Database name to connect to
  database : String
  /// SSL/TLS mode (default: Require)
  ssl_mode : SslMode
  /// Read timeout in milliseconds (0 = no timeout)
  read_timeout : Int
}

///|
/// Show implementation that masks the password
pub impl Show for Config with output(self, logger) {
  logger.write_string("Config { host: ")
  logger.write_string(self.host)
  logger.write_string(", port: ")
  Show::output(self.port, logger)
  logger.write_string(", user: ")
  logger.write_string(self.user)
  logger.write_string(", password: ****, database: ")
  logger.write_string(self.database)
  logger.write_string(", ssl_mode: ")
  Show::output(self.ssl_mode, logger)
  logger.write_string(" }")
}

///|
/// Create a new Config with default values
pub fn Config::new(
  user : String,
  password : String,
  database : String,
  host? : String = "localhost",
  port? : Int = 5432,
  ssl_mode? : SslMode = Require,
  read_timeout? : Int = 0,
) -> Config {
  { host, port, user, password, database, ssl_mode, read_timeout }
}

///|
/// Host
pub fn Config::host(self : Config) -> String {
  self.host
}

///|
/// Port
pub fn Config::port(self : Config) -> Int {
  self.port
}

///|
/// User
pub fn Config::user(self : Config) -> String {
  self.user
}

///|
/// Password
pub fn Config::password(self : Config) -> String {
  self.password
}

///|
/// Database
pub fn Config::database(self : Config) -> String {
  self.database
}

///|
/// SSL mode
pub fn Config::ssl_mode(self : Config) -> SslMode {
  self.ssl_mode
}
