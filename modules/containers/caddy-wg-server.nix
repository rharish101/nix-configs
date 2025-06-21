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
      privateKeyFile = lib.mkOption {
        description = "The file for the server's private key";
        type = lib.types.str;
      };
      client = {
        publicKey = lib.mkOption {
          description = "The public key for the client";
          type = lib.types.str;
        };
        presharedKeyFile = lib.mkOption {
          description = "The file for the preshared key with the clients";
          type = lib.types.str;
        };
        address = lib.mkOption {
          description = "The Wireguard IP address of the client";
          type = lib.types.str;
          default = "10.100.0.2";
        };
      };
    };
    caddy = {
      minecraftPort = lib.mkOption {
        description = "The port on the host that to be used for Minecraft";
        type = lib.types.int;
        default = 25565;
      };
      environmentFile = lib.mkOption {
        description = "The file containing the environment variables for Caddy";
        type = with lib.types; nullOr str;
      };
    };
  };

  config =
    let
      cpu_limit = 1;
      memory_limit = 1; # in GiB
      caddy_data_dir = "/var/lib/containers/caddy";
      priv_uid_gid = 65536 * 10; # Randomly-chosen UID/GID a/c to how systemd-nspawn chooses one for the user namespacing.
    in
    lib.mkIf config.modules.caddy-wg-server.enable {
      users.users.caddywg = {
        uid = priv_uid_gid;
        group = "caddywg";
        isSystemUser = true;
      };
      users.groups.caddywg.gid = priv_uid_gid;

      systemd.services."container@caddy-wg-server" = {
        serviceConfig = {
          MemoryHigh = "${toString memory_limit}G";
          CPUQuota = "${toString (cpu_limit * 100)}%";
        };
      };

      containers.caddy-wg-server = {
        privateNetwork = true;
        hostAddress = "10.1.0.1";
        localAddress = "10.1.0.2";
        forwardPorts = with config.modules.caddy-wg-server; [
          {
            containerPort = 51820;
            hostPort = wireguard.port;
            protocol = "udp";
          }
          { hostPort = 443; }
          {
            hostPort = caddy.minecraftPort;
            containerPort = 25565;
            protocol = "tcp";
          }
          {
            hostPort = caddy.minecraftPort;
            containerPort = 25565;
            protocol = "udp";
          }
        ];

        privateUsers = config.users.users.caddywg.uid;
        extraFlags = [ "--private-users-ownership=auto" ];

        ephemeral = true;
        autoStart = true;

        # Make the key files and data dirs accessible to the container.
        # NOTE: Key files should be readable by the "caddywg" user.
        bindMounts = with config.modules.caddy-wg-server; {
          privateKeyFile = {
            hostPath = wireguard.privateKeyFile;
            mountPoint = wireguard.privateKeyFile;
          };
          presharedKeyFile = {
            hostPath = wireguard.client.presharedKeyFile;
            mountPoint = wireguard.client.presharedKeyFile;
          };
          environmentFile = {
            hostPath = caddy.environmentFile;
            mountPoint = caddy.environmentFile;
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
            networking.firewall.allowedTCPPorts = [
              443 # HTTPS
              25565 # Minecraft Java
            ];
            networking.firewall.allowedUDPPorts = [
              25565 # Minecraft Bedrock
              51820 # WireGuard
            ];

            # Allow internet access for clients through the WireGuard tunnel.
            networking.nat = {
              enable = true;
              internalInterfaces = [ "wg0" ];
              externalInterface = "eth0";
            };

            networking.wg-quick.interfaces.wg0 = with config.modules.caddy-wg-server.wireguard; {
              address = [ "10.100.0.1/24" ];
              listenPort = 51820;
              privateKeyFile = privateKeyFile;
              peers = [
                {
                  publicKey = client.publicKey;
                  presharedKeyFile = client.presharedKeyFile;
                  allowedIPs = [ "${client.address}/24" ];
                }
              ];
            };

            services.caddy =
              let
                client_ip = config.modules.caddy-wg-server.wireguard.client.address;
                reverse_proxy_config = "reverse_proxy ${client_ip}:80";
              in
              {
                enable = true;
                package = pkgs.caddy.withPlugins {
                  plugins = [
                    "github.com/caddy-dns/cloudflare@v0.2.1"
                    "github.com/mholt/caddy-l4@v0.0.0-20250124234235-87e3e5e2c7f9"
                  ];
                  hash = "sha256-PfCTGGH1be7TI95wvS95K4BoK3myc0TrRcaaN6ejfkI=";
                };
                environmentFile = config.modules.caddy-wg-server.caddy.environmentFile;
                email = "harish.rajagopals@gmail.com";
                globalConfig = ''
                  acme_dns cloudflare {
                    zone_token {env.ZONE_TOKEN}
                    api_token {env.DNS_TOKEN}
                  }
                  layer4 {
                    0.0.0.0:25565 {
                      route {
                        proxy ${client_ip}:25565
                      }
                    }
                  }
                '';
                virtualHosts."rharish.dev".extraConfig = reverse_proxy_config;
                virtualHosts."www.rharish.dev".extraConfig = "redir https://rharish.dev 301";
              };

            system.stateVersion = "25.05";
          };
      };
    };
}
