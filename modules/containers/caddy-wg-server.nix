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
      secretsConfig = {
        owner = "caddywg";
        group = "caddywg";
        restartUnits = [ "container@caddy-wg-server.service" ];
      };
    in
    lib.mkIf config.modules.caddy-wg-server.enable {
      users.users.caddywg = {
        uid = constants.uids.caddywg;
        group = "caddywg";
        isSystemUser = true;
      };
      users.groups.caddywg.gid = constants.uids.caddywg;

      sops.secrets."cloudflare" = secretsConfig;
      sops.secrets."wireguard/psk" = secretsConfig;
      sops.secrets."wireguard/server" = secretsConfig;
      sops.secrets."crowdsec/caddy-creds" = secretsConfig;

      systemd.services."container@caddy-wg-server" = {
        serviceConfig = with constants.limits.caddy-wg-server; {
          MemoryHigh = "${toString memory}G";
          CPUQuota = "${toString (cpu * 100)}%";
        };
      };

      containers.caddy-wg-server =
        let
          privKeyFile = config.sops.secrets."wireguard/server".path;
          pskFile = config.sops.secrets."wireguard/psk".path;
          caddyEnvFile = config.sops.secrets."cloudflare".path;
          csecCreds = config.sops.secrets."crowdsec/caddy-creds".path;
        in
        {
          privateNetwork = true;
          hostAddress = constants.veths.caddy.host.ip4;
          hostAddress6 = constants.veths.caddy.host.ip6;
          localAddress = constants.veths.caddy.local.ip4;
          localAddress6 = constants.veths.caddy.local.ip6;

          forwardPorts = with config.modules.caddy-wg-server; [
            {
              containerPort = constants.ports.wireguard;
              hostPort = wireguard.port;
              protocol = "udp";
            }
            { hostPort = 443; }
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

          privateUsers = config.users.users.caddywg.uid;
          extraFlags = [ "--private-users-ownership=auto" ];

          ephemeral = true;
          autoStart = true;

          # Make the key files and data dirs accessible to the container.
          # NOTE: Key files should be readable by the "caddywg" user.
          bindMounts = {
            privateKeyFile = {
              hostPath = privKeyFile;
              mountPoint = privKeyFile;
            };
            presharedKeyFile = {
              hostPath = pskFile;
              mountPoint = pskFile;
            };
            environmentFile = {
              hostPath = caddyEnvFile;
              mountPoint = caddyEnvFile;
            };
            dataDir = {
              hostPath = caddyDataDir;
              mountPoint = "/var/lib/caddy";
              isReadOnly = false;
            };
            crowdsec = {
              hostPath = csecCreds;
              mountPoint = csecCreds;
            };
          };

          config =
            { pkgs, ... }:
            {
              imports = [ ../vendored/crowdsec.nix ];

              networking.firewall.allowedTCPPorts = with constants.ports; [
                443 # HTTPS
                minecraft # Minecraft Java
                crowdsec # CrowdSec LAPI
              ];
              networking.firewall.allowedUDPPorts = with constants.ports; [
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
                privateKeyFile = privKeyFile;
                peers = [
                  {
                    publicKey = client.publicKey;
                    presharedKeyFile = pskFile;
                    allowedIPs = [
                      "${constants.veths.tunnel.client.ip4}/24"
                      "${constants.veths.tunnel.client.ip6}/112"
                    ];
                  }
                ];
              };

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
                      "github.com/caddy-dns/cloudflare@v0.2.1"
                      "github.com/mholt/caddy-l4@v0.0.0-20250124234235-87e3e5e2c7f9"
                    ];
                    hash = "sha256-kADjiFy2v0wF4o4X8EACNSW0M4+13LNJYDpHynBPVz8=";
                  };
                  environmentFile = caddyEnvFile;
                  email = "harish.rajagopals@gmail.com";
                  globalConfig = with constants.ports; ''
                    acme_dns cloudflare {
                      zone_token {env.ZONE_TOKEN}
                      api_token {env.DNS_TOKEN}
                    }
                    layer4 {
                      tcp/:${toString minecraft} {
                        route {
                          proxy ${clientIp}:${toString minecraft}
                        }
                      }
                      udp/:${toString minecraft} {
                        route {
                          proxy udp/${clientIp}:${toString minecraft}
                        }
                      }
                    }
                  '';
                  virtualHosts.":${toString constants.ports.crowdsec}".extraConfig =
                    "reverse_proxy ${clientIp}:${toString constants.ports.crowdsec}";
                  virtualHosts."${domain}".extraConfig = proxyConfig;
                  virtualHosts."www.${domain}".extraConfig = "redir https://${domain} 301";
                  virtualHosts."${subdomains.auth}.${domain}".extraConfig = proxyConfig;
                };

              services.crowdsec = lib.mkIf config.modules.caddy-wg-server.crowdsec.enable {
                enable = true;
                autoUpdateService = true;
                name = "${config.networking.hostName}-caddy";

                user = "root";
                group = "root";

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
                settings.lapi.credentialsFile = csecCreds;
              };

              system.stateVersion = "25.05";
            };
        };
    };
}
