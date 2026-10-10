# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{
  config,
  inputs,
  lib,
  ...
}:
{
  options.modules.bookorbit = {
    enable = lib.mkEnableOption "BookOrbit";
    dataDir = lib.mkOption {
      description = "The BookOrbit directory path";
      type = lib.types.str;
    };
  };

  config =
    let
      constants = import ../constants.nix lib;
    in
    lib.mkIf config.modules.bookorbit.enable {
      sops.secrets."bookorbit/postgres" = { };
      sops.secrets."bookorbit/jwt" = { };
      sops.secrets."bookorbit/setup" = { };
      sops.templates."bookorbit/env".content =
        let
          pgPassword = config.sops.placeholder."bookorbit/postgres";
          pgHost = "${constants.bridge.postgres.ip4}:${toString constants.ports.postgres}";
        in
        ''
          DATABASE_URL='postgres://bookorbit:${pgPassword}@${pgHost}/bookorbit'
          JWT_SECRET=${config.sops.placeholder."bookorbit/jwt"}
          SETUP_BOOTSTRAP_TOKEN=${config.sops.placeholder."bookorbit/setup"}
        '';

      modules.containers.bookorbit = {
        allowedPorts.Tcp = [ constants.ports.bookorbit ];
        username = "bookorbit";

        credentials.env = {
          name = "bookorbit/env";
          sopsType = "template";
        };

        dirMounts.data = {
          hostPath = config.modules.bookorbit.dataDir;
          mountPoint = "/var/lib/bookorbit";
          isReadOnly = false;
        };

        config =
          { pkgs, ... }:
          {
            imports = [ "${inputs.nixpkgs-unstable}/nixos/modules/services/web-apps/bookorbit.nix" ];

            services.bookorbit = {
              enable = true;
              package = (import inputs.nixpkgs-unstable { system = pkgs.stdenv.hostPlatform.system; }).bookorbit;
              createDatabaseLocally = false;
              environment = {
                PORT = constants.ports.bookorbit;
                APP_URL = with constants.domain; "https://${subdomains.bookorbit}.${domain}";
                DISABLE_LOCAL_AUTH = "true";
              };
              environmentFile = "/run/credentials/@system/env";
            };
            systemd.services.bookorbit-migrate.serviceConfig.EnvironmentFile = "/run/credentials/@system/env";

            system.stateVersion = "26.11";
          };
      };
    };
}
