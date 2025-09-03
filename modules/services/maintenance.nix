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
  options.modules.autoUpdate = lib.mkEnableOption "Enable automatic system updates";
  config = {
    # Enable automatic upgrades.
    system.autoUpgrade = lib.mkIf config.modules.autoUpdate {
      enable = true;
      flake = "/etc/nixos";
      flags = builtins.concatMap (inp: [
        "--update-input"
        inp
      ]) (builtins.attrNames inputs);
      dates = "weekly";
    };
    programs.git.config.safe.directory = "/etc/nixos";

    # Enable automatic garbage collection & optimisation.
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    nix.settings.auto-optimise-store = true;
  };
}
