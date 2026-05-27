# SPDX-FileCopyrightText: 2026 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.clamav = {
    enable = lib.mkEnableOption "Enable scanning files with ClamAV";
    extraScanDirs = lib.mkOption {
      description = "List of directories to scan on top of the defaults";
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
  };

  config.services.clamav = lib.mkIf config.modules.clamav.enable {
    daemon = {
      enable = true;
      settings = {
        CrossFilesystems = false;
        # Btrfs subvolumes aren't excluded by disabling CrossFilesystems.
        ExcludePath = ''/\.snapshots/'';
      };
    };
    updater.enable = true;
    fangfrisch.enable = true;
    scanner = {
      enable = true;
      scanDirectories = [
        "${config.modules.impermanence.path}/etc"
        "${config.modules.impermanence.path}/var/lib"
        "/home"
        "/tmp"
        "/var/tmp"
      ]
      ++ config.modules.clamav.extraScanDirs;
    };
  };
}
