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
  options.modules.lldap.enable = lib.mkEnableOption "Enable lldap";
  config =
    let
      constants = import ../constants.nix;
      lldap_key_config = {
        owner = "lldap";
        group = "lldap";
        restartUnits = [ "container@lldap.service" ];
      };
    in
    lib.mkIf (config.modules.lldap.enable && config.modules.postgres.enable) {
      # User for the lldap container.
      users.users.lldap = {
        uid = constants.uids.lldap;
        group = "lldap";
        isSystemUser = true;
      };
      users.groups.lldap.gid = constants.uids.lldap;

      sops.secrets."lldap/db" = lldap_key_config;
      sops.secrets."lldap/jwt" = lldap_key_config;
      sops.secrets."lldap/key" = lldap_key_config;
      sops.secrets."lldap/pass" = lldap_key_config;

      systemd.services."container@lldap".requires = [ "container@postgres.service" ];

      networking.bridges."${constants.bridges.ldap-pg.name}".interfaces = [ ];
      containers.postgres.extraVeths."${constants.bridges.ldap-pg.pg.interface}" =
        with constants.bridges.ldap-pg; {
          hostBridge = name;
          localAddress = "${pg.ip4}/24";
          localAddress6 = "${pg.ip6}/112";
        };

      containers.lldap =
        let
          db_file = config.sops.secrets."lldap/db".path;
          jwt_file = config.sops.secrets."lldap/jwt".path;
          key_seed_file = config.sops.secrets."lldap/key".path;
          user_pass_file = config.sops.secrets."lldap/pass".path;
        in
        {
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

          bindMounts = {
            dbUrl = {
              hostPath = db_file;
              mountPoint = db_file;
            };
            jwt = {
              hostPath = jwt_file;
              mountPoint = jwt_file;
            };
            keySeed = {
              hostPath = key_seed_file;
              mountPoint = key_seed_file;
            };
            userPass = {
              hostPath = user_pass_file;
              mountPoint = user_pass_file;
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
                  ldap_base_dn = constants.domain.ldap_base_dn;
                  ldap_port = constants.ports.lldap;
                };
                environment = {
                  LLDAP_DATABASE_URL_FILE = db_file;
                  LLDAP_JWT_SECRET_FILE = jwt_file;
                  LLDAP_KEY_SEED_FILE = key_seed_file;
                  LLDAP_LDAP_USER_PASS_FILE = user_pass_file;
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
