# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ lib, ... }:
{
  imports = [
    ./clamav.nix
    ./crowdsec-bouncer.nix
    ./crowdsec-sshd.nix
    ./locate.nix
    ./maintenance.nix
    ./podman.nix
    ./power-management.nix
    ./restic.nix
    ./snapper.nix
    ./ssh-agent.nix
  ];

  modules.autoUpdate = lib.mkDefault true;
  modules.snapshots.enable = lib.mkDefault true;
}
