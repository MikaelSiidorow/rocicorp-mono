{
  description = "Zero replication fault harness development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {nixpkgs, ...}: let
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    devShells = forAllSystems (system: let
      pkgs = import nixpkgs {inherit system;};
      commonPackages = with pkgs; [
        bashInteractive
        coreutils
        curl
        findutils
        gawk
        git
        gnugrep
        gnused
        jq
        nodejs_22
        openssl
        pnpm
        postgresql_16
        ripgrep
        sqlite
        which
      ];
      linuxPackages = with pkgs;
        lib.optionals stdenv.isLinux [
          docker-client
          docker-compose
          lsof
          procps
        ];
      darwinPackages = with pkgs;
        lib.optionals stdenv.isDarwin [
          docker-client
          docker-compose
          lsof
        ];
    in {
      default = pkgs.mkShell {
        packages = commonPackages ++ linuxPackages ++ darwinPackages;

        shellHook = ''
          export ZERO_FAULT_HARNESS_PGHOST="''${ZERO_FAULT_HARNESS_PGHOST:-127.0.0.1}"
          export ZERO_FAULT_HARNESS_PGPORT="''${ZERO_FAULT_HARNESS_PGPORT:-55432}"
          export ZERO_FAULT_HARNESS_PGUSER="''${ZERO_FAULT_HARNESS_PGUSER:-zero}"
          export ZERO_FAULT_HARNESS_PGPASSWORD="''${ZERO_FAULT_HARNESS_PGPASSWORD:-zero}"
          export ZERO_FAULT_HARNESS_PGDATABASE="''${ZERO_FAULT_HARNESS_PGDATABASE:-zero}"

          export PGHOST="''${PGHOST:-$ZERO_FAULT_HARNESS_PGHOST}"
          export PGPORT="''${PGPORT:-$ZERO_FAULT_HARNESS_PGPORT}"
          export PGUSER="''${PGUSER:-$ZERO_FAULT_HARNESS_PGUSER}"
          export PGPASSWORD="''${PGPASSWORD:-$ZERO_FAULT_HARNESS_PGPASSWORD}"
          export PGDATABASE="''${PGDATABASE:-$ZERO_FAULT_HARNESS_PGDATABASE}"

          export ZERO_UPSTREAM_DB="''${ZERO_UPSTREAM_DB:-postgres://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT/$PGDATABASE}"
          export ZERO_CHANGE_DB="''${ZERO_CHANGE_DB:-$ZERO_UPSTREAM_DB}"
          export ZERO_APP_ID="''${ZERO_APP_ID:-zero_fault_harness}"
          export ZERO_REPLICA_FILE="''${ZERO_REPLICA_FILE:-$PWD/runs/dev/replica.db}"
          export ZERO_LOG_FORMAT="''${ZERO_LOG_FORMAT:-json}"
          export ZERO_LOG_LEVEL="''${ZERO_LOG_LEVEL:-debug}"
          export ZERO_ENABLE_TELEMETRY="''${ZERO_ENABLE_TELEMETRY:-false}"
          export ZERO_NUM_SYNC_WORKERS="''${ZERO_NUM_SYNC_WORKERS:-0}"
          export ZERO_CHANGE_STREAMER_STARTUP_DELAY_MS="''${ZERO_CHANGE_STREAMER_STARTUP_DELAY_MS:-0}"
          export ZERO_REPLICATION_LAG_REPORT_INTERVAL_MS="''${ZERO_REPLICATION_LAG_REPORT_INTERVAL_MS:-0}"

          mkdir -p runs/dev

          echo "zero harness shell: node $(node --version), pnpm $(pnpm --version)"
          echo "zero harness shell: ZERO_UPSTREAM_DB=$ZERO_UPSTREAM_DB"
          echo "zero harness shell: ZERO_REPLICA_FILE=$ZERO_REPLICA_FILE"
        '';
      };
    });
  };
}
