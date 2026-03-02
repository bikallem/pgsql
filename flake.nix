{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.postgresql
          ];

          shellHook = ''
            export PGDATA="$(pwd)/.postgres"
            export PGHOST="127.0.0.1"
            export PGPORT="5432"
            if [ ! -d "$PGDATA" ]; then
              initdb --no-locale --encoding=UTF8 --auth=trust
              cat > "$PGDATA/postgresql.conf" <<PGCONF
            listen_addresses = '127.0.0.1'
            port = 5432
            unix_socket_directories = '$(pwd)/.postgres'
            PGCONF
              cat > "$PGDATA/pg_hba.conf" <<HBA
            local   all   all                 trust
            host    all   all   127.0.0.1/32  trust
            host    all   all   ::1/128       trust
            HBA
              pg_ctl start -l "$PGDATA/log" -o "-k $(pwd)/.postgres"
              createuser -h 127.0.0.1 -s postgres 2>/dev/null || true
              createdb -h 127.0.0.1 -U postgres postgres 2>/dev/null || true
              pg_ctl stop
            fi
          '';
        };
      }
    );
}
