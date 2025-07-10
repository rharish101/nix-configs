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
      priv_uid_gid = 65536 * 13; # Randomly-chosen UID/GID a/c to how systemd-nspawn chooses one for the user namespacing.
    in
    lib.mkIf config.modules.postgres.enable {
      # User for the PostgreSQL container.
      users.users.postgres = {
        uid = priv_uid_gid;
        group = "postgres";
        isSystemUser = true;
      };
      users.groups.postgres.gid = priv_uid_gid;

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
            networking.firewall.allowedTCPPorts = [ 5432 ];

            services.postgresql = {
              enable = true;
              enableTCPIP = true;
              authentication = ''
                host sameuser authelia 10.4.2.1/32 scram-sha-256
                host sameuser crowdsec 10.6.1.1/32 scram-sha-256
                host sameuser lldap    10.5.0.1/32 scram-sha-256
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
