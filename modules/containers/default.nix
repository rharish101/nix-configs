# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ ... }:
{
  imports = [
    ./caddy-wg-client.nix
    ./caddy-wg-server.nix
    ./minecraft.nix
  ];
}
