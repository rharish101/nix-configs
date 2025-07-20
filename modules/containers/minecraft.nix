# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{
  config,
  inputs,
  lib,
  ...
}:
{
  options.modules.minecraft = {
    enable = lib.mkEnableOption "Enable Minecraft servers";
    dataDir = lib.mkOption {
      description = "The Minecraft directory path";
      type = lib.types.str;
    };
  };
  config =
    let
      constants = import ../constants.nix;
      cpu_limit = 6;
      memory_limit = 12; # in GiB
      server_name = "EBG6 Minecraft server";
      mc_key_config = {
        owner = "minecraft";
        group = "minecraft";
        restartUnits = [ "container@minecraft.service" ];
      };
    in
    lib.mkIf (config.modules.minecraft.enable && config.modules.caddy-wg-client.enable) {
      # User for the Minecraft server.
      users.users.minecraft = {
        uid = constants.uids.minecraft;
        group = "minecraft";
        isSystemUser = true;
      };
      users.groups.minecraft.gid = constants.uids.minecraft;

      # Secrets for the server config
      sops.secrets."minecraft/whitelist" = mc_key_config;
      sops.secrets."minecraft/ops" = mc_key_config;

      systemd.services."container@minecraft" = {
        serviceConfig = {
          MemoryHigh = "${toString memory_limit}G";
          CPUQuota = "${toString (cpu_limit * 100)}%";
        };
        requires = [ "container@caddy-wg-client.service" ];
      };

      networking.bridges."${constants.bridges.caddy-mc.name}".interfaces = [ ];
      containers.caddy-wg-client.extraVeths."${constants.bridges.caddy-mc.caddy.interface}" =
        with constants.bridges.caddy-mc; {
          hostBridge = name;
          localAddress = "${caddy.ip4}/24";
          localAddress6 = "${caddy.ip6}/112";
        };

      containers.minecraft = {
        privateNetwork = true;
        hostBridge = constants.bridges.caddy-mc.name;
        localAddress = "${constants.bridges.caddy-mc.mc.ip4}/24";
        localAddress6 = "${constants.bridges.caddy-mc.mc.ip6}/112";

        privateUsers = config.users.users.minecraft.uid;
        extraFlags = [ "--private-users-ownership=auto" ];

        autoStart = true;
        ephemeral = true;

        bindMounts = with config.modules.minecraft; {
          dataDir = {
            hostPath = dataDir;
            mountPoint = "/srv/minecraft";
            isReadOnly = false;
          };
          whitelist = {
            hostPath = config.sops.secrets."minecraft/whitelist".path;
            mountPoint = config.sops.secrets."minecraft/whitelist".path;
          };
          ops = {
            hostPath = config.sops.secrets."minecraft/ops".path;
            mountPoint = config.sops.secrets."minecraft/ops".path;
          };
        };

        config =
          { pkgs, ... }:
          {
            imports = [ inputs.nix-minecraft.nixosModules.minecraft-servers ];
            nixpkgs.overlays = [ inputs.nix-minecraft.overlay ];
            nixpkgs.config.allowUnfreePredicate =
              pkg:
              builtins.elem (lib.getName pkg) [
                "minecraft-server"
              ];

            networking.firewall.allowedTCPPorts = [ constants.ports.minecraft ];
            networking.firewall.allowedUDPPorts = [ constants.ports.minecraft ];

            # To allow this container to access the internet through the bridge.
            networking.defaultGateway = {
              address = constants.bridges.caddy-mc.caddy.ip4;
              interface = "eth0";
            };
            networking.defaultGateway6 = {
              address = constants.bridges.caddy-mc.caddy.ip6;
              interface = "eth0";
            };
            networking.nameservers = [ "1.1.1.1" ];

            services.minecraft-servers = {
              enable = true;
              eula = true;

              # Use the root user of the container, i.e. the "minecraft" user.
              # This is needed to read the secrets files.
              user = "root";
              group = "root";

              servers.original = {
                enable = true;
                package = pkgs.minecraftServers.paper-1_21_7-build_17;
                # Aikar's flags.
                jvmOpts = ''
                  -Xms${toString memory_limit}G \
                  -Xmx${toString memory_limit}G \
                  -XX:+UseG1GC \
                  -XX:+ParallelRefProcEnabled \
                  -XX:MaxGCPauseMillis=200 \
                  -XX:+UnlockExperimentalVMOptions \
                  -XX:+DisableExplicitGC \
                  -XX:+AlwaysPreTouch \
                  -XX:G1NewSizePercent=30 \
                  -XX:G1MaxNewSizePercent=40 \
                  -XX:G1HeapRegionSize=8M \
                  -XX:G1ReservePercent=20 \
                  -XX:G1HeapWastePercent=5 \
                  -XX:G1MixedGCCountTarget=4 \
                  -XX:InitiatingHeapOccupancyPercent=15 \
                  -XX:G1MixedGCLiveThresholdPercent=90 \
                  -XX:G1RSetUpdatingPauseTimePercent=5 \
                  -XX:SurvivorRatio=32 \
                  -XX:+PerfDisableSharedMem \
                  -XX:MaxTenuringThreshold=1 \
                  -Dusing.aikars.flags=https://mcflags.emc.gs \
                  -Daikars.new.flags=true \
                  -DgeyserUdpPort=server
                '';
                serverProperties = {
                  server-name = server_name;
                  motd = server_name;
                  difficulty = "easy";
                  view-distance = 50;
                  max-world-size = 29999984;
                  spawn-protection = 0;
                  white-list = true;
                  server-port = constants.ports.minecraft;
                };
                symlinks = {
                  "plugins/Geyser.jar" = pkgs.fetchurl {
                    url = "https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot";
                    name = "Geyser";
                    hash = "sha256-vRNYzLMA28eZkTAulzQc0El6jK4w/gWBFV8OGIrsKtc=";
                  };
                  "plugins/Floodgate.jar" = pkgs.fetchurl {
                    url = "https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot";
                    name = "Floodgate";
                    hash = "sha256-lnLGEWtBGuQSFU7fLZMVxLZ9sbNtGJhUedPMl8S0WrU=";
                  };
                };
                files = {
                  "whitelist.json" = config.sops.secrets."minecraft/whitelist".path;
                  "ops.json" = config.sops.secrets."minecraft/ops".path;
                };
              };
            };
            system.stateVersion = "25.05";
          };
      };
    };
}
