# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ ... }:
{
  # Enable SSH & GPG agents.
  programs.ssh.startAgent = true;
  programs.gnupg.agent.enable = true;
}
