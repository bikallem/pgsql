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
pub struct Config {
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
  /// SSL/TLS mode (default: Disable)
  ssl_mode : SslMode
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
  ssl_mode? : SslMode = Disable,
) -> Config {
  { host, port, user, password, database, ssl_mode }
}

///|
/// Get the host
pub fn Config::get_host(self : Config) -> String {
  self.host
}

///|
/// Get the port
pub fn Config::get_port(self : Config) -> Int {
  self.port
}

///|
/// Get the user
pub fn Config::get_user(self : Config) -> String {
  self.user
}

///|
/// Get the password
pub fn Config::get_password(self : Config) -> String {
  self.password
}

///|
/// Get the database
pub fn Config::get_database(self : Config) -> String {
  self.database
}

///|
/// Get the SSL mode
pub fn Config::get_ssl_mode(self : Config) -> SslMode {
  self.ssl_mode
}
