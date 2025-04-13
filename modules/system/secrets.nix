# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

let
  artorias_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIETY0BUwxJxpgVCRR6BXXqihGGXKy5e2h67XTDcDhcP4 artorias";
in
{ config, inputs, ... }:
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  sops.defaultSopsFile = ../../secrets/secrets.yaml;
  sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

  sops.secrets."users/root".neededForUsers = true;
  sops.secrets."users/rharish".neededForUsers = true;

  users.users.root = {
    hashedPasswordFile = config.sops.secrets."users/root".path;
    openssh.authorizedKeys.keys = [ artorias_key ];
  };
  users.users.rharish = {
    hashedPasswordFile = config.sops.secrets."users/rharish".path;
    openssh.authorizedKeys.keys = [ artorias_key ];
  };
}
