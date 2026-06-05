# SPDX-FileCopyrightText: 2026 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.qui = {
    enable = lib.mkEnableOption "Enable qui";
    dataDir = lib.mkOption {
      description = "The data directory path for qui";
      type = lib.types.str;
    };
  };

  config =
    let
      constants = import ../constants.nix lib;
    in
    lib.mkIf config.modules.qui.enable {
      modules.containers.qui = {
        username = "qui";
        allowInternet = true;
        preferredBridge = "qb";
        allowedPorts.Tcp = [ constants.ports.qui ];

        credentials = {
          oidc.name = "qui/oidc";
          postgres.name = "qui/postgres";
          session.name = "qui/session";
        };

        bindMounts.qui = {
          hostPath = config.modules.qui.dataDir;
          mountPoint = "/var/lib/qui";
          isReadOnly = false;
        };

        config =
          { ... }:
          {
            services.qui = {
              enable = true;
              secretFile = "/run/credentials/@system/session";
              settings =
                let
                  origin = with constants.domain; "https://${subdomains.qui}.${domain}";
                in
                {
                  host = "0.0.0.0";
                  port = constants.ports.qui;
                  corsAllowedOrigins = [ origin ];
                  databaseEngine = "postgres";
                  databaseHost = constants.bridges.caddy.postgres.ip4;
                  databasePort = constants.ports.postgres;
                  databaseUser = "qui";
                  databaseName = "qui";
                  checkForUpdates = false;
                  oidcEnabled = true;
                  oidcIssuer = with constants.domain; "https://${subdomains.authelia}.${domain}";
                  oidcClientId = "VPSq_HeaAKSxNyC87AojNrNP11G4z-4uC-P_Tf4iTYL.cHfQSQ6-LRwg4mTAWodyZeRzwAaJ";
                  oidcRedirectUrl = "${origin}/api/auth/oidc/callback";
                  oidcDisableBuiltInLogin = true;
                };
            };
            systemd.services.qui.serviceConfig = {
              LoadCredential = [
                "oidc:oidc"
                "postgres:postgres"
              ];
              Environment = [
                "QUI__DATABASE_PASSWORD_FILE=%d/postgres"
                "QUI__OIDC_CLIENT_SECRET_FILE=%d/oidc"
              ];
            };

            system.stateVersion = "26.05";
          };
      };
    };
}
