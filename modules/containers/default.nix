# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ ... }:
{
  imports = [
    ./authelia.nix
    ./caddy-wg-client.nix
    ./caddy-wg-server.nix
    ./lldap.nix
    ./minecraft.nix
    ./postgres.nix
  ];
}
