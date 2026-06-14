# SPDX-FileCopyrightText: 2026 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.qbittorrent = {
    enable = lib.mkEnableOption "Enable qBittorrent";
    dataDir = lib.mkOption {
      description = "The data directory path for qBittorrent";
      type = lib.types.str;
    };
  };

  config =
    let
      constants = import ../constants.nix lib;
    in
    lib.mkIf config.modules.qbittorrent.enable {
      modules.containers.qbittorrent = {
        username = "qbittorrent";
        allowedPorts.Tcp = [ constants.ports.qbittorrent ];

        bindMounts.profile = {
          hostPath = config.modules.qbittorrent.dataDir;
          mountPoint = "/var/lib/qBittorrent/qBittorrent";
          isReadOnly = false;
        };

        config =
          { ... }:
          {
            networking.nat = {
              enable = true;
              internalInterfaces = [ "vb-*" ];
              externalInterface = "eth0";
            };

            services.qbittorrent = {
              enable = true;
              extraArgs = [ "--confirm-legal-notice" ];
              webuiPort = constants.ports.qbittorrent;
              serverConfig.Preferences.WebUI = {
                Username = "qui";
                Password_PBKDF2 = "@ByteArray(AEgFonsUIBrIzzKFE+yFnQ==:SEE/1cXWx20ucaQy3ngOMLj044mPvWG8KZAzuradfhW4YNE8/SHeC55FUOMRpG6zJlPW0M71CUgBR3sn9RRf9A==)";
              };
            };

            system.stateVersion = "26.05";
          };
      };
    };
}
