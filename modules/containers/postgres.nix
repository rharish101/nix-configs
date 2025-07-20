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
  };
  config =
    let
      constants = import ../constants.nix;
    in
    lib.mkIf config.modules.postgres.enable {
      # User for the PostgreSQL container.
      users.users.postgres = {
        uid = constants.uids.postgres;
        group = "postgres";
        isSystemUser = true;
      };
      users.groups.postgres.gid = constants.uids.postgres;

      containers.postgres = {
        privateNetwork = true;

        privateUsers = config.users.users.postgres.uid;
        extraFlags = [ "--private-users-ownership=auto" ];

        autoStart = true;
        ephemeral = true;

        bindMounts = with config.modules.postgres; {
          dataDir = {
            hostPath = dataDir;
            mountPoint = "/var/lib/postgresql";
            isReadOnly = false;
          };
        };

        config =
          { ... }:
          {
            networking.firewall.allowedTCPPorts = [ constants.ports.postgres ];

            services.postgresql = {
              enable = true;
              enableTCPIP = true;
              settings.port = constants.ports.postgres;
              authentication = with constants.bridges; ''
                host sameuser authelia ${auth-pg.auth.ip4}/32 scram-sha-256
                host sameuser crowdsec ${csec-pg.csec.ip4}/32 scram-sha-256
                host sameuser lldap    ${ldap-pg.ldap.ip4}/32 scram-sha-256
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
                (lib.mkIf config.modules.lldap.enable {
                  name = "lldap";
                  ensureDBOwnership = true;
                })
              ];
              ensureDatabases = [
                (lib.mkIf config.modules.authelia.enable "authelia")
                (lib.mkIf config.modules.crowdsec-lapi.enable "crowdsec")
                (lib.mkIf config.modules.lldap.enable "lldap")
              ];
            };

            system.stateVersion = "25.05";
          };
      };
    };
}
