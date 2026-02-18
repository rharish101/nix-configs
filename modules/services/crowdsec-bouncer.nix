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
  options.modules.crowdsec-bouncer = {
    enable = lib.mkEnableOption "Enable CrowdSec firewall bouncer";
  };

  config =
    let
      package = pkgs.crowdsec-firewall-bouncer;
      configFmt = pkgs.formats.yaml { };
      configFile = configFmt.generate "crowdsec-firewall-bouncer.yaml" {
        mode = "nftables";
        nftables = {
          ipv4.set-only = true;
          ipv6.set-only = true;
        };
        log_mode = "stdout";
        api_url = "\${API_URL}";
        api_key = "\${API_KEY}";
      };
      ip4List = "crowdsec-blacklists";
      ip6List = "crowdsec6-blacklists";
    in
    lib.mkIf config.modules.crowdsec-bouncer.enable {
      networking.nftables.tables = {
        crowdsec = {
          name = "crowdsec";
          family = "ip";
          content = ''
            set ${ip4List} {
              type ipv4_addr
              flags timeout
            }
            chain crowdsec-chain {
              type filter hook input priority filter; policy accept;
              ip saddr @${ip4List} drop
            }
          '';
        };
        crowdsec6 = {
          name = "crowdsec6";
          family = "ip6";
          content = ''
            set ${ip6List} {
              type ipv6_addr
              flags timeout
            }
            chain crowdsec6-chain {
              type filter hook input priority filter; policy accept;
              ip6 saddr @${ip6List} drop
            }
          '';
        };
      };

      sops.secrets."crowdsec/bouncer-env".restartUnits = [ "crowdsec-firewall-bouncer.service" ];

      # Reference: https://github.com/crowdsecurity/cs-firewall-bouncer/blob/main/config/crowdsec-firewall-bouncer.service
      systemd.services.crowdsec-firewall-bouncer = {
        description = "The firewall bouncer for CrowdSec";
        after = [
          "syslog.target"
          "network.target"
          "remote-fs.target"
          "nss-lookup.target"
          "crowdsec.service"
        ];
        wantedBy = [ "multi-user.target" ];
        path = [
          package
          pkgs.nftables
        ];
        serviceConfig = {
          Type = "notify";
          ExecStart = [ "${lib.getExe package} -c ${configFile}" ];
          ExecStartPre = [ "${lib.getExe package} -c ${configFile} -t" ];
          ExecStartPost = [ "${lib.getExe' pkgs.coreutils-full "sleep"} 0.1" ];
          Restart = "always";
          RestartSec = 10;
          LimitNOFILE = 65536;
          KillMode = "mixed";
          EnvironmentFile = config.sops.secrets."crowdsec/bouncer-env".path;
        };
      };
    };
}
