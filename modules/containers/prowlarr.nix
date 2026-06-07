# SPDX-FileCopyrightText: 2026 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.prowlarr = {
    enable = lib.mkEnableOption "Enable Prowlarr";
    port = lib.mkOption {
      description = "The port on the host that to be used for Prowlarr";
      type = lib.types.int;
      default = 9696;
    };
    dataDir = lib.mkOption {
      description = "The data directory path for Prowlarr";
      type = lib.types.str;
    };
  };

  config =
    let
      constants = import ../constants.nix lib;
    in
    lib.mkIf config.modules.prowlarr.enable {
      modules.containers.prowlarr = {
        username = "prowlarr";
        allowedPorts.Tcp = [ config.modules.prowlarr.port ];
        credentials.env.name = "prowlarr";
        forwardPorts = [ { hostPort = config.modules.prowlarr.port; } ];

        bindMounts.data = {
          hostPath = config.modules.prowlarr.dataDir;
          mountPoint = "/var/lib/private/prowlarr";
          isReadOnly = false;
        };

        config =
          { ... }:
          {
            services.prowlarr = {
              enable = true;
              environmentFiles = [ "/run/credentials/@system/env" ];
              settings = {
                log.dbenabled = false;
                postgres = {
                  host = constants.bridges.qb.postgres.ip4;
                  port = constants.ports.postgres;
                  user = "prowlarr";
                  maindb = "prowlarr";
                };
                server = {
                  bindaddress = "*";
                  port = config.modules.prowlarr.port;
                };
              };
            };

            system.stateVersion = "26.05";
          };
      };
    };
}
