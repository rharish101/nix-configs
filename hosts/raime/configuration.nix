# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ ... }:
{
  imports = [
    ./hardware-configuration.nix # Include the results of the hardware scan.
    ../../modules # Include custom modules.
  ];

  # Allow modifying EFI variables.
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "raime"; # Define your hostname.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # Set your time zone.
  time.timeZone = "Europe/Zurich";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Define user accounts declaratively (required by impermanence) and their passwords.
  users.users.rharish = {
    isNormalUser = true;
    uid = 1000; # Keep this fixed, so that adding more users doesn't change this UID.
    extraGroups = [
      "wheel" # Enable 'sudo' for the user.
      "networkmanager" # Allow NetworkManager access.
    ];
  };

  # Enable the following secrets.
  sops.secrets."crypttab/cache" = { };
  sops.secrets."crypttab/data1" = { };
  sops.secrets."crypttab/data2" = { };

  # List packages installed in system profile. To search, run:
  # $ nix search wget

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Enable fresh AMD microcode updates.
  services.ucodenix.enable = true;

  # Enable firmware updates.
  services.fwupd.enable = true;

  # Custom module configuration
  modules.git.dev = true;
  modules.impermanence.path = "/persist";
  modules.minecraft.enable = true;
  modules.secureBoot.enable = true;

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
