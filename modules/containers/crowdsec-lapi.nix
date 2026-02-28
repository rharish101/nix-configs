# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.modules.crowdsec-lapi = {
    enable = lib.mkEnableOption "Enable CrowdSec Local API server";
    dataDir = lib.mkOption {
      description = "Path to the directory to store CrowdSec info & credentials.";
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
        modules.containers.crowdsec-lapi = {
          username = "crowdsec";
          allowInternet = true;
          credentials.env.name = "crowdsec/lapi-env";
          allowedPorts.Tcp = [ constants.ports.crowdsec ];

          bindMounts.dataDir = {
            hostPath = config.modules.crowdsec-lapi.dataDir;
            mountPoint = "/var/lib/crowdsec";
            isReadOnly = false;
          };

          config =
            { ... }:
            {
              # Add secrets using an environment file.
              systemd.services.crowdsec.serviceConfig.EnvironmentFile = "/run/credentials/@system/env";
              systemd.services.crowdsec.path = [ pkgs.sytemd ];

              services.crowdsec =
                let
                  credentialsDir = "/var/lib/crowdsec/credentials";
                in
                {
                  enable = true;
                  autoUpdateService = true;
                  name = "${config.networking.hostName}-lapi";

                  # XXX: CrowdSec refuses to start unless some acquisitions are specified.
                  localConfig.acquisitions = [
                    # Minimal acquisition for journalctl
                    {
                      source = "journalctl";
                      journalctl_filter = [ "_SYSTEMD_UNIT=ssh.service" ];
                      labels.type = "syslog";
                    }
                  ];

                  settings = {
                    general = {
                      db_config = {
                        type = "postgres";
                        user = "crowdsec";
                        password = "\${DB_PASSWORD}";
                        db_name = "crowdsec";
                        host = constants.bridge.postgres.ip4;
                        port = constants.ports.postgres;
                      };
                      api.server = {
                        enable = true;
                        listen_uri = "0.0.0.0:${toString constants.ports.crowdsec}";
                      };
                    };
                    capi.credentialsFile = "${credentialsDir}/capi.yaml";
                    lapi.credentialsFile = "${credentialsDir}/lapi.yaml";
                    console.tokenFile = "${credentialsDir}/console.yaml";
                  };
                };

              system.stateVersion = "25.05";
            };
        };
      };
}
