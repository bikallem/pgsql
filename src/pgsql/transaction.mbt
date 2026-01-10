///| Transaction Management
///
/// Provides transaction support for PostgreSQL operations.

/// Transaction handle for executing queries within a transaction
pub struct Transaction {
  /// Reference to the client
  client : Client
  /// Whether the transaction is still active
  mut active : Bool
}

/// Execute a function within a transaction
/// Automatically commits on success and rolls back on failure
pub async fn[T] Client::transaction(
  self : Client,
  f : async (Transaction) -> T
) -> T {
  // Begin transaction
  self.begin()

  let tx = { client: self, active: true }

  // Execute the function
  let result = try {
    f(tx)
  } catch {
    e => {
      // Rollback on error
      try {
        self.rollback()
      } catch {
        _ => () // Ignore rollback errors
      }
      tx.active = false
      raise e
    }
  }

  // Commit on success
  if tx.active {
    self.commit()
    tx.active = false
  }

  result
}

/// Execute a query within the transaction
pub async fn Transaction::query(
  self : Transaction,
  sql : String
) -> QueryResult {
  if not(self.active) {
    raise TxError("Transaction is no longer active")
  }
  self.client.query(sql)
}

/// Execute a parameterized query within the transaction
pub async fn Transaction::query_params(
  self : Transaction,
  sql : String,
  params : Array[@protocol.Value]
) -> QueryResult {
  if not(self.active) {
    raise TxError("Transaction is no longer active")
  }
  self.client.query_params(sql, params)
}

/// Execute a statement within the transaction
pub async fn Transaction::execute(
  self : Transaction,
  sql : String
) -> Int {
  if not(self.active) {
    raise TxError("Transaction is no longer active")
  }
  self.client.execute(sql)
}

/// Execute a parameterized statement within the transaction
pub async fn Transaction::execute_params(
  self : Transaction,
  sql : String,
  params : Array[@protocol.Value]
) -> Int {
  if not(self.active) {
    raise TxError("Transaction is no longer active")
  }
  self.client.execute_params(sql, params)
}

/// Explicitly commit the transaction
pub async fn Transaction::commit(self : Transaction) -> Unit {
  if not(self.active) {
    raise TxError("Transaction is no longer active")
  }
  self.client.commit()
  self.active = false
}

/// Explicitly rollback the transaction
pub async fn Transaction::rollback(self : Transaction) -> Unit {
  if not(self.active) {
    raise TxError("Transaction is no longer active")
  }
  self.client.rollback()
  self.active = false
}

/// Check if the transaction is still active
pub fn Transaction::is_active(self : Transaction) -> Bool {
  self.active
}

/// Create a savepoint within the transaction
pub async fn Transaction::savepoint(
  self : Transaction,
  name : String
) -> Unit {
  if not(self.active) {
    raise TxError("Transaction is no longer active")
  }
  let _ = self.client.execute("SAVEPOINT " + name)
}

/// Rollback to a savepoint
pub async fn Transaction::rollback_to(
  self : Transaction,
  name : String
) -> Unit {
  if not(self.active) {
    raise TxError("Transaction is no longer active")
  }
  let _ = self.client.execute("ROLLBACK TO SAVEPOINT " + name)
}

/// Release a savepoint
pub async fn Transaction::release(
  self : Transaction,
  name : String
) -> Unit {
  if not(self.active) {
    raise TxError("Transaction is no longer active")
  }
  let _ = self.client.execute("RELEASE SAVEPOINT " + name)
}
