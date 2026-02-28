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
  options.modules.bentopdf.enable = lib.mkEnableOption "Enable BentoPDF";

  config =
    let
      constants = import ../constants.nix;
      caddyDataDir = "/var/lib/containers/caddy";
    in
    lib.mkIf config.modules.caddy-wg-client.enable {
      modules.containers.caddy-wg-client = {
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
            networking.firewall.filterForward = true;
            networking.firewall.extraForwardRules = "tcp flags syn tcp option maxseg size set rt mtu";

            # Allow internet access through the WireGuard tunnel for containers connected to this one.
            networking.nat = {
              enable = true;
              internalInterfaces = [ "eth0" ];
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
                  plugins = [ "github.com/mholt/caddy-l4@v0.0.0-20260216070754-eca560d759c9" ];
                  hash = "sha256-f5t6fhKijbY82G7RdqExtoCjkq56AALmCxKlRFXkGg8=";
                };
                globalConfig =
                  let
                    mcAddr = constants.bridge.minecraft.ip4;
                    mcPort = constants.ports.minecraft;
                  in
                  ''
                    layer4 {
                      tcp/:${toString mcPort} {
                        route {
                          proxy_protocol
                          proxy {
                            proxy_protocol v2
                            upstream tcp/${mcAddr}:${toString mcPort}
                          }
                        }
                      }
                      udp/:${toString mcPort} {
                        route {
                          proxy_protocol
                          proxy {
                            proxy_protocol v2
                            upstream udp/${mcAddr}:${toString mcPort}
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
                  reverse_proxy ${constants.bridge.crowdsec-lapi.ip4}:${toString constants.ports.crowdsec}
                '';
                virtualHosts."http://${subdomains.authelia}.${domain}".extraConfig = ''
                  reverse_proxy ${constants.bridge.authelia.ip4}:${toString constants.ports.authelia}
                '';
                virtualHosts."http://${subdomains.collabora}.${domain}".extraConfig = ''
                  reverse_proxy ${constants.bridge.collabora.ip4}:${toString constants.ports.collabora}
                '';
                virtualHosts."http://${subdomains.immich}.${domain}".extraConfig = ''
                  reverse_proxy ${constants.bridge.immich.ip4}:${toString constants.ports.immich}
                '';
                virtualHosts."http://${subdomains.jellyfin}.${domain}".extraConfig = ''
                  reverse_proxy ${constants.bridge.jellyfin.ip4}:${toString constants.ports.jellyfin}
                '';
                virtualHosts."http://${subdomains.opencloud}.${domain}".extraConfig = ''
                  reverse_proxy ${constants.bridge.opencloud.ip4}:${toString constants.ports.opencloud}
                '';
                virtualHosts."http://${subdomains.tandoor}.${domain}".extraConfig = ''
                  reverse_proxy ${constants.bridge.tandoor.ip4}:${toString constants.ports.tandoor}
                '';
                virtualHosts."http://${subdomains.vaultwarden}.${domain}".extraConfig = ''
                  reverse_proxy ${constants.bridge.vaultwarden.ip4}:${toString constants.ports.vaultwarden}
                '';
              };

            services.bentopdf = lib.mkIf config.modules.bentopdf.enable {
              enable = true;
              domain = with constants.domain; "http://${subdomains.bentopdf}.${domain}";
              caddy = {
                enable = true;
                virtualHost.extraConfig = with constants; ''
                  forward_auth ${bridge.authelia.ip4}:${toString ports.authelia} {
                    uri /api/authz/forward-auth
                    copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
                  }
                '';
              };
            };

            system.stateVersion = "24.11";
          };
      };
    };
}
