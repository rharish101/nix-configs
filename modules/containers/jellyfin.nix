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
      constants = import ../constants.nix;
      gpuDevice = "/dev/dri/renderD128";
    in
    lib.mkIf (config.modules.jellyfin.enable && config.modules.caddy-wg-client.enable) {
      # User for the Jellyfin container.
      users.users.jellyfin = {
        uid = constants.uids.jellyfin;
        group = "jellyfin";
        isSystemUser = true;
      };
      users.groups.jellyfin.gid = constants.uids.jellyfin;

      modules.containers.jellyfin = {
        shortName = "jf";
        username = "jellyfin";
        allowInternet = true;
        credentials.csec-creds.name = "jellyfin/crowdsec";

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

        allowedDevices = [
          {
            node = gpuDevice;
            modifier = "rw";
          }
        ];

        config =
          let
            hostName = config.networking.hostName;
          in
          { ... }:
          {
            imports = [ ../vendored/crowdsec.nix ];

            networking.firewall.allowedTCPPorts = [ constants.ports.jellyfin ];

            hardware.graphics = {
              enable = true;
              extraPackages = with pkgs; [
                intel-media-driver
                vpl-gpu-rt
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
