///| Low-Level Connection
///
/// Handles TCP connection and PostgreSQL protocol message exchange.

///|
/// Internal connection state
priv struct Connection {
  /// Configuration
  config : Config
  /// Transport (TCP or TLS)
  transport : Transport
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
  /// Queue of received notifications
  notification_queue : Array[Notification]
}

///|
/// Create a new connection (internal use)
fn Connection::create(config : Config, transport : Transport) -> Connection {
  {
    config,
    transport,
    decoder: @protocol.Decoder::new(),
    process_id: 0,
    secret_key: 0,
    transaction_status: @protocol.Idle,
    server_params: {},
    notification_queue: [],
  }
}

///|
/// Send a protocol message
async fn Connection::send(
  self : Connection,
  msg : @protocol.FrontendMessage,
) -> Unit {
  let bytes = @protocol.encode(msg)
  self.transport.write(bytes)
}

///|
/// Send multiple protocol messages in a single write to reduce syscalls
async fn Connection::send_all(
  self : Connection,
  msgs : Array[@protocol.FrontendMessage],
) -> Unit {
  let buf : Array[Byte] = []
  for msg in msgs {
    let bytes = @protocol.encode(msg)
    for i = 0; i < bytes.length(); i = i + 1 {
      buf.push(bytes[i])
    }
  }
  self.transport.write(Bytes::from_array(buf))
}

///|
/// Receive messages from server
///
/// Note: read_some() blocks until data arrives. The underlying socket library
/// does not currently expose timeout configuration, so a hung server will
/// cause the caller to block indefinitely. This is a known limitation.
async fn Connection::receive(
  self : Connection,
) -> Array[@protocol.BackendMessage] {
  // Read available data
  match self.transport.read_some() {
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
      match msg {
        @protocol.NotificationResponse(pid, channel, payload) =>
          self.notification_queue.push(Notification::new(channel, payload, pid))
        @protocol.ReadyForQuery(status) => {
          all_messages.push(msg)
          self.transaction_status = status
          return all_messages
        }
        _ => all_messages.push(msg)
      }
    }
  } nobreak {
    all_messages
  }
}

///|
/// Raise ServerError if messages contain an error
fn check_error(
  messages : Array[@protocol.BackendMessage],
) -> Unit raise ServerError {
  for msg in messages {
    match msg {
      @protocol.ErrorResponse(fields) =>
        raise ServerError(ServerErrorInfo::from_fields(fields))
      _ => ()
    }
  }
}

///|
/// Server parameter
fn Connection::server_param(self : Connection, name : String) -> String? {
  self.server_params.get(name)
}

///|
/// Close the connection, sending Terminate message first
async fn Connection::close(self : Connection) -> Unit {
  self.send(@protocol.Terminate) catch {
    _ => () // Best effort — socket may already be broken
  }
  self.transport.close()
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
  let tcp = @socket.Tcp::connect(addr)

  // Negotiate transport (plain TCP or TLS)
  let transport = negotiate_transport(tcp, config)

  let conn = Connection::create(config, transport)

  // Perform startup and authentication
  conn.startup()

  conn
}

///|
/// Negotiate TLS transport based on SSL mode configuration.
///
/// PostgreSQL TLS negotiation: send SSLRequest, read single-byte response.
/// 'S' (0x53) = server accepts TLS, 'N' (0x4E) = server refuses.
async fn negotiate_transport(tcp : @socket.Tcp, config : Config) -> Transport {
  match config.ssl_mode {
    Disable => PlainTcp(tcp)
    Prefer | Require | VerifyFull => {
      // Send SSLRequest message
      tcp.write(@protocol.encode(@protocol.SSLRequest))
      // Read single-byte response
      match tcp.read_some() {
        Some(data) if data.length() > 0 && data[0] == b'S' => {
          let verify = config.ssl_mode is VerifyFull
          let tls = @tls.Tls::client(tcp, verify~, host=config.host)
          TlsConn(tls, tcp)
        }
        _ if config.ssl_mode is Prefer => PlainTcp(tcp)
        _ => raise AuthError("Server rejected SSL connection")
      }
    }
  }
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
/// Generate a random nonce for SCRAM authentication.
/// Uses random bytes, base64-encoded.
fn generate_nonce() -> String {
  let now = @async.now()
  let seed_bytes = Bytes::makei(32, fn(i) {
    ((now >> (i % 8 * 8)) & 0xFFL).to_byte()
  })
  let rng = @random.Rand::chacha8(seed=seed_bytes)
  let random_bytes = Bytes::makei(18, fn(_i) { rng.uint(limit=256).to_byte() })
  @base64.encode(random_bytes[:])
}

///|
/// Handle authentication flow
async fn Connection::authenticate(self : Connection) -> Unit {
  // SCRAM state tracked across auth loop iterations
  let mut scram_nonce = ""
  let mut scram_client_first_bare = ""
  let mut scram_expected_sig : Bytes = b""

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
        @protocol.AuthenticationSASL(mechanisms) => {
          // SCRAM-SHA-256 initial handshake
          guard mechanisms.contains("SCRAM-SHA-256") else {
            raise AuthError("Server requires unsupported SASL mechanism")
          }
          let nonce = generate_nonce()
          let (client_first, client_first_bare) = @protocol.scram_client_first(
            self.config.user,
            nonce,
          )
          scram_nonce = nonce
          scram_client_first_bare = client_first_bare
          self.send(
            @protocol.SASLInitialResponse(
              "SCRAM-SHA-256",
              @utf8.encode(client_first[:]),
            ),
          )
        }
        @protocol.AuthenticationSASLContinue(data) => {
          // SCRAM server-first-message → compute client-final
          let server_first = @utf8.decode_lossy(data[:])
          let (client_final, expected_sig) = @protocol.scram_client_final(
            self.config.password,
            scram_client_first_bare,
            server_first,
            scram_nonce,
          ) catch {
            @protocol.ScramError(msg) => raise AuthError(msg)
          }
          scram_expected_sig = expected_sig
          self.send(@protocol.SASLResponse(@utf8.encode(client_final[:])))
        }
        @protocol.AuthenticationSASLFinal(data) => {
          // SCRAM server-final-message → verify server signature
          let server_final = @utf8.decode_lossy(data[:])
          @protocol.scram_verify_server(server_final, scram_expected_sig) catch {
            @protocol.ScramError(msg) => raise AuthError(msg)
          }
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
        @protocol.ErrorResponse(fields) => {
          let info = ServerErrorInfo::from_fields(fields)
          raise AuthError(info.message)
        }
        _ => ()
      }
    }
  }
}
