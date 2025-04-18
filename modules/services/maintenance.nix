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
      flake = inputs.self.outPath;
      flags = [
        "--update-input"
        "nixpkgs"
        "--commit-lock-file"
      ];
      dates = "weekly";
    };

    # Enable automatic garbage collection & optimisation.
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    nix.settings.auto-optimise-store = true;
  };
}
