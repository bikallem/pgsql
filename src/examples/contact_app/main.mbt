///|
async fn main {
  let args = @env.args()
  if args.length() < 2 {
    print_usage()
    return
  }
  let config = @pgsql.Config::new(
    "postgres",
    "postgres",
    "postgres",
    host="127.0.0.1",
  )
  let client = @pgsql.Client::connect(config)
  let command = args[1]
  match command {
    "setup" => cmd_setup(client)
    "list" => cmd_list(client)
    "add" => cmd_add(client, args)
    "update" => cmd_update(client, args)
    "delete" => cmd_delete(client, args)
    "search" => cmd_search(client, args)
    _ => {
      println("Unknown command: " + command)
      print_usage()
    }
  }
  client.close()
}

///|
fn print_usage() -> Unit {
  println("Usage: contact_app <command> [args...]")
  println("")
  println("Commands:")
  println("  setup                    Create contacts table")
  println("  list                     List all contacts")
  println("  add <name> <email> [phone]  Add a contact")
  println("  update <id> <field> <value> Update a contact field")
  println("  delete <id>              Delete a contact")
  println("  search <term>            Search contacts by name or email")
}

///|
async fn cmd_setup(client : @pgsql.Client) -> Unit {
  let sql =
    #| CREATE TABLE IF NOT EXISTS contacts (
    #|   id SERIAL PRIMARY KEY,
    #|   name VARCHAR(100) NOT NULL,
    #|   email VARCHAR(100) NOT NULL,
    #|   phone VARCHAR(20)
    #| )
  let _ = client.execute(sql)
  println("Contacts table created.")
}

///|
async fn cmd_list(client : @pgsql.Client) -> Unit {
  let result = client.query(
    "SELECT id, name, email, phone FROM contacts ORDER BY id",
  )
  if result.row_count() == 0 {
    println("No contacts found.")
    return
  }
  for i = 0; i < result.row_count(); i = i + 1 {
    match result.get_row(i) {
      Some(row) => {
        let id = row.get_int(0).unwrap_or(0)
        let name = row.get_string(1).unwrap_or("")
        let email = row.get_string(2).unwrap_or("")
        let phone = row.get_string(3).unwrap_or("N/A")
        println(id.to_string() + ". " + name + " <" + email + "> " + phone)
      }
      None => ()
    }
  }
}

///|
async fn cmd_add(client : @pgsql.Client, args : Array[String]) -> Unit {
  if args.length() < 4 {
    println("Usage: contact_app add <name> <email> [phone]")
    return
  }
  let name = args[2]
  let email = args[3]
  let phone : @pgsql.Value = if args.length() > 4 {
    @pgsql.String(args[4])
  } else {
    @pgsql.Null
  }
  let _ = client.execute_params(
    "INSERT INTO contacts (name, email, phone) VALUES ($1, $2, $3)",
    [@pgsql.String(name), @pgsql.String(email), phone],
  )
  println("Contact added: " + name)
}

///|
async fn cmd_update(client : @pgsql.Client, args : Array[String]) -> Unit {
  if args.length() < 5 {
    println("Usage: contact_app update <id> <field> <value>")
    return
  }
  let id = args[2]
  let field = args[3]
  let value = args[4]
  match field {
    "name" | "email" | "phone" => {
      let sql = "UPDATE contacts SET " + field + " = $1 WHERE id = $2"
      let affected = client.execute_params(sql, [
        @pgsql.String(value),
        @pgsql.String(id),
      ])
      println("Updated " + affected.to_string() + " contact(s).")
    }
    _ => println("Invalid field: " + field + ". Use name, email, or phone.")
  }
}

///|
async fn cmd_delete(client : @pgsql.Client, args : Array[String]) -> Unit {
  if args.length() < 3 {
    println("Usage: contact_app delete <id>")
    return
  }
  let id = args[2]
  let affected = client.execute_params("DELETE FROM contacts WHERE id = $1", [
    @pgsql.String(id),
  ])
  println("Deleted " + affected.to_string() + " contact(s).")
}

///|
async fn cmd_search(client : @pgsql.Client, args : Array[String]) -> Unit {
  if args.length() < 3 {
    println("Usage: contact_app search <term>")
    return
  }
  let term = "%" + args[2] + "%"
  let result = client.query_params(
    "SELECT id, name, email, phone FROM contacts WHERE name ILIKE $1 OR email ILIKE $1 ORDER BY id",
    [@pgsql.String(term)],
  )
  if result.row_count() == 0 {
    println("No contacts found matching: " + args[2])
    return
  }
  for i = 0; i < result.row_count(); i = i + 1 {
    match result.get_row(i) {
      Some(row) => {
        let id = row.get_int(0).unwrap_or(0)
        let name = row.get_string(1).unwrap_or("")
        let email = row.get_string(2).unwrap_or("")
        let phone = row.get_string(3).unwrap_or("N/A")
        println(id.to_string() + ". " + name + " <" + email + "> " + phone)
      }
      None => ()
    }
  }
}
