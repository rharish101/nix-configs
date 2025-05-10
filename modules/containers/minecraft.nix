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
      cpu_limit = 4;
      memory_limit = 6; # in GiB
      server_name = "EBG6 Minecraft server";
      priv_uid_gid = 65536 * 9; # Randomly-chosen UID/GID a/c to how systemd-nspawn chooses one for the user namespacing.
      mc_key_config = {
        owner = "vu-minecraft-999"; # UID is of the "minecraft" user in nix-minecraft
        group = "vg-minecraft-999"; # GID is of the "minecraft" user in nix-minecraft
        restartUnits = [ "container@minecraft.service" ];
      };
    in
    lib.mkIf config.modules.minecraft.enable {
      # User for the Minecraft server.
      users.users.minecraft = {
        uid = priv_uid_gid;
        group = "minecraft";
        isSystemUser = true;
      };
      users.groups.minecraft.gid = priv_uid_gid;

      # Secrets for the server config
      sops.secrets."minecraft/whitelist" = mc_key_config;
      sops.secrets."minecraft/ops" = mc_key_config;

      systemd.services."container@minecraft" = {
        serviceConfig = {
          MemoryHigh = "${toString memory_limit}G";
          CPUQuota = "${toString (cpu_limit * 100)}%";
        };
      };

      containers.minecraft = {
        privateNetwork = true;
        hostAddress = "10.2.0.1";
        localAddress = "10.2.0.2";
        forwardPorts = [
          {
            hostPort = 25565;
            containerPort = 25565;
            protocol = "tcp";
          }
          {
            hostPort = 25565;
            containerPort = 19132;
            protocol = "udp";
          }
        ];

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
            services.minecraft-servers = {
              enable = true;
              eula = true;
              openFirewall = true;

              servers.original = {
                enable = true;
                package = pkgs.minecraftServers.paper-1_21_5;
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
                  -Daikars.new.flags=true
                '';
                serverProperties = {
                  server-name = server_name;
                  motd = server_name;
                  difficulty = "easy";
                  view-distance = 50;
                  max-world-size = 29999984;
                  spawn-protection = 0;
                  white-list = true;
                };
                symlinks = {
                  mods = pkgs.linkFarmFromDrvs "mods" (
                    builtins.attrValues {
                      Geyser = pkgs.fetchurl {
                        url = "https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot";
                        sha512 = "sha512-ZwMLaoLTRnOfyemsa6S4LUppnfj5PMdA92a4RtSkGCwg+2LhfqaPNuKYvD7+hTH1GsT0Vb7M2K7QRu0dudT8+A==";
                      };
                      Floodgate = pkgs.fetchurl {
                        url = "https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot";
                        sha512 = "sha512-B2jTZOGEgQfJDaes+6LTl6IRC5CR/dvU8gPglX7vjn6h0yDmTfHhNyVgOQcSp6Yg5NL98GWKdjpm35EJdfPjuQ==";
                      };
                    }
                  );
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
