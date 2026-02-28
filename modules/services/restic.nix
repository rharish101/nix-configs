# SPDX-FileCopyrightText: 2026 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
let
  hostName = config.networking.hostName;
in
{
  options.modules.restic.enable = lib.mkEnableOption "Enable remote backups with Restic";
  config = lib.mkIf config.modules.restic.enable {
    sops.secrets."restic/${hostName}" = { };

    # Keep SSH connection alive to prevent timeout during backup.
    # NOTE: SSH config is incomplete - remote server IP is in /etc/ssh/ssh_config.d.
    programs.ssh.extraConfig = "
      Host restic-remote
        IdentityFile /etc/ssh/ssh_host_ed25519_key
        ServerAliveInterval 60
        ServerAliveCountMax 240
    ";

    services.restic.backups.${hostName} = {
      repository = "sftp:restic-remote:restic";
      passwordFile = config.sops.secrets."restic/${hostName}".path;
      # Should cover all subvolumes with persistent data except DB subvolumes, but they're backed up
      # to /data.
      paths = [
        config.modules.impermanence.path
        "/home"
        "/data"
      ];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
      };
      pruneOpts = [
        "--keep-weekly 5"
        "--keep-monthly 5"
        "--keep-yearly 5"
      ];
      inhibitsSleep = true;
    };
  };
}
