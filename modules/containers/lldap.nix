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
    in
    lib.mkIf (config.modules.lldap.enable && config.modules.postgres.enable) {
      modules.containers.lldap = {
        shortName = "ldap";
        credentials = {
          db-url.name = "lldap/db";
          jwt.name = "lldap/jwt";
          key-seed.name = "lldap/key";
          user-pass.name = "lldap/pass";
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
                force_ldap_user_pass_reset = "always";
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
