# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ pkgs, ... }:
{
  # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  environment.systemPackages = [ pkgs.vim ];

  # Set the default editor.
  environment.variables.EDITOR = "vim";

  # Add LSP servers.
  users.users.rharish.packages = with pkgs; [
    nixd
    nixfmt-rfc-style
  ];
}
