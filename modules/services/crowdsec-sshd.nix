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
  imports = [ ../vendored/crowdsec.nix ];
  config = lib.mkIf config.modules.crowdsec-sshd.enable {
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
      settings.lapi.credentialsFile = config.modules.crowdsec-sshd.secrets.credFile;
    };
  };
}
