# SPDX-FileCopyrightText: 2026 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.qbittorrent = {
    enable = lib.mkEnableOption "Enable qBittorrent";
    port = lib.mkOption {
      description = "The port on the host that to be used for qBittorrent's WebUI";
      type = lib.types.int;
      default = 8080;
    };
    dataDir = lib.mkOption {
      description = "The data directory path for qBittorrent and qui";
      type = lib.types.str;
    };
    allowedDirs = lib.mkOption {
      description = "The directories exposed to qBittorrent";
      type = with lib.types; attrsOf str;
    };
  };

  config = lib.mkIf config.modules.qbittorrent.enable {
    modules.containers.qbittorrent = {
      username = "qbittorrent";
      credentials.qui.name = "qui";
      forwardPorts = [ { hostPort = config.modules.qbittorrent.port; } ];

      bindMounts =
        builtins.mapAttrs (name: dir: {
          hostPath = dir;
          mountPoint = "/data/${name}";
          isReadOnly = false;
        }) config.modules.qbittorrent.allowedDirs
        // {
          qbProfile = {
            hostPath = "${config.modules.qbittorrent.dataDir}/qBittorrent";
            mountPoint = "/var/lib/qBittorrent/qBittorrent";
            isReadOnly = false;
          };
          qui = {
            hostPath = "${config.modules.qbittorrent.dataDir}/qui";
            mountPoint = "/var/lib/qui";
            isReadOnly = false;
          };
        };

      config =
        { ... }:
        {
          networking.firewall.interfaces.eth0.allowedTCPPorts = [ config.modules.qbittorrent.port ];

          services.qbittorrent = {
            enable = true;
            extraArgs = [ "--confirm-legal-notice" ];
            serverConfig.Preferences.WebUI.LocalHostAuth = false;
          };

          services.qui = {
            enable = true;
            secretFile = "/run/credentials/@system/qui";
            settings = {
              host = "0.0.0.0";
              port = config.modules.qbittorrent.port;
            };
          };

          system.stateVersion = "26.05";
        };
    };
  };
}
