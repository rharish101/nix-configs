# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ ... }:
{
  imports = [
    ./base.nix
    ./authelia.nix
    ./bazarr.nix
    ./caddy-wg-client.nix
    ./caddy-wg-server.nix
    ./collabora.nix
    ./crowdsec-lapi.nix
    ./immich.nix
    ./jellyfin.nix
    ./lidarr.nix
    ./lldap.nix
    ./minecraft.nix
    ./opencloud.nix
    ./postgres.nix
    ./prowlarr.nix
    ./qbittorrent.nix
    ./qui.nix
    ./radarr.nix
    ./sonarr.nix
    ./tandoor.nix
    ./vaultwarden.nix
  ];
}
