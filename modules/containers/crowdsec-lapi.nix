# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.crowdsec-lapi = {
    enable = lib.mkEnableOption "Enable CrowdSec Local API server";
    dataDir = lib.mkOption {
      description = "Path to the directory to store CrowdSec info & credentials.";
      type = lib.types.str;
    };
    secrets.envFile = lib.mkOption {
      description = "Path to the environment file containing secrets.";
      type = lib.types.str;
    };
  };
  config =
    let
      priv_uid_gid = 65536 * 15; # Randomly-chosen UID/GID a/c to how systemd-nspawn chooses one for the user namespacing
      caddy_br_name = "br-caddy-csec";
      caddy_br_addr = "10.6.0.1";
      caddy_br_addr6 = "fc00::51";
      postgres_br_name = "br-csec-pg";
      postgres_br_addr_postgres = "10.6.1.2";
    in
    lib.mkIf
      (
        config.modules.crowdsec-lapi.enable
        && config.modules.caddy-wg-client.enable
        && config.modules.postgres.enable
      )
      {
        # User for the CrowdSec container.
        users.users.crowdsec = {
          uid = priv_uid_gid;
          group = "crowdsec";
          isSystemUser = true;
        };
        users.groups.crowdsec.gid = priv_uid_gid;

        systemd.services."container@crowdsec-lapi" = {
          requires = [
            "container@caddy-wg-client.service"
            "container@postgres.service"
          ];
        };

        networking.bridges."${caddy_br_name}".interfaces = [ ];
        networking.bridges."${postgres_br_name}".interfaces = [ ];

        containers.caddy-wg-client.extraVeths.caddy-csec = {
          hostBridge = caddy_br_name;
          localAddress = "${caddy_br_addr}/24";
          localAddress6 = "${caddy_br_addr6}/112";
        };
        containers.postgres.extraVeths.pg-csec = {
          hostBridge = postgres_br_name;
          localAddress = "${postgres_br_addr_postgres}/24";
          localAddress6 = "fc00::54/112";
        };

        containers.crowdsec-lapi = {
          privateNetwork = true;
          hostBridge = caddy_br_name;
          localAddress = "10.6.0.2/24";
          localAddress6 = "fc00::52/112";

          extraVeths.csec-pg = {
            hostBridge = postgres_br_name;
            localAddress = "10.6.1.1/24";
            localAddress6 = "fc00::53/112";
          };

          privateUsers = config.users.users.crowdsec.uid;
          extraFlags = [ "--private-users-ownership=auto" ];

          autoStart = true;
          ephemeral = true;

          bindMounts = with config.modules.crowdsec-lapi; {
            dataDir = {
              hostPath = dataDir;
              mountPoint = "/var/lib/crowdsec";
              isReadOnly = false;
            };
            envFile = {
              hostPath = secrets.envFile;
              mountPoint = secrets.envFile;
            };
          };

          config =
            { ... }:
            {
              imports = [ ../vendored/crowdsec.nix ];

              # To allow this container to access the internet through the bridge.
              networking.defaultGateway = {
                address = caddy_br_addr;
                interface = "eth0";
              };
              networking.defaultGateway6 = {
                address = caddy_br_addr6;
                interface = "eth0";
              };
              networking.nameservers = [ "1.1.1.1" ];

              # Add secrets using an environment file.
              systemd.services.crowdsec.serviceConfig.EnvironmentFile =
                config.modules.crowdsec-lapi.secrets.envFile;

              services.crowdsec = {
                enable = true;
                autoUpdateService = true;
                openFirewall = true;
                name = "${config.networking.hostName}-lapi";

                user = "root";
                group = "root";

                # XXX: CrowdSec refuses to start unless some acquisitions are specified.
                localConfig.acquisitions = [
                  {
                    source = "journalctl";
                    journalctl_filter = [ "_SYSTEMD_UNIT=ssh.service" ];
                    labels.type = "syslog";
                  }
                ];

                settings.general = {
                  db_config = {
                    type = "postgres";
                    user = "crowdsec";
                    password = "\${DB_PASSWORD}";
                    db_name = "crowdsec";
                    host = postgres_br_addr_postgres;
                    port = 5432;
                  };
                  api.server = {
                    enable = true;
                    listen_uri = "0.0.0.0:8080";
                    online_client.sharing = false;
                  };
                };
                settings.lapi.credentialsFile = "/var/lib/crowdsec/credentials/lapi.yaml";
              };

              system.stateVersion = "25.05";
            };
        };
      };
}
