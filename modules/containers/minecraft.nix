# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

let
  cpu_limit = 4;
  memory_limit = 6; # in GiB
in
{ ... }:
{
  virtualisation.oci-containers.containers."minecraft" = {
    image = "itzg/minecraft-server";
    ports = [ "25565:25565" ];
    environment = {
      EULA = "TRUE";
      TYPE = "PAPER";
      VERSION = "1.21.5";
      PAPER_CHANNEL = "experimental";
      MEMORY = "${toString memory_limit}G";
      USE_AIKAR_FLAGS = "true";
    };
    volumes = [ "/data/minecraft:/data" ];
    podman.user = "minecraft";
    extraOptions = [
      "--memory=${toString (memory_limit + 1)}g" # Extra memory for some overhead
      "--cpus=${toString cpu_limit}"
    ];
  };

  # User for the Minecraft server.
  users.users.minecraft = {
    group = "minecraft";
    isNormalUser = true;
  };
  users.groups.minecraft = { };
}
