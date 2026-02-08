# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.snapshots.enable = lib.mkEnableOption "Enable snapshotting of a Btrfs root partition";
  # Enable snapper for automatic Btrfs snapshots.
  config.services.snapper.configs =
    let
      rootConfigName = if (config.modules.impermanence.path == "/") then "root" else "persist";
    in
    lib.mkIf config.modules.snapshots.enable {
      "${rootConfigName}" = {
        SUBVOLUME = config.modules.impermanence.path;
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = 0;
        TIMELINE_LIMIT_DAILY = 5;
        TIMELINE_LIMIT_WEEKLY = 0;
        TIMELINE_LIMIT_MONTHLY = 5;
        TIMELINE_LIMIT_QUARTERLY = 2;
        TIMELINE_LIMIT_YEARLY = 2;
      };
      nix = {
        SUBVOLUME = "/nix";
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = 0;
        TIMELINE_LIMIT_DAILY = 5;
        TIMELINE_LIMIT_WEEKLY = 0;
        TIMELINE_LIMIT_MONTHLY = 5;
        TIMELINE_LIMIT_QUARTERLY = 0;
        TIMELINE_LIMIT_YEARLY = 0;
      };
      home = {
        SUBVOLUME = "/home";
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = 5;
        TIMELINE_LIMIT_DAILY = 5;
        TIMELINE_LIMIT_WEEKLY = 0;
        TIMELINE_LIMIT_MONTHLY = 5;
        TIMELINE_LIMIT_QUARTERLY = 0;
        TIMELINE_LIMIT_YEARLY = 0;
      };
      data = {
        SUBVOLUME = "/data";
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = 5;
        TIMELINE_LIMIT_DAILY = 5;
        TIMELINE_LIMIT_WEEKLY = 0;
        TIMELINE_LIMIT_MONTHLY = 5;
        TIMELINE_LIMIT_QUARTERLY = 2;
        TIMELINE_LIMIT_YEARLY = 2;
      };
    };
}
