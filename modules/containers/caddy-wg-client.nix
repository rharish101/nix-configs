# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.caddy-wg-client = {
    enable = lib.mkEnableOption "Enable Caddy reverse proxy with a WireGuard client";
    wireguard = {
      privateKeyFile = lib.mkOption {
        description = "The file for the client's private key";
        type = lib.types.str;
      };
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
        presharedKeyFile = lib.mkOption {
          description = "The file for the preshared key with the server";
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
      cpu_limit = 1;
      memory_limit = 1; # in GiB
      caddy_data_dir = "/var/lib/containers/caddy";
      priv_uid_gid = 65536 * 10; # Randomly-chosen UID/GID a/c to how systemd-nspawn chooses one for the user namespacing.
      csec_port = 20546;
    in
    lib.mkIf (config.modules.caddy-wg-client.enable) {
      users.users.caddywg = {
        uid = priv_uid_gid;
        group = "caddywg";
        isSystemUser = true;
      };
      users.groups.caddywg.gid = priv_uid_gid;

      systemd.services."container@caddy-wg-client" = {
        serviceConfig = {
          MemoryHigh = "${toString memory_limit}G";
          CPUQuota = "${toString (cpu_limit * 100)}%";
        };
      };

      containers.caddy-wg-client = {
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
        bindMounts = with config.modules.caddy-wg-client; {
          privateKeyFile = {
            hostPath = wireguard.privateKeyFile;
            mountPoint = wireguard.privateKeyFile;
          };
          presharedKeyFile = {
            hostPath = wireguard.server.presharedKeyFile;
            mountPoint = wireguard.server.presharedKeyFile;
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
            networking.firewall.interfaces.wg0.allowedTCPPorts = [
              80 # HTTP
              25565 # Minecraft Java
              csec_port # CrowdSec LAPI
            ];
            networking.firewall.interfaces.wg0.allowedUDPPorts = [
              25565 # Minecraft Bedrock
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
              privateKeyFile = privateKeyFile;
              dns = [ dns ]; # Use external DNS, since traffic is routed through the tunnel.
              peers = [
                {
                  publicKey = server.publicKey;
                  presharedKeyFile = server.presharedKeyFile;
                  allowedIPs = [
                    "0.0.0.0/0"
                    "::/0"
                  ]; # Route all container traffic through the tunnel.
                  endpoint = "${server.address}:${toString server.port}";
                  persistentKeepalive = 25; # in seconds
                }
              ];
            };

            services.caddy = with config.modules.caddy-wg-client.wireguard; {
              enable = true;
              package = pkgs.caddy.withPlugins {
                plugins = [ "github.com/mholt/caddy-l4@v0.0.0-20250124234235-87e3e5e2c7f9" ];
                hash = "sha256-GDTZEHtfY3jVt4//6714BiFzBbXS3V+Gi0yDAA/T7hg=";
              };
              globalConfig = with constants.bridges.caddy-mc.mc; ''
                layer4 {
                  tcp/:25565 {
                    route {
                      proxy ${ip4}:25565
                    }
                  }
                  udp/:25565 {
                    route {
                      proxy udp/${ip4}:19132
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
              virtualHosts.":${toString csec_port}".extraConfig = ''
                reverse_proxy ${constants.bridges.caddy-csec.csec.ip4}:8080
              '';
              virtualHosts."http://auth.rharish.dev".extraConfig = ''
                reverse_proxy ${constants.bridges.auth-caddy.auth.ip4}:9091
              '';
            };

            system.stateVersion = "24.11";
          };
      };
    };
}
