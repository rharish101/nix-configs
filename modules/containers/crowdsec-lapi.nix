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
      constants = import ../constants.nix;
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
          uid = constants.uids.crowdsec;
          group = "crowdsec";
          isSystemUser = true;
        };
        users.groups.crowdsec.gid = constants.uids.crowdsec;

        systemd.services."container@crowdsec-lapi" = {
          requires = [
            "container@caddy-wg-client.service"
            "container@postgres.service"
          ];
        };

        networking.bridges."${constants.bridges.caddy-csec.name}".interfaces = [ ];
        networking.bridges."${constants.bridges.csec-pg.name}".interfaces = [ ];

        containers.caddy-wg-client.extraVeths."${constants.bridges.caddy-csec.caddy.interface}" =
          with constants.bridges.caddy-csec; {
            hostBridge = name;
            localAddress = "${caddy.ip4}/24";
            localAddress6 = "${caddy.ip6}/112";
          };
        containers.postgres.extraVeths."${constants.bridges.csec-pg.pg.interface}" =
          with constants.bridges.csec-pg; {
            hostBridge = name;
            localAddress = "${pg.ip4}/24";
            localAddress6 = "${pg.ip6}/112";
          };

        containers.crowdsec-lapi = {
          privateNetwork = true;
          hostBridge = constants.bridges.caddy-csec.name;
          localAddress = "${constants.bridges.caddy-csec.csec.ip4}/24";
          localAddress6 = "${constants.bridges.caddy-csec.csec.ip6}/112";

          extraVeths."${constants.bridges.csec-pg.csec.interface}" = with constants.bridges.csec-pg; {
            hostBridge = name;
            localAddress = "${csec.ip4}/24";
            localAddress6 = "${csec.ip6}/112";
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
                address = constants.bridges.caddy-csec.caddy.ip4;
                interface = "eth0";
              };
              networking.defaultGateway6 = {
                address = constants.bridges.caddy-csec.caddy.ip6;
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
                    host = constants.bridges.csec-pg.pg.ip4;
                    port = constants.ports.postgres;
                  };
                  api.server = {
                    enable = true;
                    listen_uri = "0.0.0.0:${toString constants.ports.crowdsec}";
                    console_path = "/var/lib/crowdsec/credentials/console.yaml";
                    online_client.credentials_path = "/var/lib/crowdsec/credentials/capi.yaml";
                  };
                };
                settings.lapi.credentialsFile = "/var/lib/crowdsec/credentials/lapi.yaml";
              };

              system.stateVersion = "25.05";
            };
        };
      };
}
