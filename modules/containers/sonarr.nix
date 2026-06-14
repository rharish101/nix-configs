# SPDX-FileCopyrightText: 2026 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.sonarr = {
    enable = lib.mkEnableOption "Enable Sonarr";
    dataDir = lib.mkOption {
      description = "The data directory path for Sonarr";
      type = lib.types.str;
    };
    downloadDir = lib.mkOption {
      description = "The directory path where the download client downloads media";
      type = lib.types.str;
    };
    mediaDirs = lib.mkOption {
      description = "The directories where media is to be saved and managed by Sonarr";
      type = with lib.types; attrsOf str;
    };
  };

  config =
    let
      constants = import ../constants.nix lib;
    in
    lib.mkIf config.modules.sonarr.enable {
      modules.containers.sonarr = {
        allowedPorts.Tcp = [ constants.ports.sonarr ];
        credentials.env.name = "sonarr";
        username = "sonarr";

        bindMounts =
          with config.modules.sonarr;
          {
            data = {
              hostPath = dataDir;
              mountPoint = "/var/lib/sonarr/.config/NzbDrone";
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
            services.sonarr = {
              enable = true;
              environmentFiles = [ "/run/credentials/@system/env" ];
              settings = {
                log.dbenabled = false;
                postgres = {
                  host = constants.bridge.postgres.ip4;
                  port = constants.ports.postgres;
                  user = "sonarr";
                  maindb = "sonarr";
                };
                server = {
                  urlbase = "/shows";
                  bindaddress = "*";
                  port = constants.ports.sonarr;
                };
              };
            };

            system.stateVersion = "26.05";
          };
      };
    };
}
