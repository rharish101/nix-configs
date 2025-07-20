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
      csec_enabled = config.modules.crowdsec-lapi.enable;
      data_dir = "/var/lib/authelia-main/configs"; # MUST be a (sub)directory of "/var/lib/authelia-{instanceName}"
      authelia_key_config = {
        owner = "authelia";
        group = "authelia";
        restartUnits = [ "container@authelia.service" ];
      };
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

        sops.secrets."authelia/crowdsec" = authelia_key_config;
        sops.secrets."authelia/ldap" = authelia_key_config;
        sops.secrets."authelia/jwt" = authelia_key_config;
        sops.secrets."authelia/postgres" = authelia_key_config;
        sops.secrets."authelia/redis" = authelia_key_config // {
          restartUnits = [
            "container@authelia.service"
            "container@authelia-redis.service"
          ];
        };
        sops.secrets."authelia/session" = authelia_key_config;
        sops.secrets."authelia/storage" = authelia_key_config;

        systemd.services."container@authelia" = {
          serviceConfig = with constants.limits.authelia; {
            MemoryHigh = "${toString memory}G";
            CPUQuota = "${toString (cpu * 100)}%";
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

        containers.authelia =
          let
            csec_file = config.sops.secrets."authelia/crowdsec".path;
            ldap_file = config.sops.secrets."authelia/ldap".path;
            jwt_file = config.sops.secrets."authelia/jwt".path;
            pg_file = config.sops.secrets."authelia/postgres".path;
            redis_file = config.sops.secrets."authelia/redis".path;
            sess_file = config.sops.secrets."authelia/session".path;
            storage_file = config.sops.secrets."authelia/storage".path;
          in
          {
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
                hostPath = csec_file;
                mountPoint = csec_file;
              };
              ldap = {
                hostPath = ldap_file;
                mountPoint = ldap_file;
              };
              jwt = {
                hostPath = jwt_file;
                mountPoint = jwt_file;
              };
              postgres = {
                hostPath = pg_file;
                mountPoint = pg_file;
              };
              redis = {
                hostPath = redis_file;
                mountPoint = redis_file;
              };
              session = {
                hostPath = sess_file;
                mountPoint = sess_file;
              };
              storage = {
                hostPath = storage_file;
                mountPoint = storage_file;
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
                networking.firewall.allowedTCPPorts = [ constants.ports.authelia ];

                services.authelia.instances.main = with config.modules.authelia; {
                  enable = true;
                  user = "root";
                  group = "root";
                  secrets = {
                    jwtSecretFile = jwt_file;
                    sessionSecretFile = sess_file;
                    storageEncryptionKeyFile = storage_file;
                  };
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
                        base_dn = ldap_base_dn;
                        additional_users_dn = "ou=people";
                        user = "uid=authelia,ou=people,${ldap_base_dn}";
                      };
                      storage.postgres = {
                        address = "tcp://${auth-pg.pg.ip4}:${toString postgres}";
                        database = "authelia";
                        username = "authelia";
                      };
                      session = {
                        redis = {
                          host = auth-redis.redis.ip4;
                        };
                        cookies = [
                          {
                            domain = domain;
                            authelia_url = "https://${subdomains.auth}.${domain}";
                          }
                        ];
                      };
                      notifier.filesystem.filename = "${data_dir}/notification.txt";
                      access_control.rules = [
                        {
                          domain = "*.${domain}";
                          policy = "two_factor";
                        }
                      ];
                    };
                  environmentVariables = {
                    AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE = ldap_file;
                    AUTHELIA_STORAGE_POSTGRES_PASSWORD_FILE = pg_file;
                    AUTHELIA_SESSION_REDIS_PASSWORD_FILE = redis_file;
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
                  settings.lapi.credentialsFile = csec_file;
                };

                system.stateVersion = "25.05";
              };
          };

        containers.authelia-redis =
          let
            pass_file = config.sops.secrets."authelia/redis".path;
          in
          {
            privateNetwork = true;
            hostBridge = constants.bridges.auth-redis.name;
            localAddress = "${constants.bridges.auth-redis.redis.ip4}/24";
            localAddress6 = "${constants.bridges.auth-redis.redis.ip6}/112";

            privateUsers = config.users.users.authelia.uid;
            extraFlags = [ "--private-users-ownership=auto" ];

            autoStart = true;
            ephemeral = true;

            bindMounts.redis = {
              hostPath = pass_file;
              mountPoint = pass_file;
            };

            config =
              { ... }:
              {
                services.redis.package = pkgs.valkey;
                services.redis.servers."" = {
                  enable = true;
                  bind = null;
                  openFirewall = true;
                  requirePassFile = pass_file;
                  save = [ ];
                };

                system.stateVersion = "25.05";
              };
          };
      };
}
