# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ ... }:
{
  imports = [
    ./containers
    ./programs
    ./services
    ./system
  ];

  # Enable flakes, since they're experimental now.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
