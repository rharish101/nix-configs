# SPDX-FileCopyrightText: 2026 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.lidarr = {
    enable = lib.mkEnableOption "Enable Lidarr";
    dataDir = lib.mkOption {
      description = "The data directory path for Lidarr";
      type = lib.types.str;
    };
    downloadDir = lib.mkOption {
      description = "The directory path where the download client downloads media";
      type = lib.types.str;
    };
    mediaDirs = lib.mkOption {
      description = "The directories where media is to be saved and managed by Lidarr";
      type = with lib.types; attrsOf str;
      default = { };
    };
  };

  config =
    let
      constants = import ../constants.nix lib;
    in
    lib.mkIf config.modules.lidarr.enable {
      modules.containers.lidarr = {
        allowedPorts.Tcp = [ constants.ports.lidarr ];
        credentials.env.name = "lidarr";
        username = "lidarr";

        bindMounts =
          with config.modules.lidarr;
          {
            data = {
              hostPath = dataDir;
              mountPoint = "/var/lib/lidarr/.config/Lidarr";
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
            services.lidarr = {
              enable = true;
              environmentFiles = [ "/run/credentials/@system/env" ];
              settings = {
                log.dbenabled = false;
                postgres = {
                  host = constants.bridge.postgres.ip4;
                  port = constants.ports.postgres;
                  user = "lidarr";
                  maindb = "lidarr";
                };
                server = {
                  urlbase = "/music";
                  bindaddress = "*";
                  port = constants.ports.lidarr;
                };
              };
            };

            system.stateVersion = "26.05";
          };
      };
    };
}
