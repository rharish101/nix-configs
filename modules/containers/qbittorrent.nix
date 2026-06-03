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
    profileDir = lib.mkOption {
      description = "The qBittorrent profile directory path";
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
      forwardPorts = [ { hostPort = config.modules.qbittorrent.port; } ];

      bindMounts =
        builtins.mapAttrs (name: dir: {
          hostPath = dir;
          mountPoint = "/data/${name}";
          isReadOnly = false;
        }) config.modules.qbittorrent.allowedDirs
        // {
          profile = {
            hostPath = config.modules.qbittorrent.profileDir;
            mountPoint = "/var/lib/qBittorrent";
            isReadOnly = false;
          };
        };

      config =
        { ... }:
        {
          networking.firewall.interfaces.eth0.allowedTCPPorts = [ config.modules.qbittorrent.port ];

          services.qbittorrent = {
            enable = true;
            webuiPort = config.modules.qbittorrent.port;
            extraArgs = [ "--confirm-legal-notice" ];
          };

          system.stateVersion = "26.05";
        };
    };
  };
}
