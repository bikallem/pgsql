///|
/// Unit tests for Config
test "Config::new defaults" {
  let cfg = @pgsql.Config::new("user1", "pass1", "db1")
  inspect(cfg.host(), content="localhost")
  inspect(cfg.port(), content="5432")
  inspect(cfg.user(), content="user1")
  inspect(cfg.database(), content="db1")
  inspect(cfg.ssl_mode(), content="Require")
}

///|
test "Config::new custom" {
  let cfg = @pgsql.Config::new(
    "admin",
    "secret",
    "mydb",
    host="10.0.0.1",
    port=5433,
    ssl_mode=Disable,
  )
  inspect(cfg.host(), content="10.0.0.1")
  inspect(cfg.port(), content="5433")
  inspect(cfg.user(), content="admin")
  inspect(cfg.database(), content="mydb")
  inspect(cfg.ssl_mode(), content="Disable")
}
