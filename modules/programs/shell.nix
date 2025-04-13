# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ pkgs, ... }:
{
  # Enable fish globally to enable vendor completions.
  programs.fish.enable = true;

  # Install fish, along with some useful packages.
  users.users.rharish = {
    shell = pkgs.fish;
    packages = with pkgs; [
      cowsay
      fortune
      dotacat
      fishPlugins.tide
      any-nix-shell
    ];
  };
}
