# SPDX-FileCopyrightText: 2026 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.bazarr = {
    enable = lib.mkEnableOption "Enable Bazarr";
    dataDir = lib.mkOption {
      description = "The data directory path for Bazarr";
      type = lib.types.str;
    };
    mediaDirs = lib.mkOption {
      description = "The directories where media is to be saved and managed by Bazarr";
      type = with lib.types; attrsOf str;
      default = { };
    };
  };

  config =
    let
      constants = import ../constants.nix lib;
    in
    lib.mkIf config.modules.bazarr.enable {
      modules.containers.bazarr = {
        allowedPorts.Tcp = [ constants.ports.bazarr ];
        credentials.env.name = "bazarr";
        username = "bazarr";

        bindMounts =
          with config.modules.bazarr;
          {
            data = {
              hostPath = dataDir;
              mountPoint = "/var/lib/bazarr";
              isReadOnly = false;
            };
          }
          // builtins.mapAttrs (name: dir: {
            hostPath = dir;
            mountPoint = "/data/${name}";
            isReadOnly = false;
          }) mediaDirs;

        config =
          { ... }:
          {
            services.bazarr = {
              enable = true;
              listenPort = constants.ports.bazarr;
            };
            systemd.services.bazarr = {
              environment = {
                DYNACONF_ANALYTICS__ENABLED = "false";
                DYNACONF_BACKUP__FREQUENCY = "Manually";
                DYNACONF_GENERAL__AUTO_UPDATE = "false";
                DYNACONF_GENERAL__BASE_URL = "/subs";
                DYNACONF_GENERAL__HOSTNAME = with constants.domain; "${subdomains.arr}.${domain}";
                DYNACONF_GENERAL__PORT = toString constants.ports.bazarr;
                DYNACONF_GENERAL__USE_RADARR = "true";
                DYNACONF_GENERAL__USE_SONARR = "true";
                DYNACONF_RADARR__BASE_URL = "/movies";
                DYNACONF_RADARR__IP = constants.bridge.radarr.ip4;
                DYNACONF_RADARR__PORT = toString constants.ports.radarr;
                DYNACONF_SONARR__BASE_URL = "/shows";
                DYNACONF_SONARR__IP = constants.bridge.sonarr.ip4;
                DYNACONF_SONARR__PORT = toString constants.ports.sonarr;
                POSTGRES_DATABASE = "bazarr";
                POSTGRES_ENABLED = "true";
                POSTGRES_HOST = constants.bridge.postgres.ip4;
                POSTGRES_PORT = toString constants.ports.postgres;
                POSTGRES_USERNAME = "bazarr";
              };
              serviceConfig.EnvironmentFile = [ "/run/credentials/@system/env" ];
            };

            system.stateVersion = "26.05";
          };
      };
    };
}
