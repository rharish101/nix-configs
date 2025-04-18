# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.minecraft.enable = lib.mkEnableOption "Enable Minecraft servers";
  config =
    let
      cpu_limit = 4;
      memory_limit = 6; # in GiB
      server_name = "EBG6 Minecraft server";
    in
    lib.mkIf (config.modules.podman.enable && config.modules.minecraft.enable) {
      virtualisation.oci-containers.containers.minecraft = {
        image = "itzg/minecraft-server";
        ports = [ "25565:25565" ];
        environment = {
          EULA = "TRUE";
          TYPE = "PAPER";
          VERSION = "1.21.5";
          PAPER_CHANNEL = "experimental";
          MEMORY = "${toString memory_limit}G";
          USE_AIKAR_FLAGS = "true";
          SERVER_NAME = server_name;
          MOTD = server_name;
          DIFFICULTY = "easy";
          VIEW_DISTANCE = "50";
          MAX_WORLD_SIZE = "29999984";
          SPAWN_PROTECTION = "0";
          EXISTING_OPS_FILE = "SYNCHRONIZE";
          EXISTING_WHITELIST_FILE = "SYNCHRONIZE";
          PLUGINS = ''
            https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot
            https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot
          '';
        };
        # Store SOPS secrets in an env file, since it's only accessible to the host, not the container.
        environmentFiles = [ config.sops.secrets."minecraft".path ];
        volumes = [
          "/data/minecraft:/data"
        ];
        podman.user = "minecraft";
        extraOptions = [
          "--memory=${toString (memory_limit + 1)}g" # Extra memory for some overhead
          "--cpus=${toString cpu_limit}"
        ];
      };

      # User for the Minecraft server.
      users.users.minecraft = {
        uid = 2001;
        group = "minecraft";
        isNormalUser = true;
      };
      users.groups.minecraft.gid = 901;

      # Secrets for the server config
      sops.secrets."minecraft" = {
        owner = config.users.users.minecraft.name;
        group = config.users.users.minecraft.group;
        restartUnits = [
          "${config.virtualisation.oci-containers.containers.minecraft.serviceName}.service"
        ];
      };
    };
}
