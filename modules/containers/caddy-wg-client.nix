# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.caddy-wg-client = {
    enable = lib.mkEnableOption "Enable Caddy reverse proxy with a WireGuard client";
    wireguard = {
      dns = lib.mkOption {
        description = "IP address for the DNS server";
        type = lib.types.str;
        default = "1.1.1.1";
      };
      server = {
        publicKey = lib.mkOption {
          description = "The public key for the server";
          type = lib.types.str;
        };
        address = lib.mkOption {
          description = "The IP address of the server";
          type = lib.types.str;
        };
        port = lib.mkOption {
          description = "The WireGuard port of the server";
          type = lib.types.int;
        };
      };
    };
  };

  config =
    let
      constants = import ../constants.nix;
      caddyDataDir = "/var/lib/containers/caddy";
    in
    lib.mkIf (config.modules.caddy-wg-client.enable) {
      modules.containers.caddy-wg-client = {
        shortName = "caddy";
        username = "caddywg";
        useMacvlan = true;
        credentials = {
          priv-key.name = "wireguard/client";
          psk.name = "wireguard/psk";
        };

        bindMounts.dataDir = {
          hostPath = caddyDataDir;
          mountPoint = "/var/lib/caddy";
          isReadOnly = false;
        };

        config =
          { pkgs, ... }:
          {
            networking.firewall.interfaces.wg0.allowedTCPPorts = with constants.ports; [
              80 # HTTP
              minecraft # Minecraft Java
              crowdsec # CrowdSec LAPI
            ];
            networking.firewall.interfaces.wg0.allowedUDPPorts = with constants.ports; [
              minecraft # Minecraft Bedrock
            ];
            # Adjust MSS to fit the actual path MTU.
            # XXX: Fix for accessing Minecraft services over network bridge from other containers.
            networking.firewall.extraCommands = "iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu";

            # Allow internet access through the WireGuard tunnel for containers connected to this one.
            networking.nat = {
              enable = true;
              internalInterfaces = [ "caddy-+" ];
              externalInterface = "wg0";
            };

            # Set up a WireGuard tunnel to the server.
            networking.wg-quick.interfaces.wg0 = with config.modules.caddy-wg-client.wireguard; {
              address = [
                "${constants.veths.tunnel.client.ip4}/24"
                "${constants.veths.tunnel.client.ip6}/112"
              ];
              privateKeyFile = "$CREDENTIALS_DIRECTORY/priv-key";
              dns = [ dns ]; # Use external DNS, since traffic is routed through the tunnel.
              peers = [
                {
                  publicKey = server.publicKey;
                  presharedKeyFile = "$CREDENTIALS_DIRECTORY/psk";
                  allowedIPs = [
                    "0.0.0.0/0"
                    "::/0"
                  ]; # Route all container traffic through the tunnel.
                  endpoint = "${server.address}:${toString server.port}";
                  persistentKeepalive = 25; # in seconds
                }
              ];
            };
            systemd.services.wg-quick-wg0.serviceConfig.LoadCredential = [
              "priv-key:priv-key"
              "psk:psk"
            ];

            services.caddy =
              with config.modules.caddy-wg-client.wireguard;
              with constants.domain;
              {
                enable = true;
                package = pkgs.caddy.withPlugins {
                  plugins = [ "github.com/mholt/caddy-l4@v0.0.0-20260112235400-e24201789f06" ];
                  hash = "sha256-pXR5u1cRlsXD6CkLbJedBxuM/3OLZSvVQxX1F2HSLTQ=";
                };
                globalConfig =
                  with constants.bridges.mc-caddy.mc;
                  with constants.ports;
                  ''
                    layer4 {
                      tcp/:${toString minecraft} {
                        route {
                          proxy_protocol
                          proxy {
                            proxy_protocol v2
                            upstream tcp/${ip4}:${toString minecraft}
                          }
                        }
                      }
                      udp/:${toString minecraft} {
                        route {
                          proxy_protocol
                          proxy {
                            proxy_protocol v2
                            upstream udp/${ip4}:${toString minecraft}
                          }
                        }
                      }
                    }
                    servers {
                      trusted_proxies static ${constants.veths.tunnel.server.ip4}/24 ${constants.veths.tunnel.server.ip6}/112 ${server.address}
                    }
                  '';
                virtualHosts.":80".extraConfig = ''
                  respond "hello world"
                '';
                virtualHosts.":${toString constants.ports.crowdsec}".extraConfig = ''
                  reverse_proxy ${constants.bridges.csec-caddy.csec.ip4}:${toString constants.ports.crowdsec}
                '';
                virtualHosts."http://${subdomains.auth}.${domain}".extraConfig = ''
                  reverse_proxy ${constants.bridges.auth-caddy.auth.ip4}:${toString constants.ports.authelia}
                '';
                virtualHosts."http://${subdomains.cb}.${domain}".extraConfig = ''
                  reverse_proxy ${constants.bridges.cb-caddy.cb.ip4}:${toString constants.ports.collabora}
                '';
                virtualHosts."http://${subdomains.imm}.${domain}".extraConfig = ''
                  reverse_proxy ${constants.bridges.imm-caddy.imm.ip4}:${toString constants.ports.immich}
                '';
                virtualHosts."http://${subdomains.jf}.${domain}".extraConfig = ''
                  reverse_proxy ${constants.bridges.jf-caddy.jf.ip4}:${toString constants.ports.jellyfin}
                '';
                virtualHosts."http://${subdomains.oc}.${domain}".extraConfig = ''
                  reverse_proxy ${constants.bridges.oc-caddy.oc.ip4}:${toString constants.ports.opencloud}
                '';
                virtualHosts."http://${subdomains.tr}.${domain}".extraConfig = ''
                  reverse_proxy ${constants.bridges.tr-caddy.tr.ip4}:${toString constants.ports.tandoor}
                '';
              };

            system.stateVersion = "24.11";
          };
      };
    };
}
