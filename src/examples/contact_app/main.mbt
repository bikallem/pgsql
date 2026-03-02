///| Contacts App CLI
///
/// A CLI application demonstrating the PostgreSQL driver.
///
/// Usage:
///   moon run examples/contact_app --target native -- <command> [args...]
///
/// Commands:
///   setup                      Create contacts table
///   list                       List all contacts
///   add <name> <email> [phone] Add a contact
///   update <id> <field> <value> Update a contact field
///   delete <id>                Delete a contact
///   search <term>              Search contacts by name or email

async fn main {
  let args = @env.args()
  // args[0] is the program name; commands start at args[1]
  if args.length() < 2 {
    print_usage()
    return
  }

  let config = @pgsql.Config::new(
    "postgres",
    "postgres",
    "postgres",
    host="localhost",
    port=5432,
  )

  let client = try {
    @pgsql.Client::connect(config)
  } catch {
    e => {
      println("Failed to connect: \{e}")
      return
    }
  }

  let command = args[1]
  try {
    if command == "setup" {
      cmd_setup(client)
    } else if command == "list" {
      cmd_list(client)
    } else if command == "add" {
      cmd_add(client, args)
    } else if command == "update" {
      cmd_update(client, args)
    } else if command == "delete" {
      cmd_delete(client, args)
    } else if command == "search" {
      cmd_search(client, args)
    } else {
      println("Unknown command: \{command}")
      print_usage()
    }
  } catch {
    e => println("Error: \{e}")
  }

  client.close()
}

fn print_usage() -> Unit {
  println("Usage: contact_app <command> [args...]")
  println("")
  println("Commands:")
  println("  setup                        Create contacts table")
  println("  list                         List all contacts")
  println("  add <name> <email> [phone]   Add a contact")
  println("  update <id> <field> <value>  Update a contact field")
  println("  delete <id>                  Delete a contact")
  println("  search <term>                Search by name or email")
}

async fn cmd_setup(client : @pgsql.Client) -> Unit {
  let sql = "CREATE TABLE IF NOT EXISTS contacts (id SERIAL PRIMARY KEY, name TEXT NOT NULL, email TEXT UNIQUE NOT NULL, phone TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)"
  let _ = client.execute(sql)
  println("Contacts table created.")
}

async fn cmd_list(client : @pgsql.Client) -> Unit {
  let result = client.query(
    "SELECT id, name, email, phone FROM contacts ORDER BY id",
  )
  if result.row_count() == 0 {
    println("No contacts found.")
    return
  }
  for row in result.iter() {
    let id = row.get_int(0).unwrap_or(0)
    let name = row.get_string(1).unwrap_or("")
    let email = row.get_string(2).unwrap_or("")
    let phone = if row.is_null(3) {
      "N/A"
    } else {
      row.get_string(3).unwrap_or("N/A")
    }
    println("\{id}: \{name} <\{email}> \{phone}")
  }
  println("Total: \{result.row_count()} contact(s)")
}

async fn cmd_add(client : @pgsql.Client, args : Array[String]) -> Unit {
  if args.length() < 4 {
    println("Usage: add <name> <email> [phone]")
    return
  }
  let name = args[2]
  let email = args[3]
  if args.length() >= 5 {
    let phone = args[4]
    let _ = client.execute_params(
      "INSERT INTO contacts (name, email, phone) VALUES ($1, $2, $3)",
      [@pgsql.String(name), @pgsql.String(email), @pgsql.String(phone)],
    )
  } else {
    let _ = client.execute_params(
      "INSERT INTO contacts (name, email) VALUES ($1, $2)",
      [@pgsql.String(name), @pgsql.String(email)],
    )
  }
  println("Contact added: \{name} <\{email}>")
}

async fn cmd_update(client : @pgsql.Client, args : Array[String]) -> Unit {
  if args.length() < 5 {
    println("Usage: update <id> <field> <value>")
    return
  }
  let id = args[2]
  let field = args[3]
  let value = args[4]
  // Only allow updating known columns
  if field != "name" && field != "email" && field != "phone" {
    println("Invalid field: \{field}. Allowed: name, email, phone")
    return
  }
  // Use separate queries for each field to avoid SQL injection
  let sql = if field == "name" {
    "UPDATE contacts SET name = $1 WHERE id = $2"
  } else if field == "email" {
    "UPDATE contacts SET email = $1 WHERE id = $2"
  } else {
    "UPDATE contacts SET phone = $1 WHERE id = $2"
  }
  let affected = client.execute_params(
    sql,
    [@pgsql.String(value), @pgsql.String(id)],
  )
  println("Updated \{affected} row(s)")
}

async fn cmd_delete(client : @pgsql.Client, args : Array[String]) -> Unit {
  if args.length() < 3 {
    println("Usage: delete <id>")
    return
  }
  let id = args[2]
  let affected = client.execute_params(
    "DELETE FROM contacts WHERE id = $1",
    [@pgsql.String(id)],
  )
  println("Deleted \{affected} row(s)")
}

async fn cmd_search(client : @pgsql.Client, args : Array[String]) -> Unit {
  if args.length() < 3 {
    println("Usage: search <term>")
    return
  }
  let term = "%" + args[2] + "%"
  let result = client.query_params(
    "SELECT id, name, email, phone FROM contacts WHERE name ILIKE $1 OR email ILIKE $1 ORDER BY id",
    [@pgsql.String(term)],
  )
  if result.row_count() == 0 {
    println("No matches found.")
    return
  }
  for row in result.iter() {
    let id = row.get_int(0).unwrap_or(0)
    let name = row.get_string(1).unwrap_or("")
    let email = row.get_string(2).unwrap_or("")
    let phone = if row.is_null(3) {
      "N/A"
    } else {
      row.get_string(3).unwrap_or("N/A")
    }
    println("\{id}: \{name} <\{email}> \{phone}")
  }
  println("Found: \{result.row_count()} contact(s)")
}
