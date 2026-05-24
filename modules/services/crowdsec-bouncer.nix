# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.crowdsec-bouncer = {
    enable = lib.mkEnableOption "Enable CrowdSec firewall bouncer";
  };

  config =
    let
      constants = import ../constants.nix;
    in
    lib.mkIf config.modules.crowdsec-bouncer.enable {
      sops.secrets."crowdsec/bouncer".restartUnits = [ "crowdsec-firewall-bouncer.service" ];
      services.crowdsec-firewall-bouncer = {
        enable = true;
        settings.api_url =
          with constants;
          "http://${veths.caddy-wg-server.local.ip4}:${toString ports.crowdsec}";
        secrets.apiKeyPath = config.sops.secrets."crowdsec/bouncer".path;
        registerBouncer.enable = false;
      };

      # The bouncer sometimes fails on start, because it started too soon (before network connectivity to the local API).
      # Unfortunately, this module doesn't add restarts, so add them manually.
      systemd.services.crowdsec-firewall-bouncer.serviceConfig = {
        Restart = "on-failure";
        RestartSec = 10;
      };
    };
}
