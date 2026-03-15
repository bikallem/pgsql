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
  let result = self.items.drain(self.head, self.items.length())
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
  decoder : Decoder
  /// Backend process ID
  mut process_id : Int
  /// Backend secret key (for cancellation)
  mut secret_key : Int
  /// Current transaction status
  mut transaction_status : TransactionStatus
  /// Server parameters
  server_params : Map[String, String]
  /// Queue of received notifications
  notification_queue : NotificationQueue
  /// Queue of received notices (warnings, informational messages)
  notice_queue : Array[ServerErrorInfo]
  /// True while COPY FROM STDIN is active on this connection.
  mut copy_in_active : Bool
  /// Serialize protocol operations on this connection
  operation_guard : @async.Semaphore
}

///|
/// Query-relevant messages passed through by dispatch after connection-level
/// messages have been consumed. This is the narrower type that callers work with.
priv enum QueryMessage {
  RowDescription(Array[FieldDescription])
  DataRow(Array[Bytes?])
  CommandComplete(String)
  EmptyQueryResponse
  ErrorResponse(Map[String, String])
  ParseComplete
  BindComplete
  NoData
  PortalSuspended
  ParameterDescription(Array[UInt])
  CopyInResponse
  CopyOutResponse
  CopyData(Bytes)
  CopyDone
}

///|
/// Result of dispatching a backend message.
priv enum DispatchResult {
  /// Message consumed (connection state updated, notice queued, etc.)
  Consumed
  /// ReadyForQuery received — stop receiving
  Ready
  /// Query-relevant message passed through for caller processing
  Message(QueryMessage)
}

///|
/// Create a new connection (internal use)
fn Connection::create(config : Config, transport : Transport) -> Connection {
  {
    config,
    transport,
    decoder: Decoder::new(),
    process_id: 0,
    secret_key: 0,
    transaction_status: Idle,
    server_params: {},
    notification_queue: NotificationQueue::new(),
    notice_queue: [],
    copy_in_active: false,
    operation_guard: @async.Semaphore::new(1),
  }
}

///|
/// Send a protocol message
async fn Connection::send(self : Connection, msg : FrontendMessage) -> Unit {
  let bytes = encode(msg)
  self.transport.write(bytes)
}

///|
/// Send multiple protocol messages in a single write to reduce syscalls
async fn Connection::send_all(
  self : Connection,
  msgs : Array[FrontendMessage],
) -> Unit {
  if msgs.length() == 0 {
    return
  }
  self.transport.write(encode_frontend_batch(msgs))
}

///|
/// Encode a frontend message batch into a single contiguous frame.
fn encode_frontend_batch(msgs : Array[FrontendMessage]) -> Bytes {
  if msgs.length() == 1 {
    return encode(msgs[0])
  }
  let buf : Array[Byte] = []
  for msg in msgs {
    let bytes = encode(msg)
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
async fn Connection::receive(self : Connection) -> Array[BackendMessage] {
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
/// Format an unexpected QueryMessage for error reporting.
fn unexpected_message(context : String, qm : QueryMessage) -> String {
  let name = match qm {
    RowDescription(_) => "RowDescription"
    DataRow(_) => "DataRow"
    CommandComplete(_) => "CommandComplete"
    EmptyQueryResponse => "EmptyQueryResponse"
    ErrorResponse(_) => "ErrorResponse"
    ParseComplete => "ParseComplete"
    BindComplete => "BindComplete"
    NoData => "NoData"
    PortalSuspended => "PortalSuspended"
    ParameterDescription(_) => "ParameterDescription"
    CopyInResponse => "CopyInResponse"
    CopyOutResponse => "CopyOutResponse"
    CopyData(_) => "CopyData"
    CopyDone => "CopyDone"
  }
  "Unexpected " + name + " during " + context
}

///|
/// Receive messages until ReadyForQuery
async fn Connection::receive_until_ready(
  self : Connection,
) -> Array[QueryMessage] {
  let result : Array[QueryMessage] = []
  while true {
    let messages = self.receive()
    for msg in messages {
      match self.dispatch(msg) {
        Ready => return result
        Consumed => ()
        Message(qm) => result.push(qm)
      }
    }
  } nobreak {
    result
  }
}

///|
/// Raise ServerError if query messages contain an error.
fn check_error(messages : Array[QueryMessage]) -> Unit raise ServerError {
  for msg in messages {
    match msg {
      ErrorResponse(fields) => raise ServerError(ServerErrorInfo::from_fields(fields))
      RowDescription(_) | DataRow(_) | CommandComplete(_) |
      EmptyQueryResponse | ParseComplete | BindComplete | NoData |
      PortalSuspended | ParameterDescription(_) |
      CopyInResponse | CopyOutResponse | CopyData(_) | CopyDone => ()
    }
  }
}

///|
/// Dispatch a backend message: consume connection-level messages, convert
/// query-relevant messages to QueryMessage, drop the rest.
fn Connection::dispatch(
  self : Connection,
  msg : BackendMessage,
) -> DispatchResult {
  match msg {
    // Connection state updates
    NotificationResponse(pid, channel, payload) => {
      self.notification_queue.enqueue(Notification::new(channel, payload, pid))
      Consumed
    }
    ParameterStatus(name, value) => {
      self.server_params[name] = value
      Consumed
    }
    ReadyForQuery(status) => {
      self.transaction_status = status
      Ready
    }
    // Server notices (warnings, informational messages)
    NoticeResponse(fields) => {
      self.notice_queue.push(ServerErrorInfo::from_fields(fields))
      Consumed
    }
    // Protocol acknowledgments
    CloseComplete => Consumed
    // Query-relevant messages — pass through as narrower type
    RowDescription(f) => Message(QueryMessage::RowDescription(f))
    DataRow(v) => Message(QueryMessage::DataRow(v))
    CommandComplete(tag) => Message(QueryMessage::CommandComplete(tag))
    EmptyQueryResponse => Message(QueryMessage::EmptyQueryResponse)
    ErrorResponse(f) => Message(QueryMessage::ErrorResponse(f))
    ParseComplete => Message(QueryMessage::ParseComplete)
    BindComplete => Message(QueryMessage::BindComplete)
    NoData => Message(QueryMessage::NoData)
    PortalSuspended => Message(QueryMessage::PortalSuspended)
    ParameterDescription(oids) =>
      Message(QueryMessage::ParameterDescription(oids))
    // COPY messages — pass through for COPY callers
    CopyInResponse(_, _) => Message(QueryMessage::CopyInResponse)
    CopyOutResponse(_, _) => Message(QueryMessage::CopyOutResponse)
    CopyData(data) => Message(QueryMessage::CopyData(data))
    CopyDone => Message(QueryMessage::CopyDone)
    // Protocol messages consumed but payload unused (future features)
    NegotiateProtocolVersion(_, _) => Consumed
    // Authentication messages — only expected during startup, ignore elsewhere
    AuthenticationOk | AuthenticationCleartextPassword |
    AuthenticationMD5Password(_) | AuthenticationSASL(_) |
    AuthenticationSASLContinue(_) | AuthenticationSASLFinal(_) |
    BackendKeyData(_, _) => Consumed
  }
}

///|
/// Close the connection, sending Terminate message first
async fn Connection::close(self : Connection) -> Unit {
  self.send(Terminate) catch {
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
  tcp.write(encode(CancelRequest(process_id, secret_key)))
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
      tcp.write(encode(SSLRequest))
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
  self.send(StartupMessage(params))

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
fn secure_random_bytes(len : Int) -> Bytes raise AuthError {
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
        AuthenticationOk =>
          // Authentication successful, continue to receive startup messages
          ()
        AuthenticationCleartextPassword =>
          // Send password in cleartext
          self.send(PasswordMessage(self.config.password))
        AuthenticationMD5Password(salt) => {
          // Compute MD5 hash
          let hash = md5_password(self.config.password, self.config.user, salt)
          self.send(PasswordMessage(hash))
        }
        AuthenticationSASL(mechanisms) => {
          // SCRAM-SHA-256 initial handshake
          guard mechanisms.contains("SCRAM-SHA-256") else {
            raise AuthError("Server requires unsupported SASL mechanism")
          }
          let nonce = generate_nonce()
          let (client_first, client_first_bare) = scram_client_first(
            self.config.user,
            nonce,
          )
          scram_nonce = nonce
          scram_client_first_bare = client_first_bare
          self.send(
            SASLInitialResponse("SCRAM-SHA-256", @utf8.encode(client_first[:])),
          )
        }
        AuthenticationSASLContinue(data) => {
          // SCRAM server-first-message → compute client-final
          let server_first = @utf8.decode_lossy(data[:])
          let (client_final, expected_sig) = scram_client_final(
            self.config.password,
            scram_client_first_bare,
            server_first,
            scram_nonce,
          ) catch {
            ScramError(msg) => raise AuthError(msg)
          }
          scram_expected_sig = expected_sig
          self.send(SASLResponse(@utf8.encode(client_final[:])))
        }
        AuthenticationSASLFinal(data) => {
          // SCRAM server-final-message → verify server signature
          let server_final = @utf8.decode_lossy(data[:])
          scram_verify_server(server_final, scram_expected_sig) catch {
            ScramError(msg) => raise AuthError(msg)
          }
        }
        BackendKeyData(pid, key) => {
          self.process_id = pid
          self.secret_key = key
        }
        ErrorResponse(fields) =>
          raise AuthError(
            ServerErrorInfo::from_fields(fields).message,
          )
        msg =>
          match self.dispatch(msg) {
            Ready => return
            Consumed | Message(_) => ()
          }
      }
    }
  }
}
