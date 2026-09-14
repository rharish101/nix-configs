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
  options.modules.dilbert.enable = lib.mkEnableOption "Dilbert Viewer";
  config =
    let
      constants = import ../constants.nix lib;
    in
    lib.mkIf config.modules.dilbert.enable {
      sops.templates."dilbert/env".content =
        let
          pgPassword = config.sops.placeholder."dilbert/postgres";
          pgHost = "${constants.bridge.postgres.ip4}:${toString constants.ports.postgres}";
        in
        ''
          DATABASE_URL='postgres://dilbert:${pgPassword}@${pgHost}/dilbert'
        '';

      modules.containers.dilbert = {
        allowedPorts.Tcp = [ constants.ports.dilbert ];

        credentials = {
          postgres.name = "dilbert/postgres";
          env = {
            name = "dilbert/env";
            sopsType = "template";
          };
        };

        config =
          { ... }:
          {
            imports = [ inputs.dilbert-viewer.nixosModules.default ];

            services.dilbert-viewer = {
              enable = true;
              host = "0.0.0.0";
              port = constants.ports.dilbert;
              environmentFile = "/run/credentials/@system/env";
            };

            system.stateVersion = "26.05";
          };
      };
    };
}
