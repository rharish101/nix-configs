# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ ... }:
{
  virtualisation = {
    podman.enable = true;
    oci-containers.backend = "podman";
  };
}
