# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.podman.enable = lib.mkEnableOption "Enable podman for OCI containers";
  config.virtualisation = lib.mkIf config.modules.podman.enable {
    podman.enable = true;
    oci-containers.backend = "podman";
  };
}
