# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{
  name = "rharish101/minecraft-dos";
  description = "Detect Minecraft login DoS";
  filter = "evt.Meta.service == 'minecraft' && evt.Meta.log_type == 'minecraft_auth_failed'";
  type = "leaky";
  groupby = "evt.Meta.source_ip";
  leakspeed = "10s";
  capacity = 5;
  blackhole = "1m";
  labels = {
    service = "minecraft";
    confidence = 2;
    spoofable = 0;
    classification = [ "attack.T1499" ];
    behavior = "http:dos";
    label = "Login spam";
    remediation = true;
  };
}
