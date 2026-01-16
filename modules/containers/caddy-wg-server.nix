# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.caddy-wg-server = {
    enable = lib.mkEnableOption "Enable WireGuard server with public Caddy reverse proxy";
    wireguard = {
      port = lib.mkOption {
        description = "The port on the host that to be used for Wireguard";
        type = lib.types.int;
        default = 51820;
      };
      client.publicKey = lib.mkOption {
        description = "The public key for the client";
        type = lib.types.str;
      };
    };
    caddy.minecraftPort = lib.mkOption {
      description = "The port on the host that to be used for Minecraft";
      type = lib.types.int;
      default = 25565;
    };
    crowdsec.enable = lib.mkEnableOption "Enable CrowdSec Caddy log processor";
  };

  config =
    let
      constants = import ../constants.nix;
      caddyDataDir = "/var/lib/containers/caddy";
    in
    lib.mkIf config.modules.caddy-wg-server.enable {
      modules.containers.caddy-wg-server = {
        shortName = "caddy";
        username = "caddywg";
        credentials = {
          priv-key.name = "wireguard/server";
          psk.name = "wireguard/psk";
          caddy-env.name = "cloudflare";
          csec-creds.name = "crowdsec/caddy-creds";
        };

        forwardPorts = with config.modules.caddy-wg-server; [
          {
            containerPort = constants.ports.wireguard;
            hostPort = wireguard.port;
            protocol = "udp";
          }
          { hostPort = 443; }
          {
            hostPort = 443;
            protocol = "udp";
          }
          {
            hostPort = caddy.minecraftPort;
            containerPort = constants.ports.minecraft;
            protocol = "tcp";
          }
          {
            hostPort = caddy.minecraftPort;
            containerPort = constants.ports.minecraft;
            protocol = "udp";
          }
        ];

        bindMounts.dataDir = {
          hostPath = caddyDataDir;
          mountPoint = "/var/lib/caddy";
          isReadOnly = false;
        };

        config =
          { pkgs, ... }:
          {
            networking.firewall.allowedTCPPorts = with constants.ports; [
              443 # HTTPS
              minecraft # Minecraft Java
              crowdsec # CrowdSec LAPI
            ];
            networking.firewall.allowedUDPPorts = with constants.ports; [
              443 # QUIC
              minecraft # Minecraft Bedrock
              wireguard # WireGuard tunnel
            ];

            # Allow internet access for clients through the WireGuard tunnel.
            networking.nat = {
              enable = true;
              internalInterfaces = [ "wg0" ];
              externalInterface = "eth0";
            };

            networking.wg-quick.interfaces.wg0 = with config.modules.caddy-wg-server.wireguard; {
              address = [
                "${constants.veths.tunnel.server.ip4}/24"
                "${constants.veths.tunnel.server.ip6}/112"
              ];
              listenPort = constants.ports.wireguard;
              privateKeyFile = "$CREDENTIALS_DIRECTORY/priv-key";
              peers = [
                {
                  publicKey = client.publicKey;
                  presharedKeyFile = "$CREDENTIALS_DIRECTORY/psk";
                  allowedIPs = [
                    "${constants.veths.tunnel.client.ip4}/24"
                    "${constants.veths.tunnel.client.ip6}/112"
                  ];
                }
              ];
            };
            systemd.services.wg-quick-wg0.serviceConfig.LoadCredential = [
              "priv-key:priv-key"
              "psk:psk"
            ];

            services.caddy =
              let
                clientIp = constants.veths.tunnel.client.ip4;
                proxyConfig = "reverse_proxy ${clientIp}:80";
              in
              with constants.domain;
              {
                enable = true;
                package = pkgs.caddy.withPlugins {
                  plugins = [
                    "github.com/caddy-dns/cloudflare@v0.2.2"
                    "github.com/mholt/caddy-l4@v0.0.0-20260112235400-e24201789f06"
                  ];
                  hash = "sha256-OjFzC9ar5ZyC5TgIpulJ43l8ecgV47cnbevf1t2JZik=";
                };
                environmentFile = "/run/credentials/@system/caddy-env";
                email = "harish.rajagopals@gmail.com";
                globalConfig = with constants.ports; ''
                  dns cloudflare {
                    zone_token {env.ZONE_TOKEN}
                    api_token {env.DNS_TOKEN}
                  }
                  ech ${constants.domain.domain}
                  layer4 {
                    tcp/:${toString minecraft} {
                      route {
                        proxy {
                          proxy_protocol v2
                          upstream tcp/${clientIp}:${toString minecraft}
                        }
                      }
                    }
                    udp/:${toString minecraft} {
                      route {
                        proxy {
                          proxy_protocol v2
                          upstream udp/${clientIp}:${toString minecraft}
                        }
                      }
                    }
                  }
                '';
                virtualHosts.":${toString constants.ports.crowdsec}".extraConfig =
                  "reverse_proxy ${clientIp}:${toString constants.ports.crowdsec}";
                virtualHosts.${domain}.extraConfig = proxyConfig;
                virtualHosts."www.${domain}".extraConfig = "redir https://${domain} 301";
                virtualHosts."${subdomains.auth}.${domain}".extraConfig = proxyConfig;
                virtualHosts."${subdomains.cb}.${domain}".extraConfig = proxyConfig;
                virtualHosts."${subdomains.imm}.${domain}".extraConfig = proxyConfig;
                virtualHosts."${subdomains.jf}.${domain}".extraConfig = proxyConfig;
                virtualHosts."${subdomains.oc}.${domain}".extraConfig = proxyConfig;
                virtualHosts."${subdomains.tr}.${domain}".extraConfig = proxyConfig;
              };

            services.crowdsec = lib.mkIf config.modules.caddy-wg-server.crowdsec.enable {
              enable = true;
              autoUpdateService = true;
              name = "${config.networking.hostName}-caddy";

              localConfig.acquisitions = [
                {
                  source = "journalctl";
                  journalctl_filter = [ "_SYSTEMD_UNIT=caddy.service" ];
                  labels.type = "syslog";
                  use_time_machine = true;
                }
              ];
              hub.collections = [
                "crowdsecurity/linux"
                "crowdsecurity/caddy"
              ];
              settings.general.api.client.credentials_path = lib.mkForce "\${CREDENTIALS_DIRECTORY}/csec-creds";
            };
            systemd.services.crowdsec.serviceConfig.LoadCredential = [ "csec-creds:csec-creds" ];

            system.stateVersion = "25.05";
          };
      };
    };
}
