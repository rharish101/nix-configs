# SPDX-FileCopyrightText: 2026 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
let
  hostName = config.networking.hostName;
in
{
  options.modules.restic = {
    enable = lib.mkEnableOption "Enable remote backups with Restic";
    ssh = {
      config = lib.mkOption {
        description = "SSH host config for the restic SFTP remote";
        type = lib.types.str;
      };
      hostName = lib.mkOption {
        description = "The hostname to be used in the SSH known hosts for th restic SFTP remote";
        type = lib.types.str;
      };
      publicKey = lib.mkOption {
        description = "Public key for the restic SFTP remote";
        type = lib.types.str;
      };
    };
  };

  config = lib.mkIf config.modules.restic.enable {
    sops.secrets."restic/${hostName}" = { };

    programs.ssh = with config.modules.restic; {
      # Keep SSH connection alive to prevent timeout during backup.
      extraConfig = ''
        Host restic-remote
          ${ssh.config}
          IdentityFile /etc/ssh/ssh_host_ed25519_key
          ServerAliveInterval 60
          ServerAliveCountMax 240
      '';
      knownHosts.${ssh.hostName}.publicKey = ssh.publicKey;
    };

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
