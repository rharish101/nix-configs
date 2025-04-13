# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ ... }:
{
  imports = [
    ./programs/editor.nix
    ./programs/git.nix
    ./programs/misc.nix
    ./programs/shell.nix
    ./programs/terminal.nix
    ./services/locate.nix
    ./services/maintenance.nix
    ./services/podman.nix
    ./services/power-management.nix
    ./services/secrets.nix
    ./services/snapper.nix
    ./system/impermanence.nix
    ./system/lanzaboote.nix
    ./system/secrets.nix
  ];
}
