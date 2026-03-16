///| Connection Pool
///
/// Manages a pool of reusable PostgreSQL connections.

///|
/// Connection pool for PostgreSQL
struct Pool {
  config : Config
  idle : @async.Queue[Pgsql]
  semaphore : @async.Semaphore
  acquire_timeout_ms : Int
  mut closed : Bool
  /// Number of acquires currently waiting on semaphore.acquire().
  mut waiting_acquires : Int
  /// Synthetic permits released during close to wake blocked acquires.
  mut synthetic_permits : Int
}

///|
/// Create a new connection pool
pub fn Pool::new(
  config : Config,
  max_size? : Int = 10,
  acquire_timeout_ms? : Int = 30000,
) -> Pool {
  {
    config,
    idle: @async.Queue::new(kind=Unbounded),
    semaphore: @async.Semaphore::new(max_size),
    acquire_timeout_ms,
    closed: false,
    waiting_acquires: 0,
    synthetic_permits: 0,
  }
}

///|
/// Acquire a connection from the pool.
/// Returns an idle connection if available, otherwise creates a new one.
/// Blocks if the pool is at maximum capacity, with a timeout.
pub async fn Pool::acquire(self : Pool) -> Pgsql {
  guard not(self.closed) else { raise PoolError("Pool is closed") }
  @async.with_timeout(
    self.acquire_timeout_ms,
    async fn() {
      self.acquire_permit()
      if self.closed {
        self.release_permit()
        raise PoolError("Pool is closed")
      }
      let client = self.acquire_after_permit() catch {
        err => {
          // Connect failure after permit acquisition must not leak capacity.
          self.release_permit()
          raise err
        }
      }
      if self.closed {
        if not(client.closed) {
          client.close() catch {
            _ => ()
          }
        }
        self.release_permit()
        raise PoolError("Pool is closed")
      }
      client
    },
    error=PoolError("Acquire timeout"),
  )
}

///|
/// Acquire path after a semaphore permit has already been acquired.
/// Caller is responsible for releasing the permit on failure.
async fn Pool::acquire_after_permit(self : Pool) -> Pgsql {
  // Try to get an idle connection
  let idle_client : Pgsql? = self.idle.try_get() catch {
    // Queue closed (pool shutting down) — treat as no idle connection available
    _queue_closed => None
  }
  match idle_client {
    Some(client) =>
      // Verify the connection is still usable
      if client.closed {
        // Discard and create a new one
        Pgsql::connect(self.config)
      } else {
        client
      }
    _ =>
      // No idle connections, create a new one
      Pgsql::connect(self.config)
  }
}

///|
/// Release a connection back to the pool
pub async fn Pool::release(self : Pool, client : Pgsql) -> Unit {
  if self.closed || client.closed {
    if not(client.closed) {
      client.close()
    }
    self.release_permit()
    return
  }
  self.idle.put(client)
  self.release_permit()
}

///|
/// Close the pool, closing all idle connections
pub async fn Pool::close(self : Pool) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  // Wake currently blocked acquires without overflowing semaphore capacity.
  self.wake_acquire_waiters(count=self.waiting_acquires)
  // Also issue one wake-up kick to cover edge races where a waiter may be
  // between try_acquire() and semaphore.acquire().
  self.wake_acquire_waiters()
  // Drain idle connections before closing the queue
  while true {
    let client : Pgsql? = self.idle.try_get() catch {
      // Queue may already be closed — treat as empty
      _queue_closed => None
    }
    match client {
      Some(c) => c.close()
      None => break
    }
  }
  self.idle.close()
}

///|
/// Acquire one semaphore permit, tracking waiters for close wake-up logic.
async fn Pool::acquire_permit(self : Pool) -> Unit {
  if self.semaphore.try_acquire() {
    return
  }
  self.waiting_acquires += 1
  self.semaphore.acquire() catch {
    err => {
      self.waiting_acquires -= 1
      raise err
    }
  }
  self.waiting_acquires -= 1
}

///|
/// Release one permit while accounting for synthetic close wakeups.
fn Pool::release_permit(self : Pool) -> Unit {
  if self.closed && self.synthetic_permits > 0 {
    self.synthetic_permits -= 1
    return
  }
  self.semaphore.release()
}

///|
/// Wake up to `count` blocked acquires while preserving permit accounting.
fn Pool::wake_acquire_waiters(self : Pool, count? : Int = 1) -> Unit {
  for remaining = count; remaining > 0; remaining = remaining - 1 {
    if not(self.wake_one_acquire_waiter()) {
      break
    }
  }
}

///|
/// Attempt to wake one blocked acquire.
/// Returns true if a synthetic wake permit was issued.
fn Pool::wake_one_acquire_waiter(self : Pool) -> Bool {
  if self.semaphore.try_acquire() {
    self.semaphore.release()
    return false
  }
  self.semaphore.release()
  self.synthetic_permits += 1
  true
}

///|
/// Execute a function with a connection, automatically releasing it afterwards
pub async fn[T] Pool::with_connection(self : Pool, f : async (Pgsql) -> T) -> T {
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
