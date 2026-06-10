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
  options.modules.jellyfin = {
    enable = lib.mkEnableOption "Enable Jellyfin";
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
      modules.containers.jellyfin = {
        allowedPorts.Tcp = [ constants.ports.jellyfin ];
        credentials.csec-creds.name = "jellyfin/crowdsec";
        username = "jellyfin";

        allowedDevices = [
          {
            node = gpuDevice;
            modifier = "rw";
          }
        ];

        bindMounts = with config.modules.jellyfin; {
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
          render.mountPoint = "/dev/dri";
        };

        config =
          let
            hostName = config.networking.hostName;
          in
          { ... }:
          {
            hardware.graphics = {
              enable = true;
              extraPackages = with pkgs; [
                intel-media-driver
                vpl-gpu-rt
                intel-compute-runtime
              ];
            };

            services.jellyfin.enable = true;

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
