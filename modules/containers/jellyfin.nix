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
      csecEnabled = config.modules.crowdsec-lapi.enable;
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

      sops.secrets."jellyfin/crowdsec".restartUnits = [ "container@jellyfin.service" ];

      systemd.services."container@jellyfin" = with constants.limits.jellyfin; {
        serviceConfig = {
          MemoryHigh = "${toString memory}G";
          CPUQuota = "${toString (cpu * 100)}%";
        };
        requires = [ (lib.mkIf csecEnabled "container@crowdsec-lapi.service") ];
      };

      networking.bridges = with constants.bridges; {
        ${caddy-jf.name}.interfaces = [ ];
        ${csec-jf.name} = lib.mkIf csecEnabled { interfaces = [ ]; };
      };
      containers.caddy-wg-client.extraVeths.${constants.bridges.caddy-jf.caddy.interface} =
        with constants.bridges.caddy-jf; {
          hostBridge = name;
          localAddress = "${caddy.ip4}/24";
          localAddress6 = "${caddy.ip6}/112";
        };
      containers.crowdsec-lapi.extraVeths.${constants.bridges.csec-jf.csec.interface} =
        with constants.bridges.csec-jf;
        lib.mkIf csecEnabled {
          hostBridge = name;
          localAddress = "${csec.ip4}/24";
          localAddress6 = "${csec.ip6}/112";
        };

      containers.jellyfin = {
        privateNetwork = true;
        hostBridge = constants.bridges.caddy-jf.name;
        localAddress = "${constants.bridges.caddy-jf.jf.ip4}/24";
        localAddress6 = "${constants.bridges.caddy-jf.jf.ip6}/112";

        privateUsers = config.users.users.jellyfin.uid;
        autoStart = true;
        extraFlags = [
          "--private-users-ownership=auto"
          "--volatile=overlay"
          "--link-journal=host"
          "--load-credential=csec-creds:${config.sops.secrets."jellyfin/crowdsec".path}"
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

            # To allow this container to access the internet through the bridge.
            networking.defaultGateway = {
              address = constants.bridges.caddy-jf.caddy.ip4;
              interface = "eth0";
            };
            networking.defaultGateway6 = {
              address = constants.bridges.caddy-jf.caddy.ip6;
              interface = "eth0";
            };
            networking.nameservers = [ "1.1.1.1" ];
            networking.firewall.allowedTCPPorts = [ constants.ports.jellyfin ];

            hardware.graphics = {
              enable = true;
              extraPackages = with pkgs; [
                intel-media-driver
                vpl-gpu-rt
              ];
            };

            services.jellyfin.enable = true;

            services.crowdsec = lib.mkIf csecEnabled {
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
