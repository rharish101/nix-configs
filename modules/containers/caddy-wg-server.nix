# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.caddy-wg-server = {
    enable = lib.mkEnableOption "WireGuard server with public Caddy reverse proxy";
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
    crowdsec.enable = lib.mkEnableOption "CrowdSec Caddy log processor";
  };

  config =
    let
      constants = import ../constants.nix lib;
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

        dirMounts.dataDir = {
          hostPath = "/var/lib/containers/caddy";
          mountPoint = "/var/lib/caddy";
          isReadOnly = false;
        };

        config =
          let
            globalConfig = config;
          in
          { config, pkgs, ... }:
          {
            networking.firewall.interfaces.eth0.allowedTCPPorts = with constants.ports; [
              443 # HTTPS
              minecraft # Minecraft Java
              crowdsec # CrowdSec LAPI
            ];
            networking.firewall.interfaces.eth0.allowedUDPPorts = with constants.ports; [
              443 # QUIC
              minecraft # Minecraft Bedrock
              wireguard # WireGuard tunnel
            ];

            networking.nameservers = constants.nameservers;

            # Allow internet access for clients through the WireGuard tunnel.
            # NAT translates internal client IPs to the server's public IP for external replies
            networking.nat = {
              enable = true;
              internalInterfaces = [ "wg0" ];
              externalInterface = "eth0";
            };

            networking.wg-quick.interfaces.wg0 = with globalConfig.modules.caddy-wg-server.wireguard; {
              address = [ "${constants.veths.tunnel.server.ip4}/24" ];
              listenPort = constants.ports.wireguard;
              privateKeyFile = "$CREDENTIALS_DIRECTORY/priv-key";
              peers = [
                {
                  publicKey = client.publicKey;
                  presharedKeyFile = "$CREDENTIALS_DIRECTORY/psk";
                  allowedIPs = [ "${constants.veths.tunnel.client.ip4}/24" ];
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
                    "github.com/caddy-dns/cloudflare@v0.2.4"
                    "github.com/mholt/caddy-l4@v0.1.2"
                    "github.com/mholt/caddy-ratelimit@v0.1.1-0.20260612195517-5625512f24f6"
                    "github.com/WeidiDeng/caddy-cloudflare-ip@v0.0.0-20231130002422-f53b62aa13cb"
                  ];
                  hash = "sha256-7iYV/ZCc7M2Ym3rz3STl4TE5cCvIlOPOCV5S8pZy2eE=";
                };
                environmentFile = "/run/credentials/@system/caddy-env";
                email = "harish.rajagopals@gmail.com";
                globalConfig =
                  # Caddyfile snippets don't work in the layer4 global config.
                  let
                    mcPort = toString constants.ports.minecraft;
                    mcProxyConfig = proto: ''
                      ${proto}/:${mcPort} {
                        route {
                          proxy {
                            proxy_protocol v2
                            upstream ${proto}/${clientIp}:${mcPort}
                          }
                        }
                      }
                    '';
                  in
                  ''
                    # Configure DNS provider for getting TLS certs from LetsEncrypt through ACME.
                    dns cloudflare {
                      zone_token {env.ZONE_TOKEN}
                      api_token {env.DNS_TOKEN}
                    }
                    # Enable ECH for the main domain (as it's the only one I control directly with the
                    # DNS provider)
                    ech ${constants.domain.domain}
                    # Reverse proxy for Minecraft with proxy protocol v2 for logging source IPs
                    # (used by CrowdSec for blocking bad actors)
                    layer4 {
                      ${mcProxyConfig "tcp"}
                      ${mcProxyConfig "udp"}
                    }
                    # Trust Cloudflare, so that we use the source IPs it reports (used by CrowdSec for
                    # blocking bad actors)
                    servers {
                      trusted_proxies cloudflare {
                        timeout 10s
                      }
                      trusted_proxies_strict
                    }
                  '';
                extraConfig = ''
                  (rate-limit) {
                    # NOTE: Make sure that this isn't too low.
                    # For reference, one load of the Jellyfin homepage takes ~180 requests (as of
                    # 2026-02-25).
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
                  }
                  (reverse-proxy) {
                    import rate-limit
                    reverse_proxy ${clientIp}:{args[0]} {
                      transport http {
                        proxy_protocol v2
                      }
                    }
                  }
                '';
                virtualHosts =
                  with constants.domain;
                  let
                    sanitize = name: builtins.replaceStrings [ "/" " " ] [ "_" "_" ] name;
                    logFile = name: "${config.services.caddy.logDir}/access-${sanitize name}.log";
                    addLogFormat =
                      name: value:
                      {
                        logFormat = ''
                          output file ${logFile name} {
                            mode 640
                          }
                        '';
                      }
                      // value;
                  in
                  builtins.mapAttrs addLogFormat (
                    {
                      ":${toString constants.ports.crowdsec}".extraConfig = ''
                        import reverse-proxy ${toString constants.ports.crowdsec}
                      '';
                      ${domain}.extraConfig = ''
                        import reverse-proxy 80
                      '';
                      "www.${domain}".extraConfig = ''
                        import rate-limit
                        redir {scheme}://${domain}{uri} permanent
                      '';
                    }
                    // lib.mapAttrs' (_: subdomain: {
                      name = "${subdomain}.${domain}";
                      value.extraConfig = ''
                        import reverse-proxy 80
                      '';
                    }) subdomains
                  );
              };

            services.crowdsec = lib.mkIf globalConfig.modules.caddy-wg-server.crowdsec.enable {
              enable = true;
              autoUpdateService = true;
              name = "${globalConfig.networking.hostName}-caddy";

              localConfig.acquisitions = [
                {
                  source = "journalctl";
                  journalctl_filter = [ "_SYSTEMD_UNIT=caddy.service" ];
                  labels.type = "syslog";
                  use_time_machine = true;
                }
                {
                  source = "file";
                  filenames = [ "/var/log/caddy/*.log" ];
                  labels.type = "caddy";
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
            users.users.crowdsec.extraGroups = [ "caddy" ];

            system.stateVersion = "25.05";
          };
      };
    };
}
