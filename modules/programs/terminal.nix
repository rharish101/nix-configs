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
  options.modules.terminal.utils.enable =
    lib.mkEnableOption "Install useful terminal tools & utilities";
  config.users.users.rharish.packages =
    with pkgs;
    lib.mkIf config.modules.terminal.utils.enable [
      gdu
      tmux
      htop
      nnn
      ripgrep
      tree
    ];
}
