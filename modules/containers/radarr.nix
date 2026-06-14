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
    downloadDir = lib.mkOption {
      description = "The directory path where the download client downloads media";
      type = lib.types.str;
    };
    mediaDirs = lib.mkOption {
      description = "The directories where media is to be saved and managed by Radarr";
      type = with lib.types; attrsOf str;
    };
  };

  config =
    let
      constants = import ../constants.nix lib;
    in
    lib.mkIf config.modules.radarr.enable {
      modules.containers.radarr = {
        allowedPorts.Tcp = [ constants.ports.radarr ];
        credentials.env.name = "radarr";
        username = "radarr";

        bindMounts =
          with config.modules.radarr;
          {
            data = {
              hostPath = dataDir;
              mountPoint = "/var/lib/radarr/.config/Radarr";
              isReadOnly = false;
            };
            downloads = {
              hostPath = downloadDir;
              mountPoint = "/var/lib/qBittorrent/qBittorrent/downloads";
            };
          }
          // builtins.mapAttrs (name: dir: {
            hostPath = dir;
            mountPoint = "/data/${name}";
            isReadOnly = false;
          }) mediaDirs;

        config =
          { ... }:
          {
            services.radarr = {
              enable = true;
              environmentFiles = [ "/run/credentials/@system/env" ];
              settings = {
                log.dbenabled = false;
                postgres = {
                  host = constants.bridge.postgres.ip4;
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
