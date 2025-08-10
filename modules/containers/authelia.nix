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
      csecEnabled = config.modules.crowdsec-lapi.enable;
      configDir = "/var/lib/authelia-main/configs"; # MUST be a (sub)directory of "/var/lib/authelia-{instanceName}"
      secretsConfig.restartUnits = [ "container@authelia.service" ];
    in
    lib.mkIf
      (
        config.modules.authelia.enable
        && config.modules.caddy-wg-client.enable
        && config.modules.postgres.enable
        && config.modules.lldap.enable
      )
      {
        # User for the Authelia container.
        users.users.authelia = {
          uid = constants.uids.authelia;
          group = "authelia";
          isSystemUser = true;
        };
        users.groups.authelia.gid = constants.uids.authelia;

        sops.secrets."authelia/crowdsec" = secretsConfig;
        sops.secrets."authelia/ldap" = secretsConfig;
        sops.secrets."authelia/jwt" = secretsConfig;
        sops.secrets."authelia/oidc-hmac" = secretsConfig;
        sops.secrets."authelia/oidc-jwks" = secretsConfig;
        sops.secrets."authelia/postgres" = secretsConfig;
        sops.secrets."authelia/redis" = {
          owner = "authelia";
          group = "authelia";
          restartUnits = [
            "container@authelia.service"
            "container@authelia-redis.service"
          ];
        };
        sops.secrets."authelia/session" = secretsConfig;
        sops.secrets."authelia/storage" = secretsConfig;

        systemd.services."container@authelia" = {
          serviceConfig = with constants.limits.authelia; {
            MemoryHigh = "${toString memory}G";
            CPUQuota = "${toString (cpu * 100)}%";
          };
          requires = [
            (lib.mkIf csecEnabled "container@crowdsec-lapi.service")
            "container@lldap.service"
            "container@postgres.service"
            "container@authelia-redis.service"
          ];
        };

        networking.bridges = with constants.bridges; {
          "${auth-caddy.name}".interfaces = [ ];
          "${auth-csec.name}" = lib.mkIf csecEnabled { interfaces = [ ]; };
          "${auth-ldap.name}".interfaces = [ ];
          "${auth-pg.name}".interfaces = [ ];
          "${auth-redis.name}".interfaces = [ ];
        };

        containers.caddy-wg-client.extraVeths.${constants.bridges.auth-caddy.caddy.interface} =
          with constants.bridges.auth-caddy; {
            hostBridge = name;
            localAddress = "${caddy.ip4}/24";
            localAddress6 = "${caddy.ip6}/112";
          };
        containers.crowdsec-lapi.extraVeths.${constants.bridges.auth-csec.csec.interface} =
          with constants.bridges.auth-csec;
          lib.mkIf csecEnabled {
            hostBridge = name;
            localAddress = "${csec.ip4}/24";
            localAddress6 = "${csec.ip6}/112";
          };
        containers.lldap = with constants.bridges.auth-ldap; {
          hostBridge = name;
          localAddress = "${ldap.ip4}/24";
          localAddress6 = "${ldap.ip6}/112";
        };
        containers.postgres.extraVeths.${constants.bridges.auth-pg.pg.interface} =
          with constants.bridges.auth-pg; {
            hostBridge = name;
            localAddress = "${pg.ip4}/24";
            localAddress6 = "${pg.ip6}/112";
          };

        containers.authelia = {
          privateNetwork = true;
          hostBridge = constants.bridges.auth-caddy.name;
          localAddress = "${constants.bridges.auth-caddy.auth.ip4}/24";
          localAddress6 = "${constants.bridges.auth-caddy.auth.ip6}/112";

          extraVeths = with constants.bridges; {
            "${auth-csec.auth.interface}" =
              with auth-csec;
              lib.mkIf csecEnabled {
                hostBridge = name;
                localAddress = "${auth.ip4}/24";
                localAddress6 = "${auth.ip6}/112";
              };
            "${auth-ldap.auth.interface}" = with auth-ldap; {
              hostBridge = name;
              localAddress = "${auth.ip4}/24";
              localAddress6 = "${auth.ip6}/112";
            };
            "${auth-pg.auth.interface}" = with auth-pg; {
              hostBridge = name;
              localAddress = "${auth.ip4}/24";
              localAddress6 = "${auth.ip6}/112";
            };
            "${auth-redis.auth.interface}" = with auth-redis; {
              hostBridge = name;
              localAddress = "${auth.ip4}/24";
              localAddress6 = "${auth.ip6}/112";
            };
          };

          privateUsers = config.users.users.authelia.uid;
          autoStart = true;
          extraFlags = [
            "--private-users-ownership=auto"
            "--volatile=overlay"
            "--link-journal=host"
            "--load-credential=csec-creds:${config.sops.secrets."authelia/crowdsec".path}"
            "--load-credential=ldap-pass:${config.sops.secrets."authelia/ldap".path}"
            "--load-credential=jwt:${config.sops.secrets."authelia/jwt".path}"
            "--load-credential=oidc-hmac:${config.sops.secrets."authelia/oidc-hmac".path}"
            "--load-credential=oidc-jwks:${config.sops.secrets."authelia/oidc-jwks".path}"
            "--load-credential=pg-pass:${config.sops.secrets."authelia/postgres".path}"
            "--load-credential=redis-pass:${config.sops.secrets."authelia/redis".path}"
            "--load-credential=sess:${config.sops.secrets."authelia/session".path}"
            "--load-credential=storage-enc:${config.sops.secrets."authelia/storage".path}"
          ];

          bindMounts.data = {
            hostPath = config.modules.authelia.dataDir;
            mountPoint = configDir;
            isReadOnly = false;
          };

          config =
            { ... }:
            {
              imports = [ ../vendored/crowdsec.nix ];

              # To allow this container to access the internet through the bridge.
              networking.defaultGateway = {
                address = constants.bridges.auth-caddy.caddy.ip4;
                interface = "eth0";
              };
              networking.defaultGateway6 = {
                address = constants.bridges.auth-caddy.caddy.ip6;
                interface = "eth0";
              };
              networking.nameservers = [ "1.1.1.1" ];
              networking.firewall.allowedTCPPorts = [ constants.ports.authelia ];

              services.authelia.instances.main = with config.modules.authelia; {
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
                      redis.host = auth-redis.redis.ip4;
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
                  AUTHELIA_SESSION_REDIS_PASSWORD_FILE = "%d/redis-pass";
                  AUTHELIA_SESSION_SECRET_FILE = "%d/sess";
                  AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE = "%d/storage-enc";
                  AUTHELIA_STORAGE_POSTGRES_PASSWORD_FILE = "%d/pg-pass";
                  X_AUTHELIA_CONFIG_FILTERS = "template";
                };
              };
              systemd.services.authelia-main.serviceConfig.LoadCredential = [
                "jwt:jwt"
                "ldap-pass:ldap-pass"
                "oidc-hmac:oidc-hmac"
                "oidc-jwks:oidc-jwks"
                "pg-pass:pg-pass"
                "redis-pass:redis-pass"
                "sess:sess"
                "storage-enc:storage-enc"
              ];

              services.crowdsec = lib.mkIf csecEnabled {
                enable = true;
                autoUpdateService = true;
                name = "${config.networking.hostName}-authelia";

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

              system.stateVersion = "25.05";
            };
        };

        containers.authelia-redis = {
          privateNetwork = true;
          hostBridge = constants.bridges.auth-redis.name;
          localAddress = "${constants.bridges.auth-redis.redis.ip4}/24";
          localAddress6 = "${constants.bridges.auth-redis.redis.ip6}/112";

          privateUsers = "pick";
          autoStart = true;
          extraFlags = [
            "--private-users-ownership=auto"
            "--volatile=overlay"
            "--link-journal=host"
            "--load-credential=pass:${config.sops.secrets."authelia/redis".path}"
          ];

          config =
            { ... }:
            {
              services.redis.package = pkgs.valkey;
              services.redis.servers."" = {
                enable = true;
                bind = null;
                openFirewall = true;
                requirePassFile = "/run/redis/passfile";
                save = [ ];
              };
              systemd.services.redis.serviceConfig = {
                # `requirePassFile` needs an absolute path, so copy the credential to a directory that the setup script can access.
                ExecStartPre = lib.mkBefore [
                  "${lib.getExe' pkgs.coreutils-full "install"} -m600 \${CREDENTIALS_DIRECTORY}/pass /run/redis/passfile"
                ];
                LoadCredential = [ "pass:pass" ];
              };

              system.stateVersion = "25.05";
            };
        };
      };
}
