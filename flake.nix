{
  description = "Harish's flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    impermanence.url = "github:nix-community/impermanence";
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      # Optional but recommended to limit the size of your system closure.
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, impermanence, lanzaboote }: {
    nixosConfigurations.raime = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        impermanence.nixosModules.impermanence
        lanzaboote.nixosModules.lanzaboote

        ({ pkgs, lib, ... }: {
          environment.systemPackages = [
            # For debugging and troubleshooting Secure Boot.
            pkgs.sbctl
          ];

          environment.persistence."/persist" = {
            hideMounts = true;
            directories = [
              "/etc/NetworkManager/system-connections"
              "/etc/nixos"
              "/root/keyfiles"
              "/var/lib/containers"
              "/var/lib/nixos"
              "/var/lib/sbctl"
              "/var/lib/systemd/coredump"
              "/var/log"
            ];
            files = [
              "/etc/machine-id"
            ];
          };

          # Lanzaboote currently replaces the systemd-boot module.
          # This setting is usually set to true in configuration.nix
          # generated at installation time. So we force it to false
          # for now.
          boot.loader.systemd-boot.enable = lib.mkForce false;
          boot.lanzaboote = {
            enable = true;
            pkiBundle = "/var/lib/sbctl";
          };
        })
      ];
    };
  };
}
