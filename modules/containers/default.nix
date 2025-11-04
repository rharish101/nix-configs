# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ ... }:
{
  imports = [
    ./base.nix
    ./authelia.nix
    ./caddy-wg-client.nix
    ./caddy-wg-server.nix
    ./crowdsec-lapi.nix
    ./immich.nix
    ./jellyfin.nix
    ./lldap.nix
    ./minecraft.nix
    ./opencloud.nix
    ./postgres.nix
    ./tandoor.nix
  ];
}
