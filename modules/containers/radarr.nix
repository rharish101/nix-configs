# SPDX-FileCopyrightText: 2026 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.radarr = {
    enable = lib.mkEnableOption "Enable Radarr";
    dataDir = lib.mkOption {
      description = "The data directory path for Radarr";
      type = lib.types.str;
    };
  };

  config =
    let
      constants = import ../constants.nix lib;
    in
    lib.mkIf config.modules.radarr.enable {
      modules.containers.radarr = {
        username = "radarr";
        allowInternet = true;
        allowedPorts.Tcp = [ constants.ports.radarr ];
        credentials.env.name = "radarr";
        preferredBridge = "caddy";

        bindMounts.data = {
          hostPath = config.modules.radarr.dataDir;
          mountPoint = "/var/lib/radarr/.config/Radarr";
          isReadOnly = false;
        };

        config =
          { ... }:
          {
            services.radarr = {
              enable = true;
              environmentFiles = [ "/run/credentials/@system/env" ];
              settings = {
                log.dbenabled = false;
                postgres = {
                  host = constants.bridges.caddy.postgres.ip4;
                  port = constants.ports.postgres;
                  user = "radarr";
                  maindb = "radarr";
                };
                server = {
                  urlbase = "/movies";
                  bindaddress = "*";
                  port = constants.ports.radarr;
                };
              };
            };

            system.stateVersion = "26.05";
          };
      };
    };
}
