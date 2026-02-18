# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, ... }:
let
  mc_port = 26460;
  ssh_port = 8398;
  wg_port = 34104;
  constants = import ../../modules/constants.nix;
in
{
  imports = [
    ./hardware-configuration.nix # Include the results of the hardware scan.
    ../../modules # Include custom modules.
  ];

  # Use the GRUB 2 boot loader.
  boot.loader.grub.enable = true;
  # Define on which hard drive you want to install Grub.
  boot.loader.grub.device = "/dev/sda";

  networking.hostName = "shalquoir"; # Define your hostname.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.

  # Open ports in the firewall.
  networking.firewall = {
    allowedTCPPorts = [
      443
      mc_port
      ssh_port
    ];
    allowedUDPPorts = [
      443
      mc_port
      wg_port
    ];
  };
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;
  networking.nftables.enable = true;

  # Hairpin NAT for the wireguard server.
  networking.nftables.tables.hairpin-nat = {
    name = "hairpin-nat";
    family = "ip";
    content =
      let
        caddyIp4 = constants.veths.caddy.local.ip4;
      in
      ''
        chain prerouting {
          type nat hook prerouting priority dstnat;
          ip saddr ${caddyIp4} oifname ${config.networking.nat.externalInterface} dnat to ${caddyIp4}
        }
        chain postrouting {
          type nat hook postrouting priority srcnat;
          ip saddr ${caddyIp4} ip daddr ${caddyIp4} masquerade
        }
      '';
  };

  networking.nat = {
    enable = true;
    internalInterfaces = [ "ve-*" ];
  };

  # Set up a wireguard server for Raime.
  modules.caddy-wg-server = {
    enable = true;
    wireguard = {
      port = wg_port;
      client.publicKey = "+lFv4mihO8w3eho26ebsrwU+NA5DlqgJPHTvYxINnS4=";
    };
    caddy.minecraftPort = mc_port;
    crowdsec.enable = true;
  };

  # Set your time zone.
  time.timeZone = "Europe/Berlin";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Define user accounts declaratively (required by impermanence) and their passwords.
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.rharish = {
    isNormalUser = true;
    uid = 1000; # Keep this fixed, so that adding more users doesn't change this UID.
    extraGroups = [
      "wheel" # Enable 'sudo' for the user.
      "networkmanager" # Allow NetworkManager access.
    ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget

  # Enable the OpenSSH daemon with strict security.
  services.openssh = {
    enable = true;
    ports = [ ssh_port ];
    settings = {
      AllowUsers = [ "rharish" ];
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  modules.crowdsec-bouncer.enable = true;
  modules.crowdsec-sshd.enable = true;
  modules.editor.nixLsp.enable = false;
  modules.impermanence.path = "/persist";
  modules.snapshots.enable = false;

  # Needed for remote deployment.
  nix.settings.trusted-users = [
    "root"
    "rharish"
  ];

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "24.11"; # Did you read the comment?
}
