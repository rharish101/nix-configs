# SPDX-FileCopyrightText: 2026 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.qbittorrent = {
    enable = lib.mkEnableOption "Enable qBittorrent";
    publicHost = lib.mkOption {
      description = "The public host used to access qBittorrent, including scheme";
      type = lib.types.str;
    };
    port = lib.mkOption {
      description = "The port on the host that to be used for qui";
      type = lib.types.int;
      default = 7476;
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

  config =
    let
      constants = import ../constants.nix;
    in
    lib.mkIf config.modules.qbittorrent.enable {
      modules.containers.qbittorrent = {
        username = "qbittorrent";
        forwardPorts = [ { hostPort = config.modules.qbittorrent.port; } ];

        credentials = {
          session.name = "qui/session";
          oidc.name = "qui/oidc";
        };

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
              secretFile = "/run/credentials/@system/session";
              settings =
                let
                  origin = with config.modules.qbittorrent; "${publicHost}:${toString port}";
                in
                {
                  host = "0.0.0.0";
                  port = config.modules.qbittorrent.port;
                  corsAllowedOrigins = [ origin ];
                  oidcEnabled = true;
                  oidcIssuer = with constants.domain; "https://${subdomains.authelia}.${domain}";
                  oidcClientId = "VPSq_HeaAKSxNyC87AojNrNP11G4z-4uC-P_Tf4iTYL.cHfQSQ6-LRwg4mTAWodyZeRzwAaJ";
                  oidcRedirectUrl = "${origin}/api/auth/oidc/callback";
                  oidcDisableBuiltInLogin = true;
                };
            };
            systemd.services.qui.serviceConfig = {
              LoadCredential = [ "oidc:oidc" ];
              Environment = [ "QUI__OIDC_CLIENT_SECRET_FILE=%d/oidc" ];
            };

            system.stateVersion = "26.05";
          };
      };
    };
}
