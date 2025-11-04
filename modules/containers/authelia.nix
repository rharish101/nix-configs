# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.modules.authelia.enable = lib.mkEnableOption "Enable Authelia";

  config =
    let
      constants = import ../constants.nix;
    in
    lib.mkIf
      (
        config.modules.authelia.enable
        && config.modules.caddy-wg-client.enable
        && config.modules.postgres.enable
        && config.modules.lldap.enable
      )
      {
        modules.containers.authelia = {
          shortName = "auth";
          allowInternet = true;

          credentials = {
            csec-creds.name = "authelia/crowdsec";
            jwt.name = "authelia/jwt";
            ldap-pass.name = "authelia/ldap";
            oidc-hmac.name = "authelia/oidc-hmac";
            oidc-jwks.name = "authelia/oidc-jwks";
            pg-pass.name = "authelia/postgres";
            sess.name = "authelia/session";
            smtp.name = "authelia/smtp";
            storage-enc.name = "authelia/storage";
          };

          config =
            let
              globalConfig = config;
            in
            { config, ... }:
            {
              networking.firewall.allowedTCPPorts = [ constants.ports.authelia ];

              services.authelia.instances.main = with globalConfig.modules.authelia; {
                enable = true;
                secrets.manual = true;
                settings =
                  with constants.bridges;
                  with constants.ports;
                  with constants.domain;
                  {
                    default_2fa_method = "totp";
                    theme = "auto";
                    server.address = "tcp://:${toString authelia}/";
                    authentication_backend.ldap = {
                      address = "ldap://${auth-ldap.ldap.ip4}:${toString lldap}";
                      implementation = "lldap";
                      base_dn = ldapBaseDn;
                      user = "uid=authelia,ou=people,${ldapBaseDn}";
                    };
                    storage.postgres = {
                      address = "tcp://${auth-pg.pg.ip4}:${toString postgres}";
                      database = "authelia";
                      username = "authelia";
                    };
                    session = {
                      redis.host = config.services.redis.servers.authelia.unixSocket;
                      cookies = [
                        {
                          domain = domain;
                          authelia_url = "https://${subdomains.auth}.${domain}";
                        }
                      ];
                    };
                    notifier.smtp = with constants.smtp; {
                      address = "submission://${host}:${toString port}";
                      username = username;
                      sender = "Authelia <${subdomains.auth}@${domain}>";
                    };
                    access_control.rules = [
                      {
                        domain = "*.${domain}";
                        policy = "two_factor";
                      }
                    ];
                    identity_providers.oidc = {
                      authorization_policies = {
                        opencloud = {
                          default_policy = "deny";
                          rules = [
                            { subject = "group:opencloud-admins"; }
                            { subject = "group:opencloud-users"; }
                          ];
                        };
                        tandoor = {
                          default_policy = "deny";
                          rules = [ { subject = "group:tandoor-users"; } ];
                        };
                      };
                      cors = {
                        endpoints = [ "token" ];
                        allowed_origins = [ "https://${subdomains.oc}.${domain}" ];
                      };
                      clients = [
                        {
                          client_id = "JuhCQHaHI65vm~.Oyw7F~X9nFiJpC1UsyxMzthVhDHwzjfcJhofhxV43Ezcs31Er";
                          client_name = "Immich";
                          client_secret = "$pbkdf2-sha512$310000$nKsIAFb7St17WH4uKLPH3A$O2/SqbuoeuDehSRkboSpfOS4DNXUn5ZDSWo.4DU3kKgUu3Qr0VkvZYgWsAWvYv2ywl/eJxyBOwwl3h68wm3/Kg";
                          redirect_uris = [
                            "https://${subdomains.imm}.${domain}/auth/login"
                            "https://${subdomains.imm}.${domain}/user-settings"
                            "app.immich:///oauth-callback"
                          ];
                          scopes = [
                            "openid"
                            "email"
                            "profile"
                          ];
                          token_endpoint_auth_method = "client_secret_post";
                          pre_configured_consent_duration = "1 month";
                        }
                        {
                          client_id = "7Fmtx-TlskeuagWedosmtKublan0JgxbMRe5V.SZyWR-GeNcOc1ngXoXpZ8U5SeI";
                          client_name = "Jellyfin";
                          client_secret = "$pbkdf2-sha512$310000$K4ozS7erBqjatwrxo5Do4Q$fDvzpM4xiAluUfBU6iSZ2wrk/xiT2brt1ko2UgLdSKo88OYbi2QcXALLi7UqoQ2qGo3.E1ChUVG330jLJdWk.Q";
                          redirect_uris = [
                            "https://${subdomains.jf}.${domain}/sso/OID/redirect/authelia"
                            "org.jellyfin.mobile://login-callback"
                          ];
                          scopes = [
                            "openid"
                            "profile"
                            "groups"
                          ];
                          token_endpoint_auth_method = "client_secret_post";
                          pre_configured_consent_duration = "1 month";
                        }
                        {
                          client_id = "ze1RwDxg_zLBH40.D9eP3RPbXl.fa~c2Q99q8vbwIQVZqFcn37GtzP3Wbk-HhsBO";
                          client_name = "Tandoor Recipes";
                          client_secret = "$pbkdf2-sha512$310000$qbwXRo.OH3g8/C5/QSYX5A$9sUVtyen0XwJi4Ky88g6NWK/C6HcHPig6sIhGzr7llkeQrNh0bpklafz3jOJx7A9d632NSPVIaNDWBWAaONeMQ";
                          redirect_uris = [ "https://${subdomains.tr}.${domain}/accounts/oidc/authelia/login/callback/" ];
                          scopes = [
                            "openid"
                            "profile"
                            "email"
                          ];
                          authorization_policy = "tandoor";
                          pre_configured_consent_duration = "1 month";
                        }
                        {
                          client_id = "9j4m5zcr5c51gJB6Qs50bChpQFWj3Htzc4wj3F2SMGVtIw-LhF3k8XpdXsWLP7YN";
                          client_name = "OpenCloud (Web)";
                          client_secret = "";
                          public = true;
                          redirect_uris = [
                            "https://${subdomains.oc}.${domain}/"
                            "https://${subdomains.oc}.${domain}/oidc-callback.html"
                            "https://${subdomains.oc}.${domain}/oidc-silent-redirect.html"
                          ];
                          scopes = [
                            "openid"
                            "profile"
                            "email"
                            "groups"
                          ];
                          authorization_policy = "opencloud";
                          pre_configured_consent_duration = "1 month";
                        }
                      ];
                    };
                  };
                settingsFiles = [
                  # Use separate YAML file to preserve newlines in the private key.
                  (pkgs.writeText "oidc-jwks.yaml" ''
                    identity_providers:
                      oidc:
                        jwks:
                          - key: {{ expandenv "$CREDENTIALS_DIRECTORY/oidc-jwks" | secret | mindent 10 "|" | msquote }}
                  '')
                ];
                environmentVariables = {
                  AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE = "%d/ldap-pass";
                  AUTHELIA_IDENTITY_PROVIDERS_OIDC_HMAC_SECRET_FILE = "%d/oidc-hmac";
                  AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET_FILE = "%d/jwt";
                  AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE = "%d/smtp";
                  AUTHELIA_SESSION_SECRET_FILE = "%d/sess";
                  AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE = "%d/storage-enc";
                  AUTHELIA_STORAGE_POSTGRES_PASSWORD_FILE = "%d/pg-pass";
                  X_AUTHELIA_CONFIG_FILTERS = "template";
                };
              };
              systemd.services.authelia-main.serviceConfig = {
                SupplementaryGroups = config.services.redis.servers.authelia.group;
                LoadCredential = [
                  "jwt:jwt"
                  "ldap-pass:ldap-pass"
                  "oidc-hmac:oidc-hmac"
                  "oidc-jwks:oidc-jwks"
                  "pg-pass:pg-pass"
                  "sess:sess"
                  "smtp:smtp"
                  "storage-enc:storage-enc"
                ];
              };

              services.crowdsec = lib.mkIf globalConfig.modules.crowdsec-lapi.enable {
                enable = true;
                autoUpdateService = true;
                name = "${globalConfig.networking.hostName}-authelia";

                localConfig.acquisitions = [
                  {
                    source = "journalctl";
                    journalctl_filter = [ "_SYSTEMD_UNIT=authelia-main.service" ];
                    labels.type = "syslog";
                    use_time_machine = true;
                  }
                ];
                hub.collections = [
                  "crowdsecurity/linux"
                  "LePresidente/authelia"
                ];
                settings.general.api.client.credentials_path = lib.mkForce "\${CREDENTIALS_DIRECTORY}/csec-creds";
              };
              systemd.services.crowdsec.serviceConfig.LoadCredential = [ "csec-creds:csec-creds" ];

              services.redis.servers.authelia.enable = true;

              system.stateVersion = "25.05";
            };
        };
      };
}
