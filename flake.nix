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

          PGDATA = ".postgres";

          shellHook = ''
            if [ ! -d "$PGDATA" ]; then
              initdb --no-locale --encoding=UTF8
              echo "unix_socket_directories = '$(pwd)/.postgres'" >> "$PGDATA/postgresql.conf"
              echo "listen_addresses = '127.0.0.1'" >> "$PGDATA/postgresql.conf"
              echo "port = 5432" >> "$PGDATA/postgresql.conf"
            fi
          '';
        };
      }
    );
}
