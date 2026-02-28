# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (builtins) attrNames filter hasAttr;
  inherit (lib)
    concatMapStrings
    filterAttrs
    hasPrefix
    mapAttrsToList
    mkDefault
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optionalString
    pipe
    types
    ;

  # Options for each container.
  containerOpts = {
    freeformType = types.attrs; # Allow using `containers.<name>` options automatically.
    options = {
      username = mkOption {
        description = "Username for the host user that is mapped to the container's root user";
        type = with types; nullOr str;
        default = null;
      };
      credentials = mkOption {
        description = "Attribute set of SOPS secrets to be loaded as the container's system credentials";
        type =
          with types;
          attrsOf (submodule {
            options = {
              name = mkOption {
                description = "The SOPS name of this credential";
                type = types.str;
              };
              sopsType = mkOption {
                description = "Whether this is a standard SOPS secret or a template";
                type = types.enum [
                  "secret"
                  "template"
                ];
                default = "secret";
              };
            };

          });
        default = { };
      };
      allowInternet = mkEnableOption "Allow this container to access the internet";
      allowedPorts = {
        Tcp = mkOption {
          description = "List of TCP ports to which incoming connections are only allowed from certain containers";
          type = with types; listOf port;
          default = [ ];
        };
        Udp = mkOption {
          description = "List of UDP ports to which incoming connections are only allowed from certain containers";
          type = with types; listOf port;
          default = [ ];
        };
      };
      useMacvlan = mkEnableOption "Allow this container to access the local network through a macvlan interface";
    };
  };

  # DNS provider.
  nameserver = "1.1.1.1";
in
{
  options.modules.containers = mkOption {
    description = "A set of NixOS container configurations with custom defaults";
    type = with types; attrsOf (submodule containerOpts);
    default = { };
  };

  config =
    let
      constants = import ../constants.nix;

      bridgeName = "br-containers";

      # Map an attribute set and use `lib.mkMerge` to merge them.
      mergeMapAttrs = func: attr: mkMerge (mapAttrsToList func attr);

      # Containers that have set a username.
      containersWithUsernames = filterAttrs (_: cfg: cfg.username != null) config.modules.containers;
    in
    {
      containers = builtins.mapAttrs (
        name: cfg:
        # Merge such that the specified config can override defaults if needed.
        mkMerge [
          (
            # Calculate default container config.
            let
              # The container's local IP addresses for this container's default network interface.
              # It also has a flag denoting whether to add the subnet mask.
              # This depends on whether the interface is a network bridge or not (IDK why).
              localAddresses =
                if !hasAttr name constants.bridge then
                  constants.veths.caddy.local // { subnet = false; }
                else
                  constants.bridge.${name} // { subnet = true; };

              # The host's IP addresses for this container's default network interface.
              # Only for containers that aren't part of the bridge.
              hostAddresses = if !hasAttr name constants.bridge then constants.veths.caddy.host else null;
            in
            {
              privateNetwork = mkDefault true;
              privateUsers = mkDefault (if isNull cfg.username then "pick" else constants.uids.${cfg.username});
              autoStart = mkDefault true;

              hostBridge = mkIf (hasAttr name constants.bridge) (mkDefault bridgeName);
              hostAddress = mkIf (hostAddresses != null) (mkDefault hostAddresses.ip4);
              hostAddress6 = mkIf (hostAddresses != null) (mkDefault hostAddresses.ip6);
              localAddress = mkIf (localAddresses != null) (
                mkDefault (localAddresses.ip4 + (if localAddresses.subnet then "/24" else ""))
              );
              localAddress6 = mkIf (localAddresses != null) (
                mkDefault (localAddresses.ip6 + (if localAddresses.subnet then "/112" else ""))
              );

              macvlans = if cfg.useMacvlan then mkDefault [ config.networking.nat.externalInterface ] else [ ];
              # Add veth to host if macvlan isn't enabled.
              extraVeths.eth1 =
                mkIf (hasPrefix "caddy-wg-" name && hasAttr name constants.bridge && !cfg.useMacvlan)
                  {
                    hostAddress = constants.veths.caddy.host.ip4;
                    hostAddress6 = constants.veths.caddy.host.ip6;
                    localAddress = constants.veths.caddy.local.ip4;
                    localAddress6 = constants.veths.caddy.local.ip6;
                  };

              extraFlags =
                let
                  # Convert a single hex character at a given index to the corresponding character in the UUID.
                  # This adds the UUID version or the UUID variant depending on the index.
                  uuidImap =
                    i: char:
                    if i == 12 then
                      "4"
                    else if i == 16 then
                      pipe char [
                        lib.fromHexString
                        (builtins.bitAnd 3)
                        (builtins.bitOr 8)
                        lib.toHexString
                        lib.toLower
                      ]
                    else
                      char;

                  # Convert a container name (arbitrary string) deterministically to UUIDv4.
                  # This just hashes it with MD5 (since the hash is 128 bits, same as UUIDv4) and formats it to look like UUIDv4.
                  nameToUuid =
                    name:
                    pipe name [
                      (builtins.hashString "md5")
                      lib.stringToCharacters
                      (lib.concatImapStrings uuidImap)
                    ];
                in
                [
                  "--private-users-ownership=auto"
                  "--volatile=overlay"
                  "--link-journal=host"
                  "--uuid=${nameToUuid name}" # Make the machine ID deterministic.
                ]
                # Get the corresponding systemd-nspawn CLI flags for loading each SOPS secret as a systemd credential.
                ++ mapAttrsToList (
                  credentialName: secret:
                  "--load-credential=${credentialName}:"
                  + (
                    if secret.sopsType == "secret" then
                      config.sops.secrets.${secret.name}.path
                    else
                      config.sops.templates.${secret.name}.path
                  )
                ) cfg.credentials;

              config =
                { ... }:
                {
                  networking =
                    let
                      gateways = filter (hasPrefix "caddy-wg-") constants.containerDeps.${name} or [ ];
                      defaultGateway = lib.optionalAttrs (gateways != [ ]) constants.bridge.${builtins.head gateways};
                      allowInternet = cfg.allowInternet && !hasPrefix "caddy-wg-" name && defaultGateway != { };
                      listToSet = values: lib.concatStringsSep "," (map toString values);
                      getIpAddrs =
                        ipType: map (value: constants.bridge.${value}.${ipType}) constants.firewallOpen.${name};
                      ip4Addrs = listToSet (getIpAddrs "ip4");
                      ip6Addrs = listToSet (getIpAddrs "ip6");
                      tcpPorts = listToSet cfg.allowedPorts.Tcp;
                      udpPorts = listToSet cfg.allowedPorts.Udp;
                    in
                    {
                      # Config for allowing internet through the bridge to another container
                      defaultGateway = mkIf allowInternet {
                        address = mkDefault defaultGateway.ip4;
                        interface = mkDefault "eth0";
                      };
                      defaultGateway6 = mkIf allowInternet {
                        address = mkDefault defaultGateway.ip6;
                        interface = mkDefault "eth0";
                      };
                      nameservers = if allowInternet then [ nameserver ] else [ ];

                      # Use systemd-networkd to configure network access through the macvlan interface.
                      useNetworkd = mkDefault cfg.useMacvlan;
                      interfaces = mkIf cfg.useMacvlan {
                        "mv-${config.networking.nat.externalInterface}".useDHCP = mkDefault true;
                      };
                      useHostResolvConf = !cfg.useMacvlan;

                      # Use nftables by default.
                      nftables.enable = mkDefault true;

                      firewall.extraCommands =
                        optionalString (!config.networking.nftables.enable && udpPorts != "") ''
                          iptables -A nixos-fw -p tcp -s ${ip4Addrs} -m multiport --dports ${tcpPorts} -j nixos-fw-accept
                          ip6tables -A nixos-fw -p tcp -s ${ip6Addrs} -m multiport --dports ${tcpPorts} -j nixos-fw-accept
                        ''
                        + optionalString (!config.networking.nftables.enable && udpPorts != "") ''
                          iptables -A nixos-fw -p udp -s ${ip4Addrs} -m multiport --dports ${udpPorts} -j nixos-fw-accept
                          ip6tables -A nixos-fw -p udp -s ${ip6Addrs} -m multiport --dports ${udpPorts} -j nixos-fw-accept
                        '';
                      firewall.extraInputRules =
                        optionalString (config.networking.nftables.enable && tcpPorts != "") ''
                          ip saddr { ${ip4Addrs} } tcp dport { ${tcpPorts} } accept
                          ip6 saddr { ${ip6Addrs} } tcp dport { ${tcpPorts} } accept
                        ''
                        + optionalString (config.networking.nftables.enable && udpPorts != "") ''
                          ip saddr { ${ip4Addrs} } udp dport { ${udpPorts} } accept
                          ip6 saddr { ${ip6Addrs} } udp dport { ${udpPorts} } accept
                        '';
                    };

                  # Enable flakes so that we can debug inside containers.
                  nix.settings.experimental-features = [
                    "nix-command"
                    "flakes"
                  ];

                  services.redis.package = mkDefault pkgs.valkey;

                  # Set a low reload time, to account for crashes on init:
                  # 1. The local API server crashes due to temporary networking issues.
                  # 2. The log processor crashes because it wants us to reload the config (after a hub update).
                  systemd.services.crowdsec.serviceConfig.RestartSec = lib.mkForce 5;
                };
            }
          )
          # Delete custom options to prevent invalid option error.
          (removeAttrs cfg (attrNames containerOpts.options))
        ]
      ) config.modules.containers;

      networking.bridges = mkIf (
        filter (name: hasAttr name constants.bridge) (attrNames config.modules.containers) != [ ]
      ) { ${bridgeName}.interfaces = [ ]; };

      systemd.services = lib.mapAttrs' (
        name: cfg:
        lib.nameValuePair "container@${name}" {
          serviceConfig = mkIf (hasAttr name constants.limits) (
            with constants.limits.${name};
            {
              MemoryHigh = mkDefault "${toString memory}G";
              CPUQuota = mkDefault "${toString (cpu * 100)}%";
            }
          );

          requires =
            map (name: "container@${name}.service") constants.containerDeps.${name} or [ ]
            ++ lib.optionals (hasAttr name constants.bridge) [ "${bridgeName}-netdev.service" ];
        }
      ) config.modules.containers;

      sops =
        let
          # Get the SOPS config for a container name and a secret config.
          getSopsConfig =
            container: _: secret:
            let
              value.${secret.name}.restartUnits = mkDefault [ "container@${container}.service" ];
            in
            if secret.sopsType == "secret" then { secrets = value; } else { templates = value; };
        in
        # Iterate over all containers, and for each container, get all required SOPS configs as a
        # merged attribute set, then merge them all at the end.
        mergeMapAttrs (
          name: cfg: mergeMapAttrs (getSopsConfig name) cfg.credentials
        ) config.modules.containers;

      # Define users and their corresponding groups for containers that define the host username for their root users.
      users.users = mergeMapAttrs (_: cfg: {
        ${cfg.username} = {
          uid = constants.uids.${cfg.username};
          group = cfg.username;
          isSystemUser = true;
        };
      }) containersWithUsernames;

      users.groups = mergeMapAttrs (_: cfg: {
        ${cfg.username}.gid = constants.uids.${cfg.username};
      }) containersWithUsernames;
    };
}
