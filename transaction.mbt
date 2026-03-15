///| Transaction Management
///
/// Provides transaction support for PostgreSQL operations.

///|
/// Transaction handle for executing queries within a transaction
struct Transaction {
  /// Reference to the client
  client : Client
  /// Whether the transaction is still active
  mut active : Bool
}

///|
/// Execute a function within a transaction
/// Automatically commits on success and rolls back on failure
pub async fn[T] Client::transaction(
  self : Client,
  f : async (Transaction) -> T,
) -> T {
  self.check_not_in_user_callback()
  self.check_not_in_transaction_callback()
  self.tx_guard.acquire()
  if self.closed {
    self.tx_guard.release()
    raise ConnectionClosedError
  }

  self.with_transaction_operation(async fn() {
    ignore((self.query_unlocked("BEGIN") : QueryResult))
  }) catch {
    err => {
      self.tx_guard.release()
      raise err
    }
  }

  let tx = { client: self, active: true }

  let result = self.run_transaction_callback(async fn() { f(tx) }) catch {
    e => {
      if tx.active {
        self.with_transaction_operation(async fn() {
          ignore((self.query_unlocked("ROLLBACK") : QueryResult))
        }) catch {
          _ => ()
        }
        tx.active = false
      }
      self.tx_guard.release()
      raise e
    }
  }

  if tx.active {
    self.with_transaction_operation(async fn() {
      ignore((self.query_unlocked("COMMIT") : QueryResult))
    }) catch {
      err => {
        self.tx_guard.release()
        raise err
      }
    }
    tx.active = false
  }

  self.tx_guard.release()
  result
}

///|
/// Guard: raises TxError if the transaction is no longer active
fn Transaction::check_active(self : Transaction) -> Unit raise TxError {
  if not(self.active) {
    raise TxError("Transaction is no longer active")
  }
}

///|
/// Execute a query within the transaction
pub async fn Transaction::query(
  self : Transaction,
  sql : String,
) -> QueryResult {
  self.check_active()
  self.client.with_transaction_operation(async fn() {
    self.client.query_unlocked(sql)
  })
}

///|
/// Execute a parameterized query within the transaction
pub async fn Transaction::query_params(
  self : Transaction,
  sql : String,
  params : Array[Value],
) -> QueryResult {
  self.check_active()
  let messages = self.client.with_transaction_operation(async fn() {
    self.client.bind_execute_unlocked("", params, prefix=[
      Parse("", sql, []),
    ])
  })
  build_query_result(messages)
}

///|
/// Execute a statement within the transaction
pub async fn Transaction::execute(self : Transaction, sql : String) -> Int {
  self.check_active()
  let result = self.query(sql)
  parse_affected_rows(result.command_tag)
}

///|
/// Execute a parameterized statement within the transaction
pub async fn Transaction::execute_params(
  self : Transaction,
  sql : String,
  params : Array[Value],
) -> Int {
  self.check_active()
  let result = self.query_params(sql, params)
  parse_affected_rows(result.command_tag)
}

///|
/// Explicitly commit the transaction
pub async fn Transaction::commit(self : Transaction) -> Unit {
  self.check_active()
  ignore((self.client.with_transaction_operation(async fn() {
    self.client.query_unlocked("COMMIT")
  }) : QueryResult))
  self.active = false
}

///|
/// Explicitly rollback the transaction
pub async fn Transaction::rollback(self : Transaction) -> Unit {
  self.check_active()
  ignore((self.client.with_transaction_operation(async fn() {
    self.client.query_unlocked("ROLLBACK")
  }) : QueryResult))
  self.active = false
}

///|
/// Check if the transaction is still active
pub fn Transaction::is_active(self : Transaction) -> Bool {
  self.active
}

///|
/// Create a named prepared statement within this transaction
pub async fn Transaction::prepare(
  self : Transaction,
  sql : String,
) -> PreparedStatement {
  self.check_active()
  let stmt = self.client.with_transaction_operation(async fn() {
    self.client.prepare_unlocked(sql)
  })
  stmt.tx_scoped = true
  stmt
}

///|
/// Create a savepoint within the transaction
pub async fn Transaction::savepoint(self : Transaction, name : String) -> Unit {
  self.check_active()
  ignore((self.execute("SAVEPOINT " + quote_identifier(name)) : Int))
}

///|
/// Rollback to a savepoint
pub async fn Transaction::rollback_to(
  self : Transaction,
  name : String,
) -> Unit {
  self.check_active()
  ignore((self.execute("ROLLBACK TO SAVEPOINT " + quote_identifier(name)) : Int))
}

///|
/// Release a savepoint
pub async fn Transaction::release(self : Transaction, name : String) -> Unit {
  self.check_active()
  ignore((self.execute("RELEASE SAVEPOINT " + quote_identifier(name)) : Int))
}
