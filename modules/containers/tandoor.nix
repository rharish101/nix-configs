# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.tandoor = {
    enable = lib.mkEnableOption "Enable Tandoor Recipes";
    dataDir = lib.mkOption {
      description = "The Tandoor Recipes directory path";
      type = lib.types.str;
    };
  };
  config =
    let
      constants = import ../constants.nix;
      secretConfig.restartUnits = [ "container@tandoor.service" ];
    in
    lib.mkIf
      (
        config.modules.tandoor.enable
        && config.modules.caddy-wg-client.enable
        && config.modules.postgres.enable
      )
      {
        sops.secrets."tandoor/oidc" = secretConfig;
        sops.secrets."tandoor/postgres" = secretConfig;
        sops.secrets."tandoor/secret-key" = secretConfig;

        # Tandoor doesn't support loading secrets from a file natively (only through a helper
        # script, which NixOS doesn't use...).
        sops.templates."tandoor/env".content =
          let
            oidcConfig = builtins.toJSON {
              openid_connect.APPS = [
                {
                  provider_id = "authelia";
                  name = "Authelia";
                  client_id = "ze1RwDxg_zLBH40.D9eP3RPbXl.fa~c2Q99q8vbwIQVZqFcn37GtzP3Wbk-HhsBO";
                  secret = config.sops.placeholder."tandoor/oidc";
                  settings.server_url =
                    with constants.domain;
                    "https://${subdomains.auth}.${domain}/.well-known/openid-configuration";
                }
              ];
            };
          in
          ''
            POSTGRES_PASSWORD=${config.sops.placeholder."tandoor/postgres"}
            SECRET_KEY=${config.sops.placeholder."tandoor/secret-key"}
            SOCIALACCOUNT_PROVIDERS=${oidcConfig}
          '';

        modules.containers.tandoor = {
          shortName = "tr";
          username = "tandoor";
          allowInternet = true;

          credentials.env = {
            name = "tandoor/env";
            sopsType = "template";
          };

          bindMounts.media = {
            hostPath = config.modules.tandoor.dataDir;
            mountPoint = "/var/lib/tandoor-recipes";
            isReadOnly = false;
          };

          config =
            { ... }:
            {
              networking.firewall.allowedTCPPorts = [ constants.ports.tandoor ];

              services.tandoor-recipes = {
                enable = true;
                address = "0.0.0.0";
                port = constants.ports.tandoor;
                extraConfig = {
                  ALLOWED_HOSTS = with constants.domain; "${subdomains.tr}.${domain}";
                  DB_ENGINE = "django.db.backends.postgresql";
                  POSTGRES_HOST = constants.bridges.tr-pg.pg.ip4;
                  POSTGRES_PORT = constants.ports.postgres;
                  POSTGRES_USER = "tandoor";
                  POSTGRES_DB = "tandoor";
                  GUNICORN_MEDIA = 1;
                  SOCIAL_PROVIDERS = "allauth.socialaccount.providers.openid_connect";
                };
              };
              systemd.services.tandoor-recipes.serviceConfig.EnvironmentFile = "/run/credentials/@system/env";

              system.stateVersion = "25.11";
            };
        };
      };
}
