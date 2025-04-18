# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.modules.git.dev = lib.mkEnableOption "Install packages for development with Git";
  config = {
    users.users.rharish.packages =
      with pkgs;
      [
        git
        tig
        difftastic
      ]
      ++ lib.optionals config.modules.git.dev [
        gnupg
        pre-commit
      ];
    programs.gnupg.agent.enable = config.modules.git.dev;
  };
}
