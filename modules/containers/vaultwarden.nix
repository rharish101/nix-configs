# SPDX-FileCopyrightText: 2026 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.vaultwarden = {
    enable = lib.mkEnableOption "Vaultwarden";
    dataDir = lib.mkOption {
      description = "The Vaultwarden data directory path";
      type = lib.types.str;
    };
  };

  config =
    let
      constants = import ../constants.nix lib;
    in
    lib.mkIf config.modules.vaultwarden.enable {
      sops.secrets = {
        "vaultwarden/postgres" = { };
        "vaultwarden/smtp" = { };
        "vaultwarden/oidc" = { };
        "vaultwarden/push/id" = { };
        "vaultwarden/push/key" = { };
      };

      sops.templates."vaultwarden/env".content =
        let
          pgPassword = config.sops.placeholder."vaultwarden/postgres";
          pgHost = "${constants.bridge.postgres.ip4}:${toString constants.ports.postgres}";
        in
        ''
          DATABASE_URL='postgres://vaultwarden:${pgPassword}@${pgHost}/vaultwarden'
          SMTP_PASSWORD='${config.sops.placeholder."vaultwarden/smtp"}'
          SSO_CLIENT_SECRET=${config.sops.placeholder."vaultwarden/oidc"}
          PUSH_INSTALLATION_ID=${config.sops.placeholder."vaultwarden/push/id"}
          PUSH_INSTALLATION_KEY=${config.sops.placeholder."vaultwarden/push/key"}
        '';

      modules.containers.vaultwarden = {
        allowedPorts.Tcp = [ constants.ports.vaultwarden ];
        username = "vaultwarden";

        credentials.env = {
          name = "vaultwarden/env";
          sopsType = "template";
        };

        dirMounts.dataDir = {
          hostPath = config.modules.vaultwarden.dataDir;
          mountPoint = "/var/lib/vaultwarden";
          isReadOnly = false;
        };

        config =
          { ... }:
          {
            services.vaultwarden = {
              enable = true;
              domain = with constants.domain; "${subdomains.vaultwarden}.${domain}";
              dbBackend = "postgresql";
              environmentFile = "/run/credentials/@system/env";
              config = {
                ROCKET_ADDRESS = "0.0.0.0";
                ROCKET_PORT = constants.ports.vaultwarden;
                SMTP_HOST = constants.smtp.host;
                SMTP_PORT = constants.smtp.port;
                SMTP_USERNAME = constants.smtp.username;
                SMTP_FROM = with constants.domain; "${subdomains.vaultwarden}@${domain}";
                SSO_ENABLED = "true";
                SSO_ONLY = "true";
                SSO_AUTHORITY = with constants.domain; "https://${subdomains.authelia}.${domain}";
                SSO_CLIENT_ID = "j-rWSHQpg-BvMn8f2y3NB367j2POzf9BBtwZCUVLgRKRmNHHqagmgVba11L2hyAPQwpcomzG";
                SSO_SCOPES = "email profile offline_access";
                PUSH_ENABLED = "true";
                PUSH_RELAY_URI = "https://api.bitwarden.eu";
                PUSH_IDENTITY_URI = "https://identity.bitwarden.eu";
              };
            };

            system.stateVersion = "26.05";
          };
      };
    };
}
