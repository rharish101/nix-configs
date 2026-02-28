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
              in
              {
                enable = true;
                package = pkgs.caddy.withPlugins {
                  plugins = [
                    "github.com/caddy-dns/cloudflare@v0.2.3"
                    "github.com/mholt/caddy-l4@v0.0.0-20260216070754-eca560d759c9"
                    "github.com/mholt/caddy-ratelimit@v0.1.1-0.20260116163719-b8d8c9a9d99e"
                  ];
                  hash = "sha256-DfUx9HXNgroAzi4kWLv1xdReQwFrTLflVSYDSJDw2uU=";
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
                virtualHosts =
                  let
                    inherit (constants.domain) domain;
                    rateLimitConfig = ''
                      rate_limit {
                        zone global {
                          window 10s
                          events 20000
                        }
                        zone per_host {
                          key {remote_host}
                          window 10s
                          events 2000
                        }
                        jitter 0.2
                      }
                    '';
                    proxyConfig = ''
                      ${rateLimitConfig}
                      reverse_proxy ${clientIp}:80
                    '';
                  in
                  {
                    ":${toString constants.ports.crowdsec}".extraConfig = ''
                      ${rateLimitConfig}
                      reverse_proxy ${clientIp}:${toString constants.ports.crowdsec}
                    '';
                    ${domain}.extraConfig = proxyConfig;
                    "www.${domain}".extraConfig = ''
                      ${rateLimitConfig}
                      redir https://${domain} 301
                    '';
                  }
                  // lib.mapAttrs' (_: subdomain: {
                    name = "${subdomain}.${constants.domain.domain}";
                    value.extraConfig = proxyConfig;
                  }) constants.domain.subdomains;
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
