# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  options.modules.secureBoot.enable = lib.mkEnableOption "Enable UEFI secure boot";
  imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];
  config = lib.mkIf config.modules.secureBoot.enable {
    # For debugging and troubleshooting Secure Boot.
    environment.systemPackages = [ pkgs.sbctl ];

    # Lanzaboote currently replaces the systemd-boot module.
    # This setting is usually set to true in configuration.nix
    # generated at installation time. So we force it to false
    # for now.
    boot.loader.systemd-boot.enable = lib.mkForce false;
    boot.lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };
  };
}
