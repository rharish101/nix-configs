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
    secrets = {
      crowdsec = lib.mkOption {
        description = "Path to the CrowdSec Local API credentials file";
        type = lib.types.path;
      };
      ldap = lib.mkOption {
        description = "Path to the lldap password file";
        type = lib.types.path;
      };
      jwt = lib.mkOption {
        description = "Path to the JWT secret file";
        type = lib.types.path;
      };
      postgres = lib.mkOption {
        description = "Path to the PostgreSQL password file";
        type = lib.types.path;
      };
      redis = lib.mkOption {
        description = "Path to the Redis password file";
        type = lib.types.path;
      };
      session = lib.mkOption {
        description = "Path to the session secret file";
        type = lib.types.path;
      };
      storage = lib.mkOption {
        description = "Path to the storage encryption secret file";
        type = lib.types.path;
      };
    };
  };
  config =
    let
      constants = import ../constants.nix;
      cpu_limit = 2;
      memory_limit = 2; # in GiB
      csec_enabled = config.modules.crowdsec-lapi.enable;
      ldap_base_dn = "dc=rharish,dc=dev";
      data_dir = "/var/lib/authelia-main/configs"; # MUST be a (sub)directory of "/var/lib/authelia-{instanceName}"
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

        systemd.services."container@authelia" = {
          serviceConfig = {
            MemoryHigh = "${toString memory_limit}G";
            CPUQuota = "${toString (cpu_limit * 100)}%";
          };
          requires = [
            (lib.mkIf csec_enabled "container@crowdsec-lapi.service")
            "container@lldap.service"
            "container@postgres.service"
            "container@authelia-redis.service"
          ];
        };

        networking.bridges = with constants.bridges; {
          "${auth-caddy.name}".interfaces = [ ];
          "${auth-csec.name}" = lib.mkIf csec_enabled { interfaces = [ ]; };
          "${auth-ldap.name}".interfaces = [ ];
          "${auth-pg.name}".interfaces = [ ];
          "${auth-redis.name}".interfaces = [ ];
        };

        containers.caddy-wg-client.extraVeths."${constants.bridges.auth-caddy.caddy.interface}" =
          with constants.bridges.auth-caddy; {
            hostBridge = name;
            localAddress = "${caddy.ip4}/24";
            localAddress6 = "${caddy.ip6}/112";
          };
        containers.crowdsec-lapi.extraVeths."${constants.bridges.auth-csec.csec.interface}" =
          with constants.bridges.auth-csec;
          lib.mkIf csec_enabled {
            hostBridge = name;
            localAddress = "${csec.ip4}/24";
            localAddress6 = "${csec.ip6}/112";
          };
        containers.lldap = with constants.bridges.auth-ldap; {
          hostBridge = name;
          localAddress = "${ldap.ip4}/24";
          localAddress6 = "${ldap.ip6}/112";
        };
        containers.postgres.extraVeths."${constants.bridges.auth-pg.pg.interface}" =
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
              lib.mkIf csec_enabled {
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
          extraFlags = [ "--private-users-ownership=auto" ];

          autoStart = true;
          ephemeral = true;

          bindMounts = with config.modules.authelia; {
            data = {
              hostPath = dataDir;
              mountPoint = data_dir;
              isReadOnly = false;
            };
            crowdsec = lib.mkIf csec_enabled {
              hostPath = secrets.crowdsec;
              mountPoint = secrets.crowdsec;
            };
            ldap = {
              hostPath = secrets.ldap;
              mountPoint = secrets.ldap;
            };
            jwt = {
              hostPath = secrets.jwt;
              mountPoint = secrets.jwt;
            };
            postgres = {
              hostPath = secrets.postgres;
              mountPoint = secrets.postgres;
            };
            redis = {
              hostPath = secrets.redis;
              mountPoint = secrets.redis;
            };
            session = {
              hostPath = secrets.session;
              mountPoint = secrets.session;
            };
            storage = {
              hostPath = secrets.storage;
              mountPoint = secrets.storage;
            };
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
              networking.firewall.allowedTCPPorts = [ 9091 ];

              services.authelia.instances.main = with config.modules.authelia; {
                enable = true;
                user = "root";
                group = "root";
                secrets = with secrets; {
                  jwtSecretFile = jwt;
                  sessionSecretFile = session;
                  storageEncryptionKeyFile = storage;
                };
                settings = {
                  default_2fa_method = "totp";
                  theme = "auto";
                };
                settingsFiles = [ ../../configs/authelia.yml ];
                environmentVariables = with constants.bridges; {
                  AUTHELIA_AUTHENTICATION_BACKEND_LDAP_ADDRESS = "ldap://${auth-ldap.ldap.ip4}:3890";
                  AUTHELIA_AUTHENTICATION_BACKEND_LDAP_IMPLEMENTATION = "lldap";
                  AUTHELIA_AUTHENTICATION_BACKEND_LDAP_BASE_DN = ldap_base_dn;
                  AUTHELIA_AUTHENTICATION_BACKEND_LDAP_ADDITIONAL_USERS_DN = "ou=people";
                  AUTHELIA_AUTHENTICATION_BACKEND_LDAP_USER = "uid=authelia,ou=people,${ldap_base_dn}";
                  AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE = secrets.ldap;
                  AUTHELIA_NOTIFIER_FILESYSTEM_FILENAME = "${data_dir}/notification.txt";
                  AUTHELIA_STORAGE_POSTGRES_ADDRESS = "tcp://${auth-pg.pg.ip4}:5432";
                  AUTHELIA_STORAGE_POSTGRES_DATABASE = "authelia";
                  AUTHELIA_STORAGE_POSTGRES_USERNAME = "authelia";
                  AUTHELIA_STORAGE_POSTGRES_PASSWORD_FILE = secrets.postgres;
                  AUTHELIA_SESSION_REDIS_HOST = auth-redis.redis.ip4;
                  AUTHELIA_SESSION_REDIS_PASSWORD_FILE = secrets.redis;
                };
              };

              services.crowdsec = lib.mkIf csec_enabled {
                enable = true;
                autoUpdateService = true;
                name = "${config.networking.hostName}-authelia";

                user = "root";
                group = "root";

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
                settings.lapi.credentialsFile = config.modules.authelia.secrets.crowdsec;
              };

              system.stateVersion = "25.05";
            };
        };

        containers.authelia-redis = {
          privateNetwork = true;
          hostBridge = constants.bridges.auth-redis.name;
          localAddress = "${constants.bridges.auth-redis.redis.ip4}/24";
          localAddress6 = "${constants.bridges.auth-redis.redis.ip6}/112";

          privateUsers = config.users.users.authelia.uid;
          extraFlags = [ "--private-users-ownership=auto" ];

          autoStart = true;
          ephemeral = true;

          bindMounts.redis = with config.modules.authelia.secrets; {
            hostPath = redis;
            mountPoint = redis;
          };

          config =
            { ... }:
            {
              services.redis.package = pkgs.valkey;
              services.redis.servers."" = {
                enable = true;
                bind = null;
                openFirewall = true;
                requirePassFile = config.modules.authelia.secrets.redis;
                save = [ ];
              };

              system.stateVersion = "25.05";
            };
        };
      };
}
