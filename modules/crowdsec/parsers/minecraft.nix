# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{
  name = "rharish101/minecraft-logs";
  description = "Parse Minecraft logs for non-whitelisted/banned/unauthenticated users";
  filter = "evt.Parsed.program == 'minecraft'";
  onsuccess = "next_stage";
  pattern_syntax.MINECRAFT_USER = "[a-zA-Z0-9_]{3,16}";
  nodes = [
    {
      name = "Banned user";
      grok = {
        pattern = "^\\[%{TIME:time}\\] \\[Server thread/INFO\\]: %{MINECRAFT_USER:user} \\(/%{IP:source_ip}:%{POSINT}\\) lost connection: You are banned from this server.$";
        apply_on = "message";
      };
      statics = [
        {
          meta = "log_subtype";
          value = "minecraft_banned";
        }
        {
          meta = "user";
          expression = "evt.Parsed.user";
        }
      ];
    }
    {
      name = "User not white-listed";
      grok = {
        pattern = "^\\[%{TIME:time}\\] \\[Server thread/INFO\\]: %{MINECRAFT_USER:user} \\(/%{IP:source_ip}:%{POSINT}\\) lost connection: You are not white-?listed on this server!$";
        apply_on = "message";
      };
      statics = [
        {
          meta = "log_subtype";
          value = "minecraft_not_whitelisted";
        }
        {
          meta = "user";
          expression = "evt.Parsed.user";
        }
      ];
    }
    {
      name = "Possibly offline account user";
      grok = {
        pattern = "^\\[%{TIME:time}\\] \\[Server thread/INFO\\]: %{MINECRAFT_USER:user} \\(/%{IP:source_ip}:%{POSINT}\\) lost connection: Disconnected$";
        apply_on = "message";
      };
      statics = [
        {
          meta = "log_subtype";
          value = "minecraft_possibly_offline";
        }
        {
          meta = "user";
          expression = "evt.Parsed.user";
        }
      ];
    }
    {
      name = "Invalid username";
      grok = {
        pattern = "^\\[%{TIME:time}\\] \\[Server thread/INFO\\]: /%{IP:source_ip}:%{POSINT} lost connection: Disconnected$";
        apply_on = "message";
      };
      statics = [
        {
          meta = "log_subtype";
          value = "minecraft_invalid_username";
        }
      ];
    }
  ];
  statics = [
    {
      meta = "service";
      value = "minecraft";
    }
    {
      meta = "source_ip";
      expression = "evt.Parsed.source_ip";
    }
    {
      target = "evt.StrTime";
      expression = "evt.Parsed.time";
    }
    {
      target = "evt.StrTimeFormat";
      value = "15:04:05";
    }
    {
      meta = "log_type";
      value = "minecraft_auth_failed";
    }
  ];
}
