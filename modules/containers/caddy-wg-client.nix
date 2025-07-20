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
      caddy_data_dir = "/var/lib/containers/caddy";
      caddywg_key_config = {
        owner = "caddywg";
        group = "caddywg";
        restartUnits = [ "container@caddy-wg-client.service" ];
      };
    in
    lib.mkIf (config.modules.caddy-wg-client.enable) {
      users.users.caddywg = {
        uid = constants.uids.caddywg;
        group = "caddywg";
        isSystemUser = true;
      };
      users.groups.caddywg.gid = constants.uids.caddywg;

      sops.secrets."wireguard/client" = caddywg_key_config;
      sops.secrets."wireguard/psk" = caddywg_key_config;

      systemd.services."container@caddy-wg-client" = {
        serviceConfig = with constants.limits.caddy-wg-client; {
          MemoryHigh = "${toString memory}G";
          CPUQuota = "${toString (cpu * 100)}%";
        };
      };

      containers.caddy-wg-client =
        let
          priv_key_file = config.sops.secrets."wireguard/client".path;
          psk_file = config.sops.secrets."wireguard/psk".path;
        in
        {
          privateNetwork = true;
          hostAddress = constants.veths.caddy.host.ip4;
          hostAddress6 = constants.veths.caddy.host.ip6;
          localAddress = constants.veths.caddy.local.ip4;
          localAddress6 = constants.veths.caddy.local.ip6;

          privateUsers = config.users.users.caddywg.uid;
          extraFlags = [ "--private-users-ownership=auto" ];

          autoStart = true;
          ephemeral = true;

          # Make the key files and data dirs accessible to the container.
          # NOTE: Key files should be readable by the "caddywg" user.
          bindMounts = {
            privateKeyFile = {
              hostPath = priv_key_file;
              mountPoint = priv_key_file;
            };
            presharedKeyFile = {
              hostPath = psk_file;
              mountPoint = psk_file;
            };
            dataDir = {
              hostPath = caddy_data_dir;
              mountPoint = "/var/lib/caddy";
              isReadOnly = false;
            };
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
                privateKeyFile = priv_key_file;
                dns = [ dns ]; # Use external DNS, since traffic is routed through the tunnel.
                peers = [
                  {
                    publicKey = server.publicKey;
                    presharedKeyFile = psk_file;
                    allowedIPs = [
                      "0.0.0.0/0"
                      "::/0"
                    ]; # Route all container traffic through the tunnel.
                    endpoint = "${server.address}:${toString server.port}";
                    persistentKeepalive = 25; # in seconds
                  }
                ];
              };

              services.caddy =
                with config.modules.caddy-wg-client.wireguard;
                with constants.domain;
                {
                  enable = true;
                  package = pkgs.caddy.withPlugins {
                    plugins = [ "github.com/mholt/caddy-l4@v0.0.0-20250124234235-87e3e5e2c7f9" ];
                    hash = "sha256-GDTZEHtfY3jVt4//6714BiFzBbXS3V+Gi0yDAA/T7hg=";
                  };
                  globalConfig =
                    with constants.bridges.caddy-mc.mc;
                    with constants.ports;
                    ''
                      layer4 {
                        tcp/:${toString minecraft} {
                          route {
                            proxy ${ip4}:${toString minecraft}
                          }
                        }
                        udp/:${toString minecraft} {
                          route {
                            proxy udp/${ip4}:${toString minecraft}
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
                    reverse_proxy ${constants.bridges.caddy-csec.csec.ip4}:${toString constants.ports.crowdsec}
                  '';
                  virtualHosts."http://${subdomains.auth}.${domain}".extraConfig = ''
                    reverse_proxy ${constants.bridges.auth-caddy.auth.ip4}:${toString constants.ports.authelia}
                  '';
                };

              system.stateVersion = "24.11";
            };
        };
    };
}
