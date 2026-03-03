///| Low-Level Connection
///
/// Handles TCP connection and PostgreSQL protocol message exchange.

///|
/// Internal connection state
struct Connection {
  /// Configuration
  config : Config
  /// TCP socket
  socket : @socket.Tcp
  /// Protocol decoder
  decoder : @protocol.Decoder
  /// Backend process ID
  mut process_id : Int
  /// Backend secret key (for cancellation)
  mut secret_key : Int
  /// Current transaction status
  mut transaction_status : @protocol.TransactionStatus
  /// Server parameters
  server_params : Map[String, String]
}

///|
/// Create a new connection (internal use)
fn Connection::create(config : Config, socket : @socket.Tcp) -> Connection {
  {
    config,
    socket,
    decoder: @protocol.Decoder::new(),
    process_id: 0,
    secret_key: 0,
    transaction_status: @protocol.Idle,
    server_params: {},
  }
}

///|
/// Send a protocol message
async fn Connection::send(
  self : Connection,
  msg : @protocol.FrontendMessage,
) -> Unit {
  let bytes = @protocol.encode(msg)
  self.socket.write(bytes)
}

///|
/// Receive messages from server
async fn Connection::receive(
  self : Connection,
) -> Array[@protocol.BackendMessage] {
  // Read available data
  match self.socket.read_some() {
    Some(data) => self.decoder.parse(data)
    None => raise ConnectionClosedError
  }
}

///|
/// Receive messages until ReadyForQuery
async fn Connection::receive_until_ready(
  self : Connection,
) -> Array[@protocol.BackendMessage] {
  let all_messages : Array[@protocol.BackendMessage] = []

  while true {
    let messages = self.receive()
    for msg in messages {
      all_messages.push(msg)
      match msg {
        @protocol.ReadyForQuery(status) => {
          self.transaction_status = status
          return all_messages
        }
        @protocol.ErrorResponse(_) =>
          // Continue receiving but remember the error
          ()
        _ => ()
      }
    }
  } nobreak {
    all_messages
  }
}

///|
/// Check if there's an error in messages
fn find_error(messages : Array[@protocol.BackendMessage]) -> ServerErrorInfo? {
  for msg in messages {
    match msg {
      @protocol.ErrorResponse(fields) =>
        return Some(ServerErrorInfo::from_fields(fields))
      _ => ()
    }
  }
  None
}

///|
/// Get server parameter
fn Connection::get_server_param(self : Connection, name : String) -> String? {
  self.server_params.get(name)
}

///|
/// Close the connection, sending Terminate message first
async fn Connection::close(self : Connection) -> Unit {
  try {
    self.send(@protocol.Terminate)
  } catch {
    _ => () // Best effort — socket may already be broken
  }
  self.socket.close()
}

// =============================================================================
// Connection Establishment
// =============================================================================

///|
/// Connect to PostgreSQL server
async fn connect(config : Config) -> Connection {
  // Resolve address
  let addr = @socket.Addr::resolve(config.host, port=config.port)

  // Connect TCP socket
  let socket = @socket.Tcp::connect(addr)

  let conn = Connection::create(config, socket)

  // Perform startup and authentication
  conn.startup()

  conn
}

///|
/// Perform startup and authentication
async fn Connection::startup(self : Connection) -> Unit {
  // Build startup parameters
  let params : Map[String, String] = {}
  params["user"] = self.config.user
  params["database"] = self.config.database

  // Send StartupMessage
  self.send(@protocol.StartupMessage(params))

  // Handle authentication
  self.authenticate()
}

///|
/// Handle authentication flow
async fn Connection::authenticate(self : Connection) -> Unit {
  while true {
    let messages = self.receive()

    for msg in messages {
      match msg {
        @protocol.AuthenticationOk =>
          // Authentication successful, continue to receive startup messages
          ()
        @protocol.AuthenticationCleartextPassword =>
          // Send password in cleartext
          self.send(@protocol.PasswordMessage(self.config.password))
        @protocol.AuthenticationMD5Password(salt) => {
          // Compute MD5 hash
          let hash = @protocol.md5_password(
            self.config.password,
            self.config.user,
            salt,
          )
          self.send(@protocol.PasswordMessage(hash))
        }
        @protocol.ParameterStatus(name, value) =>
          self.server_params[name] = value
        @protocol.BackendKeyData(pid, key) => {
          self.process_id = pid
          self.secret_key = key
        }
        @protocol.ReadyForQuery(status) => {
          self.transaction_status = status
          return
        }
        @protocol.AuthenticationSASL(_) =>
          raise AuthError("SASL authentication is not supported")
        @protocol.ErrorResponse(fields) => {
          let info = ServerErrorInfo::from_fields(fields)
          raise AuthError(info.message)
        }
        _ => ()
      }
    }
  }
}
