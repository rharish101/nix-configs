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
      serverName = "EBG6 Minecraft server";
    in
    lib.mkIf (config.modules.minecraft.enable && config.modules.caddy-wg-client.enable) {
      modules.containers.minecraft = {
        shortName = "mc";
        username = "minecraft";
        allowInternet = true;
        credentials.csec-creds.name = "crowdsec/mc-creds";

        bindMounts.dataDir = {
          hostPath = config.modules.minecraft.dataDir;
          mountPoint = "/srv/minecraft";
          isReadOnly = false;
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

            services.minecraft-servers = {
              enable = true;
              eula = true;

              servers.original = {
                enable = true;
                package = pkgs.minecraftServers.paper-1_21_8;
                # Aikar's flags.
                jvmOpts = with constants.limits.minecraft; ''
                  -Xms${toString memory}G \
                  -Xmx${toString memory}G \
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
                  server-name = serverName;
                  motd = serverName;
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
                    hash = "sha256-IZFB9qQkFJUyurtCQqWBbd5rNvJ03OzNz7/17VtQdWM=";
                  };
                  "plugins/Floodgate.jar" = pkgs.fetchurl {
                    url = "https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot";
                    name = "Floodgate";
                    hash = "sha256-AelUlBDvIOJk75r2tDxp89HPJOl1b/9mc4KgScPKjTk=";
                  };
                };
                files."config/paper-global.yml".value.proxies.proxy-protocol = true;
              };
            };

            services.crowdsec = lib.mkIf config.modules.crowdsec-lapi.enable {
              enable = true;
              autoUpdateService = true;
              name = "${config.networking.hostName}-minecraft";

              localConfig =
                let
                  mcParser = import ../crowdsec/parsers/minecraft.nix;
                  mcScenario = import ../crowdsec/scenarios/minecraft.nix;
                in
                {
                  acquisitions = [
                    {
                      source = "file";
                      # Since log lines don't have any dates in them, CrowdSec will lump all events
                      # in the same day. Thus, to avoid unwanted collisions across different logs
                      # (each log gzip is for a different run on a different day), just parse the
                      # latest log.
                      filenames = [ "/srv/minecraft/original/logs/latest.log" ];
                      labels.type = "minecraft";
                      use_time_machine = true;
                    }
                  ];
                  scenarios = [ mcScenario ];
                  parsers.s01Parse = [ mcParser ];
                };
              hub.collections = [ "crowdsecurity/linux" ];
              settings.general.api.client.credentials_path = lib.mkForce "\${CREDENTIALS_DIRECTORY}/csec-creds";
            };
            systemd.services.crowdsec.serviceConfig.LoadCredential = [ "csec-creds:csec-creds" ];
            users.users.crowdsec.extraGroups = [ "minecraft" ];

            system.stateVersion = "25.05";
          };
      };
    };
}
