# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.postgres = {
    enable = lib.mkEnableOption "Enable PostgreSQL";
    dataDir = lib.mkOption {
      description = "The PostgreSQL directory path";
      type = lib.types.str;
      default = "/var/lib/postgresql";
    };
    backupDir = lib.mkOption {
      description = "The path where to save PostgreSQL backups";
      type = lib.types.str;
    };
  };
  config =
    let
      constants = import ../constants.nix;
    in
    lib.mkIf config.modules.postgres.enable {
      modules.containers.postgres = {
        username = "postgres";
        allowedPorts.Tcp = [ constants.ports.postgres ];

        bindMounts = with config.modules.postgres; {
          dataDir = {
            hostPath = dataDir;
            mountPoint = "/var/lib/postgresql";
            isReadOnly = false;
          };
          backupDir = {
            hostPath = backupDir;
            mountPoint = "/var/backup/postgresql";
            isReadOnly = false;
          };
        };

        config =
          { ... }:
          {
            services.postgresql = {
              enable = true;
              enableTCPIP = true;
              settings.port = constants.ports.postgres;
              # Have to manually allow these hosts to connect.
              authentication = with constants.bridge; ''
                host sameuser authelia    ${authelia.ip4}/32      scram-sha-256
                host sameuser crowdsec    ${crowdsec-lapi.ip4}/32 scram-sha-256
                host sameuser immich      ${immich.ip4}/32        scram-sha-256
                host sameuser lldap       ${lldap.ip4}/32         scram-sha-256
                host sameuser tandoor     ${tandoor.ip4}/32       scram-sha-256
                host sameuser vaultwarden ${vaultwarden.ip4}/32   scram-sha-256
              '';
              ensureUsers = [
                (lib.mkIf config.modules.authelia.enable {
                  name = "authelia";
                  ensureDBOwnership = true;
                })
                (lib.mkIf config.modules.crowdsec-lapi.enable {
                  name = "crowdsec";
                  ensureDBOwnership = true;
                })
                (lib.mkIf config.modules.immich.enable {
                  name = "immich";
                  ensureDBOwnership = true;
                })
                (lib.mkIf config.modules.lldap.enable {
                  name = "lldap";
                  ensureDBOwnership = true;
                })
                (lib.mkIf config.modules.tandoor.enable {
                  name = "tandoor";
                  ensureDBOwnership = true;
                })
                (lib.mkIf config.modules.vaultwarden.enable {
                  name = "vaultwarden";
                  ensureDBOwnership = true;
                })
              ];
              ensureDatabases = [
                (lib.mkIf config.modules.authelia.enable "authelia")
                (lib.mkIf config.modules.crowdsec-lapi.enable "crowdsec")
                (lib.mkIf config.modules.immich.enable "immich")
                (lib.mkIf config.modules.lldap.enable "lldap")
                (lib.mkIf config.modules.tandoor.enable "tandoor")
                (lib.mkIf config.modules.vaultwarden.enable "vaultwarden")
              ];
              # NOTE: Passwords have to be manually enrolled.

              # Install VectorChord, which is necessary for Immich.
              extensions =
                ps: with ps; [
                  vectorchord
                  pgvector
                ];
              settings.shared_preload_libraries = [ "vchord" ];
            };

            services.postgresqlBackup = {
              enable = true;
              compression = "zstd";
              compressionLevel = 3;
            };

            system.stateVersion = "25.05";
          };
      };
    };
}
