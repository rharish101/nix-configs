# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.caddy-wg-client = {
    enable = lib.mkEnableOption "Enable Caddy reverse proxy with a WireGuard client";
    wireguard = {
      address = lib.mkOption {
        description = "IP address for the client";
        type = lib.types.str;
        default = "10.100.0.2/24";
      };
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
      cpu_limit = 1;
      memory_limit = 1; # in GiB
      caddy_data_dir = "/var/lib/containers/caddy";
      priv_uid_gid = 65536 * 10; # Randomly-chosen UID/GID a/c to how systemd-nspawn chooses one for the user namespacing.
      mc_container_addr = "10.2.0.2";
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
        hostAddress = "10.1.0.1";
        localAddress = "10.1.0.2";
        localAddress6 = "fc00::1/112";

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
              internalInterfaces = [ "br-+" ];
              externalInterface = "wg0";
            };

            # Set up a WireGuard tunnel to the server.
            networking.wg-quick.interfaces.wg0 = with config.modules.caddy-wg-client.wireguard; {
              address = [ address ];
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

            services.caddy = {
              enable = true;
              package = pkgs.caddy.withPlugins {
                plugins = [ "github.com/mholt/caddy-l4@v0.0.0-20250124234235-87e3e5e2c7f9" ];
                hash = "sha256-HgB/xiMsROogUgVvy0Zvvc0GsKZWZ/ROdt9L+ubUcnw=";
              };
              globalConfig = ''
                layer4 {
                  :25565 {
                    route {
                      proxy ${mc_container_addr}:25565
                    }
                  }
                }
              '';
              virtualHosts.":80".extraConfig = ''
                respond "hello world"
              '';
            };

            system.stateVersion = "24.11";
          };
      };
    };
}
