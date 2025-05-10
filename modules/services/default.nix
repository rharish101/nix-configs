# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ lib, ... }:
{
  imports = [
    ./locate.nix
    ./maintenance.nix
    ./podman.nix
    ./power-management.nix
    ./ssh-agent.nix
    ./snapper.nix
  ];

  modules.autoUpdate = lib.mkDefault true;
  modules.snapshots.enable = lib.mkDefault true;
}
