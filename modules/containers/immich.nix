# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.modules.immich = {
    enable = lib.mkEnableOption "Enable Immich";
    dataDir = lib.mkOption {
      description = "The Immich directory path";
      type = lib.types.str;
    };
  };
  config =
    let
      constants = import ../constants.nix;
    in
    lib.mkIf
      (
        config.modules.immich.enable
        && config.modules.caddy-wg-client.enable
        && config.modules.postgres.enable
      )
      {
        # User for the Immich container.
        users.users.immich = {
          uid = constants.uids.immich;
          group = "immich";
          isSystemUser = true;
        };
        users.groups.immich.gid = constants.uids.immich;

        sops.secrets."immich/env".restartUnits = [ "container@immich.service" ];
        sops.secrets."immich/redis" = {
          owner = "immich";
          group = "immich";
          restartUnits = [
            "container@immich.service"
            "container@immich-redis.service"
          ];
        };

        systemd.services."container@immich" = with constants.limits.immich; {
          serviceConfig = {
            MemoryHigh = "${toString memory}G";
            CPUQuota = "${toString (cpu * 100)}%";
          };
          requires = [
            "container@postgres.service"
            "container@immich-redis.service"
          ];
        };

        networking.bridges = with constants.bridges; {
          ${caddy-imm.name}.interfaces = [ ];
          ${imm-pg.name}.interfaces = [ ];
          ${imm-redis.name}.interfaces = [ ];
        };

        containers.caddy-wg-client.extraVeths.${constants.bridges.caddy-imm.caddy.interface} =
          with constants.bridges.caddy-imm; {
            hostBridge = name;
            localAddress = "${caddy.ip4}/24";
            localAddress6 = "${caddy.ip6}/112";
          };
        containers.postgres.extraVeths.${constants.bridges.imm-pg.pg.interface} =
          with constants.bridges.imm-pg; {
            hostBridge = name;
            localAddress = "${pg.ip4}/24";
            localAddress6 = "${pg.ip6}/112";
          };

        containers.immich = {
          privateNetwork = true;
          hostBridge = constants.bridges.caddy-imm.name;
          localAddress = "${constants.bridges.caddy-imm.imm.ip4}/24";
          localAddress6 = "${constants.bridges.caddy-imm.imm.ip6}/112";

          extraVeths = with constants.bridges; {
            "${imm-pg.imm.interface}" = with imm-pg; {
              hostBridge = name;
              localAddress = "${imm.ip4}/24";
              localAddress6 = "${imm.ip6}/112";
            };
            "${imm-redis.imm.interface}" = with imm-redis; {
              hostBridge = name;
              localAddress = "${imm.ip4}/24";
              localAddress6 = "${imm.ip6}/112";
            };
          };

          privateUsers = config.users.users.immich.uid;
          autoStart = true;
          extraFlags = [
            "--private-users-ownership=auto"
            "--volatile=overlay"
            "--link-journal=host"
            "--load-credential=env:${config.sops.secrets."immich/env".path}"
          ];

          bindMounts = with config.modules.immich; {
            dataDir = {
              hostPath = dataDir;
              mountPoint = "/var/lib/immich";
              isReadOnly = false;
            };
          };

          config =
            { ... }:
            {
              # To allow this container to access the internet through the bridge.
              networking.defaultGateway = {
                address = constants.bridges.caddy-imm.caddy.ip4;
                interface = "eth0";
              };
              networking.defaultGateway6 = {
                address = constants.bridges.caddy-imm.caddy.ip6;
                interface = "eth0";
              };
              networking.nameservers = [ "1.1.1.1" ];

              services.immich = {
                enable = true;
                host = "0.0.0.0";
                port = constants.ports.immich;
                openFirewall = true;
                secretsFile = "/run/credentials/@system/env";
                database = {
                  enable = false;
                  host = constants.bridges.imm-pg.pg.ip4;
                  port = constants.ports.postgres;
                };
                redis = {
                  enable = false;
                  host = constants.bridges.imm-redis.redis.ip4;
                  port = 6379;
                };
                settings = {
                  server.externalDomain = "https://${constants.domain.subdomains.imm}.${constants.domain.domain}";
                  backup.database.enabled = false;
                };
                machine-learning.enable = false;
              };

              system.stateVersion = "25.05";
            };
        };

        containers.immich-redis = {
          privateNetwork = true;
          hostBridge = constants.bridges.imm-redis.name;
          localAddress = "${constants.bridges.imm-redis.redis.ip4}/24";
          localAddress6 = "${constants.bridges.imm-redis.redis.ip6}/112";

          privateUsers = "pick";
          autoStart = true;
          extraFlags = [
            "--private-users-ownership=auto"
            "--volatile=overlay"
            "--link-journal=host"
            "--load-credential=pass:${config.sops.secrets."immich/redis".path}"
          ];

          config =
            { ... }:
            {
              services.redis.package = pkgs.valkey;
              services.redis.servers."" = {
                enable = true;
                bind = null;
                openFirewall = true;
                requirePassFile = "/run/redis/passfile";
                save = [ ];
              };
              systemd.services.redis.serviceConfig = {
                # `requirePassFile` needs an absolute path, so copy the credential to a directory that the setup script can access.
                ExecStartPre = lib.mkBefore [
                  "${lib.getExe' pkgs.coreutils-full "install"} -m600 \${CREDENTIALS_DIRECTORY}/pass /run/redis/passfile"
                ];
                LoadCredential = [ "pass:pass" ];
              };

              system.stateVersion = "25.05";
            };
        };
      };
}
