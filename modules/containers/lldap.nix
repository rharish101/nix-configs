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
      secretsConfig.restartUnits = [ "container@lldap.service" ];
    in
    lib.mkIf (config.modules.lldap.enable && config.modules.postgres.enable) {
      sops.secrets."lldap/db" = secretsConfig;
      sops.secrets."lldap/jwt" = secretsConfig;
      sops.secrets."lldap/key" = secretsConfig;
      sops.secrets."lldap/pass" = secretsConfig;

      systemd.services."container@lldap".requires = [ "container@postgres.service" ];

      networking.bridges.${constants.bridges.ldap-pg.name}.interfaces = [ ];
      containers.postgres.extraVeths.${constants.bridges.ldap-pg.pg.interface} =
        with constants.bridges.ldap-pg; {
          hostBridge = name;
          localAddress = "${pg.ip4}/24";
          localAddress6 = "${pg.ip6}/112";
        };

      containers.lldap = {
        privateNetwork = true;
        extraVeths.${constants.bridges.ldap-pg.ldap.interface} = with constants.bridges.ldap-pg; {
          hostBridge = name;
          localAddress = "${ldap.ip4}/24";
          localAddress6 = "${ldap.ip6}/112";
        };

        privateUsers = "pick";
        autoStart = true;
        extraFlags = [
          "--private-users-ownership=auto"
          "--volatile=overlay"
          "--link-journal=host"
          "--load-credential=db-url:${config.sops.secrets."lldap/db".path}"
          "--load-credential=jwt:${config.sops.secrets."lldap/jwt".path}"
          "--load-credential=key-seed:${config.sops.secrets."lldap/key".path}"
          "--load-credential=user-pass:${config.sops.secrets."lldap/pass".path}"
        ];

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
              # These env vars are directly passed to systemd, so "%d" should be the credentials directory.
              environment = {
                LLDAP_DATABASE_URL_FILE = "%d/db-url";
                LLDAP_JWT_SECRET_FILE = "%d/jwt";
                LLDAP_KEY_SEED_FILE = "%d/key-seed";
                LLDAP_LDAP_USER_PASS_FILE = "%d/user-pass";
              };
            };
            systemd.services.lldap.serviceConfig.LoadCredential = [
              "db-url:db-url"
              "jwt:jwt"
              "key-seed:key-seed"
              "user-pass:user-pass"
            ];

            system.stateVersion = "25.05";
          };
      };
    };
}
