# SPDX-FileCopyrightText: 2026 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.vaultwarden = {
    enable = lib.mkEnableOption "Enable Vaultwarden";
    dataDir = lib.mkOption {
      description = "The Vaultwarden data directory path";
      type = lib.types.str;
    };
  };

  config =
    let
      constants = import ../constants.nix;
    in
    lib.mkIf (config.modules.vaultwarden.enable && config.modules.caddy-wg-client.enable) {
      modules.containers.vaultwarden = {
        shortName = "vw";
        username = "vaultwarden";
        allowInternet = true;
        credentials.env.name = "vaultwarden";

        bindMounts.dataDir = {
          hostPath = config.modules.vaultwarden.dataDir;
          mountPoint = "/var/lib/vaultwarden";
          isReadOnly = false;
        };

        config =
          { ... }:
          {
            networking.firewall.allowedTCPPorts = [ constants.ports.vaultwarden ];

            services.vaultwarden = {
              enable = true;
              domain = with constants.domain; "${subdomains.vw}.${domain}";
              dbBackend = "postgresql";
              environmentFile = "/run/credentials/@system/env";
              config = {
                ROCKET_ADDRESS = "0.0.0.0";
                ROCKET_PORT = constants.ports.vaultwarden;
                SMTP_HOST = constants.smtp.host;
                SMTP_PORT = constants.smtp.port;
                SMTP_USERNAME = constants.smtp.username;
                SMTP_FROM = with constants.domain; "${subdomains.vw}@${domain}";
                SSO_ENABLED = "true";
                SSO_ONLY = "true";
                SSO_AUTHORITY = with constants.domain; "https://${subdomains.auth}.${domain}";
                SSO_CLIENT_ID = "j-rWSHQpg-BvMn8f2y3NB367j2POzf9BBtwZCUVLgRKRmNHHqagmgVba11L2hyAPQwpcomzG";
                SSO_SCOPES = "email profile offline_access";
                SSO_AUTH_ONLY_NOT_SESSION = "true";
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
