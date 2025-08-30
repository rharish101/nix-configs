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
  options.modules.immich = {
    enable = lib.mkEnableOption "Enable Immich";
    dataDir = lib.mkOption {
      description = "The Immich directory path";
      type = lib.types.str;
    };
  };
  config =
    let
      constants = import ../constants.nix;
      gpuDevice = "/dev/dri/renderD128";
    in
    lib.mkIf
      (
        config.modules.immich.enable
        && config.modules.caddy-wg-client.enable
        && config.modules.postgres.enable
      )
      {
        # Immich doesn't have a way to pass the OIDC client secret as an env var or path, so create
        # a config manually and add it as a placeholder.
        sops.secrets."immich/oidc".restartUnits = [ "container@immich.service" ];
        sops.templates."immich.json" = {
          content =
            with constants.domain;
            builtins.toJSON {
              server.externalDomain = "https://${subdomains.imm}.${domain}";
              passwordLogin.enabled = false;
              ffmpeg = {
                accel = "qsv";
                accelDecode = true;
                acceptedVideoCodecs = [
                  "h264"
                  "hevc"
                  "vp9"
                  "av1"
                ];
              };
              oauth = {
                enabled = true;
                issuerUrl = "https://${subdomains.auth}.${domain}/.well-known/openid-configuration";
                clientId = "JuhCQHaHI65vm~.Oyw7F~X9nFiJpC1UsyxMzthVhDHwzjfcJhofhxV43Ezcs31Er";
                clientSecret = config.sops.placeholder."immich/oidc";
                buttonText = "Login with Authelia";
                autoRegister = false;
              };
              backup.database.enabled = false;
            };
        };

        modules.containers.immich = {
          shortName = "imm";
          username = "immich";
          allowInternet = true;

          credentials = {
            env.name = "immich/env";
            config = {
              name = "immich.json";
              sopsType = "template";
            };
          };

          bindMounts = with config.modules.immich; {
            dataDir = {
              hostPath = dataDir;
              mountPoint = "/var/lib/immich";
              isReadOnly = false;
            };
            render.mountPoint = "/dev/dri";
            usb.mountPoint = "/dev/bus/usb";
          };

          allowedDevices = [
            {
              node = gpuDevice;
              modifier = "rw";
            }
          ];

          config =
            { ... }:
            {
              hardware.graphics = {
                enable = true;
                extraPackages = with pkgs; [
                  intel-media-driver
                  vpl-gpu-rt
                ];
              };

              services.immich = {
                enable = true;
                host = "0.0.0.0";
                port = constants.ports.immich;
                openFirewall = true;
                secretsFile = "/run/credentials/@system/env";
                database = {
                  enable = false;
                  host = constants.bridges.imm-pg.pg.ip4;
                  port = constants.ports.postgres;
                };
                accelerationDevices = [ gpuDevice ];
                # XXX: Workaround for: https://github.com/NixOS/nixpkgs/issues/418799
                machine-learning.environment =
                  let
                    cacheDir = "/var/cache/immich";
                  in
                  {
                    MPLCONFIGDIR = cacheDir;
                    HF_XET_CACHE = "${cacheDir}/huggingface-xet";
                  };
              };
              systemd.services.immich-server = {
                serviceConfig.LoadCredential = [ "config:config" ];
                environment.IMMICH_CONFIG_FILE = "%d/config";
              };

              system.stateVersion = "25.05";
            };
        };
      };
}
