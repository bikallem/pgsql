///| Unit tests for error types

test "ServerErrorInfo::from_fields basic" {
  let fields : Map[String, String] = {}
  fields["S"] = "ERROR"
  fields["C"] = "42P01"
  fields["M"] = "relation does not exist"
  let info = @pgsql.ServerErrorInfo::from_fields(fields)
  inspect(info.severity, content="ERROR")
  inspect(info.code, content="42P01")
  inspect(info.message, content="relation does not exist")
  inspect(info.detail, content="None")
  inspect(info.hint, content="None")
}

test "ServerErrorInfo::from_fields with detail and hint" {
  let fields : Map[String, String] = {}
  fields["S"] = "FATAL"
  fields["C"] = "28P01"
  fields["M"] = "password authentication failed"
  fields["D"] = "User does not exist"
  fields["H"] = "Check your pg_hba.conf"
  let info = @pgsql.ServerErrorInfo::from_fields(fields)
  inspect(info.severity, content="FATAL")
  inspect(info.detail, content=(
    #|Some("User does not exist")
  ))
  inspect(info.hint, content=(
    #|Some("Check your pg_hba.conf")
  ))
}

test "ServerErrorInfo::from_fields with table and constraint" {
  let fields : Map[String, String] = {}
  fields["S"] = "ERROR"
  fields["C"] = "23505"
  fields["M"] = "duplicate key"
  fields["t"] = "users"
  fields["n"] = "users_email_key"
  let info = @pgsql.ServerErrorInfo::from_fields(fields)
  inspect(info.table, content=(
    #|Some("users")
  ))
  inspect(info.constraint, content=(
    #|Some("users_email_key")
  ))
  inspect(info.column, content="None")
}

test "ServerErrorInfo::from_fields fallback severity" {
  let fields : Map[String, String] = {}
  fields["V"] = "PANIC"
  fields["C"] = "XX000"
  fields["M"] = "internal error"
  let info = @pgsql.ServerErrorInfo::from_fields(fields)
  inspect(info.severity, content="PANIC")
}

test "ServerErrorInfo::from_fields missing severity" {
  let fields : Map[String, String] = {}
  fields["M"] = "something"
  let info = @pgsql.ServerErrorInfo::from_fields(fields)
  inspect(info.severity, content="ERROR")
}

test "ServerErrorInfo::from_fields missing message" {
  let fields : Map[String, String] = {}
  fields["S"] = "ERROR"
  let info = @pgsql.ServerErrorInfo::from_fields(fields)
  inspect(info.message, content="Unknown error")
}
