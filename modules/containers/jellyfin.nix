# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.jellyfin = {
    enable = lib.mkEnableOption "Jellyfin";
    dataDir = lib.mkOption {
      description = "The Jellyfin directory path";
      type = lib.types.str;
    };
  };
  config =
    let
      constants = import ../constants.nix lib;
      gpuDevice = "/dev/dri/renderD128";
    in
    lib.mkIf config.modules.jellyfin.enable {
      sops.secrets."jellyfin/crowdsec" = { };
      sops.templates."jellyfin/csec-creds".content = ''
        url: http://${constants.bridge.crowdsec-lapi.ip4}:${toString constants.ports.crowdsec}
        login: ${config.networking.hostName}-jellyfin
        password: ${config.sops.placeholder."jellyfin/crowdsec"}
      '';

      modules.containers.jellyfin = {
        allowedPorts.Tcp = [ constants.ports.jellyfin ];
        username = "jellyfin";

        allowedDevices = [
          {
            node = gpuDevice;
            modifier = "rw";
          }
        ];

        credentials.csec-creds = {
          name = "jellyfin/csec-creds";
          sopsType = "template";
        };

        dirMounts = with config.modules.jellyfin; {
          data = {
            hostPath = "${dataDir}/data";
            mountPoint = "/var/lib/jellyfin";
            isReadOnly = false;
          };
          media = {
            hostPath = "${dataDir}/media";
            mountPoint = "/media";
            isReadOnly = false;
          };
        };
        bindMounts.render = {
          mountPoint = gpuDevice;
          isReadOnly = false;
        };

        config =
          let
            hostName = config.networking.hostName;
          in
          { pkgs, ... }:
          {
            hardware.graphics = {
              enable = true;
              extraPackages = with pkgs; [
                intel-ocl
                intel-media-driver
                vpl-gpu-rt
                intel-compute-runtime
              ];
            };
            nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "intel-ocl" ];

            services.jellyfin = {
              enable = true;
              hardwareAcceleration = {
                enable = true;
                device = gpuDevice;
                type = "qsv";
              };
              transcoding = {
                enableHardwareEncoding = true;
                enableIntelLowPowerEncoding = true;
                deleteSegments = false;
                hardwareDecodingCodecs = {
                  av1 = true;
                  h264 = true;
                  hevc = true;
                  hevc10bit = true;
                  hevcRExt10bit = true;
                  hevcRExt12bit = true;
                  mpeg2 = true;
                  vp8 = true;
                  vp9 = true;
                };
                hardwareEncodingCodecs = {
                  hevc = true;
                  av1 = true;
                };
              };
            };
            systemd.services.jellyfin.environment.LIBVA_DRIVER_NAME = "iHD";

            services.crowdsec = lib.mkIf config.modules.crowdsec-lapi.enable {
              enable = true;
              autoUpdateService = true;
              name = "${hostName}-jellyfin";

              localConfig.acquisitions = [
                {
                  source = "journalctl";
                  journalctl_filter = [ "_SYSTEMD_UNIT=jellyfin.service" ];
                  labels.type = "syslog";
                  use_time_machine = true;
                }
              ];
              hub.collections = [
                "crowdsecurity/linux"
                "LePresidente/jellyfin"
              ];
              settings.general.api.client.credentials_path = lib.mkForce "\${CREDENTIALS_DIRECTORY}/csec-creds";
            };
            systemd.services.crowdsec.serviceConfig.LoadCredential = [ "csec-creds:csec-creds" ];

            system.stateVersion = "25.05";
          };
      };
    };
}
