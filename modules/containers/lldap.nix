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
  options.modules.lldap = {
    enable = lib.mkEnableOption "Enable lldap";
    secrets = {
      dbUrl = lib.mkOption {
        description = "Path to the file with the database URL";
        type = lib.types.path;
      };
      jwt = lib.mkOption {
        description = "Path to the JWT secret file";
        type = lib.types.path;
      };
      keySeed = lib.mkOption {
        description = "Path to the key seed secret file";
        type = lib.types.path;
      };
      userPass = lib.mkOption {
        description = "Path to the admin user password file";
        type = lib.types.path;
      };
    };
  };
  config =
    let
      priv_uid_gid = 65536 * 14; # Randomly-chosen UID/GID a/c to how systemd-nspawn chooses one for the user namespacing
      ldap_base_dn = "dc=rharish,dc=dev";
      postgres_br_name = "br-ldap-pg";
    in
    lib.mkIf config.modules.lldap.enable {
      # User for the lldap container.
      users.users.lldap = {
        uid = priv_uid_gid;
        group = "lldap";
        isSystemUser = true;
      };
      users.groups.lldap.gid = priv_uid_gid;

      systemd.services."container@lldap".requires = [ "container@postgres.service" ];

      networking.bridges."${postgres_br_name}".interfaces = [ ];
      containers.postgres.extraVeths.pg-ldap = {
        hostBridge = postgres_br_name;
        localAddress = "10.5.0.2/24";
        localAddress6 = "fc00::42/112";
      };

      containers.lldap = {
        privateNetwork = true;
        extraVeths.ldap-pg = {
          hostBridge = postgres_br_name;
          localAddress = "10.5.0.1/24";
          localAddress6 = "fc00::41/112";
        };

        privateUsers = config.users.users.lldap.uid;
        extraFlags = [ "--private-users-ownership=auto" ];

        autoStart = true;
        ephemeral = true;

        bindMounts = with config.modules.lldap.secrets; {
          dbUrl = {
            hostPath = dbUrl;
            mountPoint = dbUrl;
          };
          jwt = {
            hostPath = jwt;
            mountPoint = jwt;
          };
          keySeed = {
            hostPath = keySeed;
            mountPoint = keySeed;
          };
          userPass = {
            hostPath = userPass;
            mountPoint = userPass;
          };
        };

        config =
          { ... }:
          {
            networking.firewall.allowedTCPPorts = [ 3890 ];

            environment.defaultPackages = with pkgs; [ lldap-cli ];

            services.lldap = {
              enable = true;
              settings = {
                ldap_base_dn = ldap_base_dn;
              };
              environment = with config.modules.lldap.secrets; {
                LLDAP_DATABASE_URL_FILE = dbUrl;
                LLDAP_JWT_SECRET_FILE = jwt;
                LLDAP_KEY_SEED_FILE = keySeed;
                LLDAP_LDAP_USER_PASS_FILE = userPass;
              };
            };
            systemd.services.lldap.serviceConfig = {
              User = lib.mkForce "root";
              Group = lib.mkForce "root";
            };

            system.stateVersion = "25.05";
          };
      };
    };
}
