# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ options, pkgs, ... }:
{
  # Enable locate.
  services.locate = {
    enable = true;
    package = pkgs.plocate;
    pruneNames = options.services.locate.pruneNames.default ++ [ ".snapshots" ];
  };
}
