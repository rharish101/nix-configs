# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.crowdsec-sshd = {
    enable = lib.mkEnableOption "Enable CrowdSec SSH log processor";
    secrets.credFile = lib.mkOption {
      description = "Path to the CrowdSec Local API credentials file";
      type = lib.types.str;
    };
  };
  config = lib.mkIf config.modules.crowdsec-sshd.enable {
    sops.secrets."crowdsec/sshd-creds".restartUnits = [ "crowdsec.service" ];

    services.crowdsec = {
      enable = true;
      autoUpdateService = true;
      name = "${config.networking.hostName}-sshd";

      localConfig.acquisitions = [
        {
          source = "journalctl";
          journalctl_filter = [ "_SYSTEMD_UNIT=sshd.service" ];
          labels.type = "syslog";
          use_time_machine = true;
        }
      ];
      hub.collections = [ "crowdsecurity/linux" ];
      settings.general.api.client.credentials_path = lib.mkForce "\${CREDENTIALS_DIRECTORY}/csec-creds";
    };
    systemd.services.crowdsec.serviceConfig.LoadCredential = [
      "csec-creds:${config.sops.secrets."crowdsec/sshd-creds".path}"
    ];
  };
}
