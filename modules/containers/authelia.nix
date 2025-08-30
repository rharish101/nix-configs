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
  options.modules.authelia = {
    enable = lib.mkEnableOption "Enable Authelia";
    dataDir = lib.mkOption {
      description = "Path to the directory to store Authelia info & secrets.";
      type = lib.types.str;
    };
  };

  config =
    let
      constants = import ../constants.nix;
      configDir = "/var/lib/authelia-main/configs"; # MUST be a (sub)directory of "/var/lib/authelia-{instanceName}"
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
          username = "authelia";
          allowInternet = true;

          credentials = {
            csec-creds.name = "authelia/crowdsec";
            jwt.name = "authelia/jwt";
            ldap-pass.name = "authelia/ldap";
            oidc-hmac.name = "authelia/oidc-hmac";
            oidc-jwks.name = "authelia/oidc-jwks";
            pg-pass.name = "authelia/postgres";
            sess.name = "authelia/session";
            storage-enc.name = "authelia/storage";
          };

          bindMounts.data = {
            hostPath = config.modules.authelia.dataDir;
            mountPoint = configDir;
            isReadOnly = false;
          };

          config =
            let
              globalConfig = config;
            in
            { config, ... }:
            {
              imports = [ ../vendored/crowdsec.nix ];

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
                    notifier.filesystem.filename = "${configDir}/notification.txt";
                    access_control.rules = [
                      {
                        domain = "*.${domain}";
                        policy = "two_factor";
                      }
                    ];
                    identity_providers.oidc.clients = [
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
                    ];
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
