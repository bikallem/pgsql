///|
/// Unit tests for Config
test "Config::new defaults" {
  let cfg = @pgsql.Config::new("user1", "pass1", "db1")
  inspect(cfg.get_host(), content="localhost")
  inspect(cfg.get_port(), content="5432")
  inspect(cfg.get_user(), content="user1")
  inspect(cfg.get_password(), content="pass1")
  inspect(cfg.get_database(), content="db1")
}

///|
test "Config::new custom" {
  let cfg = @pgsql.Config::new(
    "admin",
    "secret",
    "mydb",
    host="10.0.0.1",
    port=5433,
  )
  inspect(cfg.get_host(), content="10.0.0.1")
  inspect(cfg.get_port(), content="5433")
  inspect(cfg.get_user(), content="admin")
  inspect(cfg.get_password(), content="secret")
  inspect(cfg.get_database(), content="mydb")
}
