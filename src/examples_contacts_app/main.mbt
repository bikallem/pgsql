///| Contacts App Example
///
/// A simple CRUD application demonstrating the PostgreSQL driver.

/// Main entry point
async fn main {
  // Configure connection
  let config = @pgsql.Config::new(
    "postgres",
    "postgres",
    "postgres",
    host="localhost",
    port=5432
  )

  // Connect to PostgreSQL
  println("Connecting to PostgreSQL...")
  let client = try {
    @pgsql.Client::connect(config)
  } catch {
    e => {
      println("Failed to connect: " + e.to_string())
      return
    }
  }

  println("Connected!")

  // Create contacts table
  println("\nCreating contacts table...")
  let create_sql = "CREATE TABLE IF NOT EXISTS contacts (id SERIAL PRIMARY KEY, name TEXT NOT NULL, email TEXT UNIQUE NOT NULL, phone TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)"
  try {
    let _ = client.execute(create_sql)
    println("Table created!")
  } catch {
    e => println("Table creation error: " + e.to_string())
  }

  // Clear existing data
  try {
    let _ = client.execute("DELETE FROM contacts")
  } catch {
    _ => ()
  }

  // Insert some contacts
  println("\nInserting contacts...")
  try {
    let _ = client.query_params(
      "INSERT INTO contacts (name, email, phone) VALUES ($1, $2, $3)",
      [@protocol.String("Alice Smith"), @protocol.String("alice@example.com"), @protocol.String("555-1234")]
    )
    let _ = client.query_params(
      "INSERT INTO contacts (name, email, phone) VALUES ($1, $2, $3)",
      [@protocol.String("Bob Jones"), @protocol.String("bob@example.com"), @protocol.String("555-5678")]
    )
    let _ = client.query_params(
      "INSERT INTO contacts (name, email) VALUES ($1, $2)",
      [@protocol.String("Charlie Brown"), @protocol.String("charlie@example.com")]
    )
    println("Contacts inserted!")
  } catch {
    e => println("Insert error: " + e.to_string())
  }

  // Query all contacts
  println("\nAll contacts:")
  try {
    let result = client.query("SELECT id, name, email, phone FROM contacts ORDER BY id")
    for row in result.rows {
      let id = row.get_int(0).unwrap_or(0)
      let name = row.get_string(1).unwrap_or("")
      let email = row.get_string(2).unwrap_or("")
      let phone = if row.is_null(3) { "N/A" } else { row.get_string(3).unwrap_or("N/A") }
      println("  \{id}: \{name} <\{email}> - \{phone}")
    }
    println("Total: \{result.row_count()} contacts")
  } catch {
    e => println("Query error: " + e.to_string())
  }

  // Update a contact
  println("\nUpdating Bob's phone...")
  try {
    let affected = client.execute_params(
      "UPDATE contacts SET phone = $1 WHERE email = $2",
      [@protocol.String("555-9999"), @protocol.String("bob@example.com")]
    )
    println("Updated \{affected} row(s)")
  } catch {
    e => println("Update error: " + e.to_string())
  }

  // Transaction example
  println("\nTransaction example...")
  try {
    client.transaction(async fn(tx) {
      let _ = tx.execute_params(
        "INSERT INTO contacts (name, email) VALUES ($1, $2)",
        [@protocol.String("Dave Wilson"), @protocol.String("dave@example.com")]
      )
      println("  Added Dave within transaction")
      ()
    })
    println("Transaction committed!")
  } catch {
    e => println("Transaction error: " + e.to_string())
  }

  // Final count
  println("\nFinal count:")
  try {
    let result = client.query("SELECT COUNT(*) FROM contacts")
    match result.rows.get(0) {
      Some(row) => {
        let count = row.get_int(0).unwrap_or(0)
        println("  Total contacts: \{count}")
      }
      None => println("  No result")
    }
  } catch {
    e => println("Count error: " + e.to_string())
  }

  // Clean up
  client.close()
  println("\nDone!")
}
