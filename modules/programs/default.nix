# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ lib, ... }:
{
  imports = [
    ./editor.nix
    ./git.nix
    ./misc.nix
    ./shell.nix
    ./terminal.nix
  ];

  modules.editor.nixLsp.enable = lib.mkDefault true;
  modules.terminal.utils.enable = lib.mkDefault true;
}
