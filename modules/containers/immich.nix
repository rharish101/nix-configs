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
      secretsConfig.restartUnits = [ "container@immich.service" ];
      gpuDevice = "/dev/dri/renderD128";
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

        sops.secrets."immich/env" = secretsConfig;
        sops.secrets."immich/oidc" = secretsConfig;
        sops.secrets."immich/redis".restartUnits = [ "container@immich-redis.service" ];

        # Immich doesn't have a way to pass the OIDC client secret as an env var or path, so create
        # a config manually and add it as a placeholder.
        sops.templates."immich.json" = secretsConfig // {
          content =
            with constants.domain;
            builtins.toJSON {
              server.externalDomain = "https://${subdomains.imm}.${domain}";
              passwordLogin.enabled = false;
              ffmpeg = {
                accel = "qsv";
                accelDecode = true;
                acceptedVideoCodecs = [
                  "h264"
                  "hevc"
                  "vp9"
                  "av1"
                ];
              };
              oauth = {
                enabled = true;
                issuerUrl = "https://${subdomains.auth}.${domain}/.well-known/openid-configuration";
                clientId = "JuhCQHaHI65vm~.Oyw7F~X9nFiJpC1UsyxMzthVhDHwzjfcJhofhxV43Ezcs31Er";
                clientSecret = config.sops.placeholder."immich/oidc";
                buttonText = "Login with Authelia";
                autoRegister = false;
              };
              backup.database.enabled = false;
            };
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
            "--load-credential=config:${config.sops.templates."immich.json".path}"
          ];

          bindMounts = with config.modules.immich; {
            dataDir = {
              hostPath = dataDir;
              mountPoint = "/var/lib/immich";
              isReadOnly = false;
            };
            render.mountPoint = "/dev/dri";
            usb.mountPoint = "/dev/bus/usb";
          };

          allowedDevices = [
            {
              node = gpuDevice;
              modifier = "rw";
            }
          ];

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

              hardware.graphics = {
                enable = true;
                extraPackages = with pkgs; [
                  intel-media-driver
                  vpl-gpu-rt
                ];
              };

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
                accelerationDevices = [ gpuDevice ];
                # XXX: Workaround for: https://github.com/NixOS/nixpkgs/issues/418799
                machine-learning.environment =
                  let
                    cacheDir = "/var/cache/immich";
                  in
                  {
                    MPLCONFIGDIR = cacheDir;
                    HF_XET_CACHE = "${cacheDir}/huggingface-xet";
                  };
              };
              systemd.services.immich-server = {
                serviceConfig.LoadCredential = [ "config:config" ];
                environment.IMMICH_CONFIG_FILE = "%d/config";
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
