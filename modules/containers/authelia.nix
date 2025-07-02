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
      jwt = lib.mkOption {
        description = "Path to the JWT secret file";
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
      cpu_limit = 2;
      memory_limit = 2; # in GiB
      priv_uid_gid = 65536 * 12; # Randomly-chosen UID/GID a/c to how systemd-nspawn chooses one for the user namespacing
      caddy_br_name = "br-auth-caddy";
      caddy_br_addr = "10.4.0.1";
      caddy_br_addr6 = "fc00::31";
      redis_br_name = "br-auth-redis";
      redis_br_addr_redis = "10.4.1.2";
      data_dir = "/var/lib/authelia-main/configs"; # MUST be a (sub)directory of "/var/lib/authelia-{instanceName}"
    in
    lib.mkIf config.modules.authelia.enable {
      # User for the Authelia container.
      users.users.authelia = {
        uid = priv_uid_gid;
        group = "authelia";
        isSystemUser = true;
      };
      users.groups.authelia.gid = priv_uid_gid;

      systemd.services."container@authelia" = {
        serviceConfig = {
          MemoryHigh = "${toString memory_limit}G";
          CPUQuota = "${toString (cpu_limit * 100)}%";
        };
        requires = [ "container@authelia-redis.service" ];
      };

      networking.bridges."${caddy_br_name}".interfaces = [ ];
      networking.bridges."${redis_br_name}".interfaces = [ ];
      containers.caddy-wg-client.extraVeths.caddy-auth = {
        hostBridge = caddy_br_name;
        localAddress = "${caddy_br_addr}/24";
        localAddress6 = "${caddy_br_addr6}/112";
      };

      containers.authelia = {
        privateNetwork = true;
        hostBridge = caddy_br_name;
        localAddress = "10.4.0.2/24";
        localAddress6 = "fc00::32/112";

        extraVeths.auth-redis = {
          hostBridge = redis_br_name;
          localAddress = "10.4.1.1/24";
          localAddress6 = "fc00::33/112";
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
          jwt = {
            hostPath = secrets.jwt;
            mountPoint = secrets.jwt;
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
            # To allow this container to access the internet through the bridge.
            networking.defaultGateway = {
              address = caddy_br_addr;
              interface = "eth0";
            };
            networking.defaultGateway6 = {
              address = caddy_br_addr6;
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
              environmentVariables = {
                AUTHELIA_AUTHENTICATION_BACKEND_FILE_PATH = "${data_dir}/users.yml";
                AUTHELIA_NOTIFIER_FILESYSTEM_FILENAME = "${data_dir}/notification.txt";
                AUTHELIA_STORAGE_LOCAL_PATH = "${data_dir}/db.sqlite3";
                AUTHELIA_SESSION_REDIS_HOST = redis_br_addr_redis;
                AUTHELIA_SESSION_REDIS_PASSWORD_FILE = secrets.redis;
              };
            };

            system.stateVersion = "25.05";
          };
      };

      containers.authelia-redis = {
        privateNetwork = true;
        hostBridge = redis_br_name;
        localAddress = "${redis_br_addr_redis}/24";
        localAddress6 = "fc00::34/112";

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
