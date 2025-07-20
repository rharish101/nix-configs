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
      secretsConfig = {
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

      sops.secrets."lldap/db" = secretsConfig;
      sops.secrets."lldap/jwt" = secretsConfig;
      sops.secrets."lldap/key" = secretsConfig;
      sops.secrets."lldap/pass" = secretsConfig;

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
          dbUrlFile = config.sops.secrets."lldap/db".path;
          jwtFile = config.sops.secrets."lldap/jwt".path;
          keySeedFile = config.sops.secrets."lldap/key".path;
          userPassFile = config.sops.secrets."lldap/pass".path;
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
              hostPath = dbUrlFile;
              mountPoint = dbUrlFile;
            };
            jwt = {
              hostPath = jwtFile;
              mountPoint = jwtFile;
            };
            keySeed = {
              hostPath = keySeedFile;
              mountPoint = keySeedFile;
            };
            userPass = {
              hostPath = userPassFile;
              mountPoint = userPassFile;
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
                  ldap_base_dn = constants.domain.ldapBaseDn;
                  ldap_port = constants.ports.lldap;
                };
                environment = {
                  LLDAP_DATABASE_URL_FILE = dbUrlFile;
                  LLDAP_JWT_SECRET_FILE = jwtFile;
                  LLDAP_KEY_SEED_FILE = keySeedFile;
                  LLDAP_LDAP_USER_PASS_FILE = userPassFile;
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
