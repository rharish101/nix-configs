# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

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
    };
    volumes = [ "/data/minecraft:/data" ];
    podman.user = "minecraft";
  };

  # User for the Minecraft server.
  users.users.minecraft = {
    group = "minecraft";
    isNormalUser = true;
  };
  users.groups.minecraft = { };
}
