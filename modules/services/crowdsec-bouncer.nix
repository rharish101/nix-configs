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
      config_fmt = pkgs.formats.yaml { };
      config_file = config_fmt.generate "crowdsec-firewall-bouncer.yaml" {
        mode = "ipset";
        log_mode = "stdout";
        api_url = "\${API_URL}";
        api_key = "\${API_KEY}";
      };
      ip4_list = "crowdsec-blacklists";
      ip6_list = "crowdsec6-blacklists";
    in
    lib.mkIf config.modules.crowdsec-bouncer.enable {
      networking.firewall.extraPackages = [ pkgs.ipset ];
      networking.firewall.extraCommands = ''
        ipset -exist create ${ip4_list} hash:net timeout 3600
        ipset -exist create ${ip6_list} hash:net family inet6 timeout 3600
        iptables -A INPUT -m set --match-set ${ip4_list} src -j DROP
        iptables -A FORWARD -m set --match-set ${ip4_list} src -j DROP
        ip6tables -A INPUT -m set --match-set ${ip6_list} src -j DROP
        ip6tables -A FORWARD -m set --match-set ${ip6_list} src -j DROP
      '';

      environment.systemPackages = [
        package
        pkgs.ipset
      ];

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
        path = with pkgs; [
          iptables
          ipset
        ];
        serviceConfig = {
          Type = "notify";
          ExecStart = [ "${lib.getExe package} -c ${config_file}" ];
          ExecStartPre = [ "${lib.getExe package} -c ${config_file} -t" ];
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
