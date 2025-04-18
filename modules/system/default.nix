# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ inputs, ... }:
{
  imports = [
    ./impermanence.nix
    ./lanzaboote.nix
    ./secrets.nix
    inputs.ucodenix.nixosModules.default
  ];
}
