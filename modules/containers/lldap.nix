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
      constants = import ../constants.nix;
      ldap_base_dn = "dc=rharish,dc=dev";
    in
    lib.mkIf (config.modules.lldap.enable && config.modules.postgres.enable) {
      # User for the lldap container.
      users.users.lldap = {
        uid = constants.uids.lldap;
        group = "lldap";
        isSystemUser = true;
      };
      users.groups.lldap.gid = constants.uids.lldap;

      systemd.services."container@lldap".requires = [ "container@postgres.service" ];

      networking.bridges."${constants.bridges.ldap-pg.name}".interfaces = [ ];
      containers.postgres.extraVeths."${constants.bridges.ldap-pg.pg.interface}" =
        with constants.bridges.ldap-pg; {
          hostBridge = name;
          localAddress = "${pg.ip4}/24";
          localAddress6 = "${pg.ip6}/112";
        };

      containers.lldap = {
        privateNetwork = true;
        extraVeths."${constants.bridges.ldap-pg.ldap.interface}" = with constants.bridges.ldap-pg; {
          hostBridge = name;
          localAddress = "${ldap.ip4}/24";
          localAddress6 = "${ldap.ip6}/112";
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
            networking.firewall.allowedTCPPorts = [ constants.ports.lldap ];

            environment.defaultPackages = with pkgs; [ lldap-cli ];

            services.lldap = {
              enable = true;
              settings = {
                ldap_base_dn = ldap_base_dn;
                ldap_port = constants.ports.lldap;
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
