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
      serverPorts = {
        original = 5001;
      };
    in
    lib.mkIf (config.modules.minecraft.enable && config.modules.caddy-wg-client.enable) {
      sops.templates."minecraft/env".content = ''
        VELOCITY_SECRET=${config.sops.placeholder."minecraft/velocity"}
      '';

      modules.containers.minecraft = {
        shortName = "mc";
        username = "minecraft";
        allowInternet = true;

        credentials = {
          csec-creds.name = "crowdsec/mc-creds";
          velocity-secret.name = "minecraft/velocity";
          env = {
            name = "minecraft/env";
            sopsType = "template";
          };
        };

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
              environmentFile = "/run/credentials/@system/env";

              servers.proxy = {
                enable = true;
                package = pkgs.velocityServers.velocity;
                # Flags from: https://docs.papermc.io/velocity/getting-started/
                jvmOpts = ''
                  -Xms1G \
                  -Xmx1G \
                  -XX:+UseG1GC \
                  -XX:G1HeapRegionSize=4M \
                  -XX:+UnlockExperimentalVMOptions \
                  -XX:+ParallelRefProcEnabled \
                  -XX:+AlwaysPreTouch \
                  -XX:MaxInlineLevel=15 \
                  -DgeyserUdpPort=server
                '';
                symlinks = {
                  "plugins/Geyser.jar" = pkgs.fetchurl {
                    url = "https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/velocity";
                    name = "Geyser";
                    hash = "sha256-p2CLx+q1Zb5st3nXEWQgQpDGTBzfIlE2D5O66IG58Ww=";
                  };
                  "plugins/Floodgate.jar" = pkgs.fetchurl {
                    url = "https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/velocity";
                    name = "Floodgate";
                    hash = "sha256-JJFZZVqa6P64PGlz7KhkfgExajDOnLPfGDpoS39W/Bc=";
                  };
                };
                files."velocity.toml".value = {
                  config-version = "2.7";
                  bind = "0.0.0.0:${toString constants.ports.minecraft}";
                  motd = serverName;
                  player-info-forwarding-mode = "modern";
                  forwarding-secret-file = "@CREDENTIALS_DIRECTORY@/velocity-secret";
                  servers = builtins.mapAttrs (_: port: "127.0.0.1:${toString port}") serverPorts // {
                    try = builtins.attrNames serverPorts;
                  };
                  forced-hosts = { }; # Unset the existing example hosts.
                  advanced.haproxy-protocol = true;
                };
              };

              servers.original = {
                enable = true;
                package = pkgs.minecraftServers.paper-1_21_11;
                # Aikar's flags.
                jvmOpts = with constants.limits.minecraft; ''
                  -Xms${toString (memory - 1)}G \
                  -Xmx${toString (memory - 1)}G \
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
                  server-name = serverName;
                  difficulty = "easy";
                  view-distance = 50;
                  max-world-size = 29999984;
                  spawn-protection = 0;
                  white-list = true;
                  server-ip = "127.0.0.1"; # Only needs to be accessible by Velocity
                  server-port = serverPorts.original;
                  online-mode = false; # Velocity does this for us.
                };
                files."config/paper-global.yml".value.proxies.velocity = {
                  enabled = true;
                  secret = "@VELOCITY_SECRET@";
                };
              };
            };
            systemd.services.minecraft-server-proxy.serviceConfig.LoadCredential = [
              "velocity-secret:velocity-secret"
            ];

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
                      filenames = [ "/srv/minecraft/*/logs/latest.log" ];
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
