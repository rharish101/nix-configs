# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

let
  artorias_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIETY0BUwxJxpgVCRR6BXXqihGGXKy5e2h67XTDcDhcP4 artorias";
  passwords_dir = "/persist/etc/passwords";
in
{ ... }:
{
  users.users.root = {
    hashedPasswordFile = "${passwords_dir}/root.passwd"; # NOTE: This file is read *before* impermanence mounts are made.
    openssh.authorizedKeys.keys = [ artorias_key ];
  };
  users.users.rharish = {
    hashedPasswordFile = "${passwords_dir}/rharish.passwd"; # NOTE: This file is read *before* impermanence mounts are made.
    openssh.authorizedKeys.keys = [ artorias_key ];
  };
}
