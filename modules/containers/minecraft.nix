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
      csecEnabled = config.modules.crowdsec-lapi.enable;
    in
    lib.mkIf (config.modules.minecraft.enable && config.modules.caddy-wg-client.enable) {
      # User for the Minecraft server.
      users.users.minecraft = {
        uid = constants.uids.minecraft;
        group = "minecraft";
        isSystemUser = true;
      };
      users.groups.minecraft.gid = constants.uids.minecraft;

      sops.secrets."crowdsec/mc-creds".restartUnits = [ "container@minecraft.service" ];

      systemd.services."container@minecraft" = {
        serviceConfig = with constants.limits.minecraft; {
          MemoryHigh = "${toString memory}G";
          CPUQuota = "${toString (cpu * 100)}%";
        };
        requires = [
          "container@caddy-wg-client.service"
          (lib.mkIf csecEnabled "container@crowdsec-lapi.service")
        ];
      };

      networking.bridges = with constants.bridges; {
        "${caddy-mc.name}".interfaces = [ ];
        "${csec-mc.name}" = lib.mkIf csecEnabled { interfaces = [ ]; };
      };

      containers.caddy-wg-client.extraVeths.${constants.bridges.caddy-mc.caddy.interface} =
        with constants.bridges.caddy-mc; {
          hostBridge = name;
          localAddress = "${caddy.ip4}/24";
          localAddress6 = "${caddy.ip6}/112";
        };
      containers.crowdsec-lapi.extraVeths.${constants.bridges.csec-mc.csec.interface} =
        with constants.bridges.csec-mc;
        lib.mkIf csecEnabled {
          hostBridge = name;
          localAddress = "${csec.ip4}/24";
          localAddress6 = "${csec.ip6}/112";
        };

      containers.minecraft = {
        privateNetwork = true;
        hostBridge = constants.bridges.caddy-mc.name;
        localAddress = "${constants.bridges.caddy-mc.mc.ip4}/24";
        localAddress6 = "${constants.bridges.caddy-mc.mc.ip6}/112";

        extraVeths = with constants.bridges; {
          "${csec-mc.mc.interface}" =
            with csec-mc;
            lib.mkIf csecEnabled {
              hostBridge = name;
              localAddress = "${mc.ip4}/24";
              localAddress6 = "${mc.ip6}/112";
            };
        };

        privateUsers = config.users.users.minecraft.uid;
        autoStart = true;
        extraFlags = [
          "--private-users-ownership=auto"
          "--volatile=overlay"
          "--link-journal=host"
          "--load-credential=csec-creds:${config.sops.secrets."crowdsec/mc-creds".path}"
        ];

        bindMounts.dataDir = {
          hostPath = config.modules.minecraft.dataDir;
          mountPoint = "/srv/minecraft";
          isReadOnly = false;
        };

        config =
          { pkgs, ... }:
          {
            imports = [
              inputs.nix-minecraft.nixosModules.minecraft-servers
              ../vendored/crowdsec.nix
            ];
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
                    hash = "sha256-AOYd7L/lZGOaUW21+TBOJo5r1SkSmTMYzRE17ZQPBN0=";
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

            services.crowdsec = lib.mkIf csecEnabled {
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
