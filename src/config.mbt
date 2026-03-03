///| Connection Configuration
///
/// Defines configuration options for PostgreSQL connections.

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
) -> Config {
  { host, port, user, password, database }
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
