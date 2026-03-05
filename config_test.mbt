///|
/// Unit tests for Config
test "Config::new defaults" {
  let cfg = @pgsql.Config::new("user1", "pass1", "db1")
  inspect(cfg.host(), content="localhost")
  inspect(cfg.port(), content="5432")
  inspect(cfg.user(), content="user1")
  inspect(cfg.password(), content="pass1")
  inspect(cfg.database(), content="db1")
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
  inspect(cfg.host(), content="10.0.0.1")
  inspect(cfg.port(), content="5433")
  inspect(cfg.user(), content="admin")
  inspect(cfg.password(), content="secret")
  inspect(cfg.database(), content="mydb")
}
