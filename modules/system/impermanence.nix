# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{
  config,
  inputs,
  lib,
  ...
}:
{
  options.modules.impermanence.path = lib.mkOption {
    description = "Path to the persistent mount for impermanence";
    type = lib.types.str;
    default = "/";
  };
  imports = [ inputs.impermanence.nixosModules.impermanence ];
  config = lib.mkIf (config.modules.impermanence.path != "/") {
    # Define user accounts declaratively, as `/etc/passwd` is on tmpfs.
    users.mutableUsers = false;

    environment.persistence.${config.modules.impermanence.path} = {
      hideMounts = true;
      directories = [
        "/etc/NetworkManager/system-connections"
        "/var/lib/containers"
        "/var/lib/nixos"
        "/var/lib/postgresql"
        "/var/lib/sbctl"
        "/var/lib/systemd/coredump"
        "/var/log"
      ];
      files = [
        "/etc/machine-id"
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
        "/etc/ssh/ssh_host_rsa_key"
        "/etc/ssh/ssh_host_rsa_key.pub"
      ];
    };
  };
}
