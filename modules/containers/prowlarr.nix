# SPDX-FileCopyrightText: 2026 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.prowlarr = {
    enable = lib.mkEnableOption "Enable Prowlarr";
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
        allowedPorts.Tcp = [ constants.ports.prowlarr ];
        credentials.env.name = "prowlarr";
        username = "prowlarr";

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
                  host = constants.bridge.postgres.ip4;
                  port = constants.ports.postgres;
                  user = "prowlarr";
                  maindb = "prowlarr";
                };
                server = {
                  urlbase = "/indexers";
                  bindaddress = "*";
                  port = constants.ports.prowlarr;
                };
              };
            };

            system.stateVersion = "26.05";
          };
      };
    };
}
