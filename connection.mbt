///| Low-Level Connection
///
/// Handles TCP connection and PostgreSQL protocol message exchange.

///|
/// FIFO queue for notifications with amortized O(1) dequeue.
/// Uses a moving head index and periodic compaction to avoid per-pop array rebuilds.
priv struct NotificationQueue {
  items : Array[Notification]
  mut head : Int
}

///|
fn NotificationQueue::new() -> NotificationQueue {
  { items: [], head: 0 }
}

///|
fn NotificationQueue::enqueue(
  self : NotificationQueue,
  notification : Notification,
) -> Unit {
  self.items.push(notification)
}

///|
fn NotificationQueue::dequeue(self : NotificationQueue) -> Notification? {
  if self.head >= self.items.length() {
    self.items.clear()
    self.head = 0
    return None
  }
  let notification = self.items[self.head]
  self.head += 1
  self.compact_if_needed()
  Some(notification)
}

///|
fn NotificationQueue::drain(self : NotificationQueue) -> Array[Notification] {
  if self.head >= self.items.length() {
    self.items.clear()
    self.head = 0
    return []
  }
  if self.head == 0 {
    let result = self.items.copy()
    self.items.clear()
    self.head = 0
    return result
  }
  let result : Array[Notification] = Array::new(
    capacity=self.items.length() - self.head,
  )
  for i = self.head; i < self.items.length(); i = i + 1 {
    result.push(self.items[i])
  }
  self.items.clear()
  self.head = 0
  result
}

///|
/// Compact once head has advanced enough to reclaim significant space.
fn NotificationQueue::compact_if_needed(self : NotificationQueue) -> Unit {
  if self.head == 0 {
    return
  }
  let len = self.items.length()
  if self.head >= len {
    self.items.clear()
    self.head = 0
    return
  }
  // Avoid frequent compaction for small queues; compact when head consumed
  // at least half of the queue and crossed a practical threshold.
  if self.head < 128 || self.head * 2 < len {
    return
  }
  // Drain the consumed prefix in-place.
  ignore((self.items.drain(0, self.head) : Array[Notification]))
  self.head = 0
}

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
  notification_queue : NotificationQueue
  /// True while COPY FROM STDIN is active on this connection.
  mut copy_in_active : Bool
  /// Serialize protocol operations on this connection
  operation_guard : @async.Semaphore
}

///|
/// Result of processing a backend control message with connection side effects.
priv enum BackendDispatchAction {
  QueueNotification(Notification)
  UpdateParameter(String, String)
  UpdateReady(@protocol.TransactionStatus)
  Ignore
}

///|
/// Classify backend messages that mutate connection state out of band.
fn classify_backend_dispatch_message(
  msg : @protocol.BackendMessage,
) -> BackendDispatchAction {
  match msg {
    @protocol.NotificationResponse(pid, channel, payload) =>
      QueueNotification(Notification::new(channel, payload, pid))
    @protocol.ParameterStatus(name, value) => UpdateParameter(name, value)
    @protocol.ReadyForQuery(status) => UpdateReady(status)
    _ => Ignore
  }
}

///|
/// Result of applying backend dispatch action to connection state.
priv enum BackendDispatchResult {
  Consumed
  Ready
  Unhandled
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
    notification_queue: NotificationQueue::new(),
    copy_in_active: false,
    operation_guard: @async.Semaphore::new(1),
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
  if msgs.length() == 0 {
    return
  }
  self.transport.write(encode_frontend_batch(msgs))
}

///|
/// Encode a frontend message batch into a single contiguous frame.
fn encode_frontend_batch(msgs : Array[@protocol.FrontendMessage]) -> Bytes {
  if msgs.length() == 1 {
    return @protocol.encode(msgs[0])
  }
  let buf : Array[Byte] = []
  for msg in msgs {
    let bytes = @protocol.encode(msg)
    for i = 0; i < bytes.length(); i = i + 1 {
      buf.push(bytes[i])
    }
  }
  Bytes::from_array(buf)
}

///|
/// Receive messages from server.
/// If a read_timeout is configured, the read will fail with
/// ConnectionClosedError after the timeout expires.
async fn Connection::receive(
  self : Connection,
) -> Array[@protocol.BackendMessage] {
  let data = if self.config.read_timeout > 0 {
    @async.with_timeout(
      self.config.read_timeout,
      async fn() { self.transport.read_some() },
      error=ConnectionClosedError,
    )
  } else {
    self.transport.read_some()
  }
  match data {
    Some(d) => self.decoder.parse(d)
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
      match self.dispatch_backend_message(msg) {
        Ready => {
          all_messages.push(msg)
          return all_messages
        }
        Consumed => ()
        Unhandled => all_messages.push(msg)
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
    match server_error_from_message(msg) {
      Some(info) => raise ServerError(info)
      None => ()
    }
  }
}

///|
/// Parse ErrorResponse into structured server error info.
fn server_error_from_message(
  msg : @protocol.BackendMessage,
) -> ServerErrorInfo? {
  match msg {
    @protocol.ErrorResponse(fields) =>
      Some(ServerErrorInfo::from_fields(fields))
    _ => None
  }
}

///|
/// Raise ServerError when backend message is ErrorResponse.
fn raise_if_server_error_message(
  msg : @protocol.BackendMessage,
) -> Unit raise ServerError {
  match server_error_from_message(msg) {
    Some(info) => raise ServerError(info)
    None => ()
  }
}

///|
/// Apply shared side effects from backend control messages.
fn Connection::dispatch_backend_message(
  self : Connection,
  msg : @protocol.BackendMessage,
) -> BackendDispatchResult {
  match classify_backend_dispatch_message(msg) {
    QueueNotification(notification) => {
      self.notification_queue.enqueue(notification)
      Consumed
    }
    UpdateParameter(name, value) => {
      self.server_params[name] = value
      Consumed
    }
    UpdateReady(status) => {
      self.transaction_status = status
      Ready
    }
    Ignore => Unhandled
  }
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
/// Send a PostgreSQL CancelRequest on a separate TCP connection.
/// This is intentionally independent of the main connection/socket.
async fn cancel_request(
  config : Config,
  process_id : Int,
  secret_key : Int,
) -> Unit {
  let addr = @socket.Addr::resolve(config.host, port=config.port)
  let tcp = @socket.Tcp::connect(addr)
  tcp.write(@protocol.encode(@protocol.CancelRequest(process_id, secret_key)))
  tcp.close()
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
/// FFI: fill buffer with OS-level cryptographically secure random bytes.
/// Returns 0 on success, -1 on failure.
#borrow(buf)
extern "C" fn getrandom_ffi(buf : FixedArray[Byte], len : Int) -> Int = "pgsql_getrandom"

///|
/// Generate cryptographically secure random bytes using the OS CSPRNG.
fn secure_random_bytes(len : Int) -> Bytes raise {
  let buf = FixedArray::make(len, b'\x00')
  guard getrandom_ffi(buf, len) == 0 else {
    raise AuthError("getrandom failed")
  }
  buf.unsafe_reinterpret_as_bytes()
}

///|
/// Generate a random nonce for SCRAM authentication.
/// Uses OS CSPRNG (getrandom/SecRandomCopyBytes/BCryptGenRandom), base64-encoded.
fn generate_nonce() -> String {
  let random_bytes = secure_random_bytes(18) catch {
    _ => {
      // Fallback: timestamp-seeded ChaCha8 if OS CSPRNG unavailable
      let now = @async.now()
      let seed_bytes = Bytes::makei(32, fn(i) {
        ((now >> (i % 8 * 8)) & 0xFFL).to_byte()
      })
      let rng = @random.Rand::chacha8(seed=seed_bytes)
      Bytes::makei(18, fn(_i) { rng.uint(limit=256).to_byte() })
    }
  }
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
        @protocol.BackendKeyData(pid, key) => {
          self.process_id = pid
          self.secret_key = key
        }
        _ =>
          match self.dispatch_backend_message(msg) {
            Ready => return
            Consumed => ()
            Unhandled =>
              match server_error_from_message(msg) {
                Some(info) => raise AuthError(info.message)
                None => ()
              }
          }
      }
    }
  }
}
