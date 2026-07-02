# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
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
      constants = import ../constants.nix lib;
      gpuDevice = "/dev/dri/renderD128";
    in
    lib.mkIf config.modules.immich.enable {
      modules.containers.immich = {
        allowedPorts.Tcp = [ constants.ports.immich ];
        username = "immich";

        allowedDevices = [
          {
            node = gpuDevice;
            modifier = "rw";
          }
        ];

        bindMounts = with config.modules.immich; {
          dataDir = {
            hostPath = dataDir;
            mountPoint = "/var/lib/immich";
            isReadOnly = false;
          };
          render.mountPoint = "/dev/dri";
          usb.mountPoint = "/dev/bus/usb";
        };

        credentials = {
          env.name = "immich/env";
          oidc.name = "immich/oidc";
        };

        config =
          { pkgs, ... }:
          {
            hardware.graphics = {
              enable = true;
              extraPackages = with pkgs; [
                intel-media-driver
                vpl-gpu-rt
                intel-compute-runtime
              ];
            };

            services.immich = {
              enable = true;
              host = "0.0.0.0";
              port = constants.ports.immich;
              secretsFile = "/run/credentials/@system/env";
              database = {
                enable = false;
                host = constants.bridge.postgres.ip4;
                port = constants.ports.postgres;
              };
              accelerationDevices = [ gpuDevice ];
              settings = {
                server.externalDomain = with constants.domain; "https://${subdomains.immich}.${domain}";
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
                  issuerUrl =
                    with constants.domain;
                    "https://${subdomains.authelia}.${domain}/.well-known/openid-configuration";
                  clientId = "JuhCQHaHI65vm~.Oyw7F~X9nFiJpC1UsyxMzthVhDHwzjfcJhofhxV43Ezcs31Er";
                  clientSecret._secret = "oidc";
                  buttonText = "Login with Authelia";
                  autoRegister = false;
                };
                backup.database.enabled = false;
              };
            };

            system.stateVersion = "25.05";
          };
      };
    };
}
