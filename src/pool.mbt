///| Connection Pool
///
/// Manages a pool of reusable PostgreSQL connections.

///|
/// Connection pool for PostgreSQL
struct Pool {
  config : Config
  idle : @async.Queue[Client]
  semaphore : @async.Semaphore
  acquire_timeout_ms : Int
  mut closed : Bool
}

///|
/// Create a new connection pool
pub fn Pool::new(
  config : Config,
  max_size~ : Int = 10,
  acquire_timeout_ms~ : Int = 30000,
) -> Pool {
  {
    config,
    idle: @async.Queue::new(kind=Unbounded),
    semaphore: @async.Semaphore::new(max_size),
    acquire_timeout_ms,
    closed: false,
  }
}

///|
/// Acquire a connection from the pool.
/// Returns an idle connection if available, otherwise creates a new one.
/// Blocks if the pool is at maximum capacity, with a timeout.
pub async fn Pool::acquire(self : Pool) -> Client {
  guard not(self.closed) else {
    raise PoolError("Pool is closed")
  }
  @async.with_timeout(
    self.acquire_timeout_ms,
    async fn() {
      self.semaphore.acquire()
      // Try to get an idle connection
      let idle_client : Client? = self.idle.try_get() catch { _ => None }
      match idle_client {
        Some(client) => {
          // Verify the connection is still usable
          if client.closed {
            // Discard and create a new one
            Client::connect(self.config)
          } else {
            client
          }
        }
        _ =>
          // No idle connections, create a new one
          Client::connect(self.config)
      }
    },
    error=PoolError("Acquire timeout"),
  )
}

///|
/// Release a connection back to the pool
pub async fn Pool::release(self : Pool, client : Client) -> Unit {
  if self.closed || client.closed {
    if not(client.closed) {
      client.close()
    }
    self.semaphore.release()
    return
  }
  self.idle.put(client)
  self.semaphore.release()
}

///|
/// Close the pool, closing all idle connections
pub async fn Pool::close(self : Pool) -> Unit {
  self.closed = true
  // Drain idle connections before closing the queue
  while true {
    let client : Client? = self.idle.try_get() catch { _ => None }
    match client {
      Some(c) => c.close()
      None => break
    }
  }
  self.idle.close()
}

///|
/// Execute a function with a connection, automatically releasing it afterwards
pub async fn[T] Pool::with_connection(
  self : Pool,
  f : async (Client) -> T,
) -> T {
  let client = self.acquire()
  let result = f(client) catch {
    err => {
      self.release(client)
      raise err
    }
  }
  self.release(client)
  result
}
