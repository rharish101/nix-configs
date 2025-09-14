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
  inherit (builtins)
    attrNames
    elemAt
    hasAttr
    length
    mapAttrs
    ;
  inherit (lib)
    escapeRegex
    filterAttrs
    mapAttrs'
    mapAttrsToList
    mkDefault
    mkIf
    mkMerge
    mkOption
    nameValuePair
    pipe
    types
    ;

  # Options for each container.
  containerOpts = {
    freeformType = types.attrs; # Allow using `containers.<name>` options automatically.
    options = {
      shortName = mkOption {
        description = "Short name for container, used for network/bridge interface names";
        type = types.strMatching "^[a-z]{2,5}$";
      };
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
      allowInternet = lib.mkEnableOption "Allow this container to access the internet";
    };
  };

  # DNS provider.
  nameserver = "1.1.1.1";
in
{
  options.modules.containers = mkOption {
    description = "A set of NixOS container configurations with custom defaults";
    type = with lib.types; attrsOf (submodule containerOpts);
    default = { };
  };

  config =
    let
      constants = import ../constants.nix;

      # Get the list of all bridges used by a container such that there is at least one other container in that bridge.
      getBridges =
        let
          # Whether the key for a bridge matches the given container's short name and also another specified container's short name.
          # This iterates over all specified containers to see if the key matches its short name.
          isBridgeValid =
            shortName: key: _:
            builtins.any (
              cfg: key == "${shortName}-${cfg.shortName}" || key == "${cfg.shortName}-${shortName}"
            ) (lib.attrValues config.modules.containers);
        in
        cfg: if cfg ? "shortName" then filterAttrs (isBridgeValid cfg.shortName) constants.bridges else [ ];

      # Map an attribute set and use `lib.mkMerge` to merge them.
      mergeMapAttrs = func: attr: mkMerge (mapAttrsToList func attr);

      # Containers that have set a username.
      containersWithUsernames = filterAttrs (_: cfg: cfg.username != null) config.modules.containers;
    in
    {
      containers = mapAttrs (
        name: cfg:
        # Merge such that the specified config can override defaults if needed.
        mkMerge [
          (
            # Calculate default container config.
            let
              # List of valid bridges for this container.
              bridges = getBridges cfg;

              # The key in the bridge constants corresponding to the bridge to be used as this container's default network interface.
              # This filters bridges by checking if the "interface" key is defined for each config.
              # Then, it chooses the first element, but only if exactly one such bridge is found.
              mainBridge =
                let
                  mainBridges = attrNames (filterAttrs (_: value: !(value.${cfg.shortName} ? "interface")) bridges);
                in
                if length mainBridges == 1 then elemAt mainBridges 0 else null;

              # The container's local IP addresses for this container's default network interface.
              # It also has a flag denoting whether to add the subnet mask.
              # This depends on whether the interface is a network bridge or not (IDK why).
              localAddresses =
                if cfg ? "shortName" && hasAttr cfg.shortName constants.veths then
                  constants.veths.${cfg.shortName}.local // { subnet = false; }
                else if cfg ? "shortName" && mainBridge != null then
                  bridges.${mainBridge}.${cfg.shortName} // { subnet = true; }
                else
                  null;

              # The host's IP addresses for this container's default network interface.
              hostAddresses =
                if cfg ? "shortName" && hasAttr cfg.shortName constants.veths then
                  constants.veths.${cfg.shortName}.host
                else
                  null;
            in
            {
              privateNetwork = mkDefault true;
              privateUsers = mkDefault (if isNull cfg.username then "pick" else constants.uids.${cfg.username});
              autoStart = mkDefault true;

              hostBridge = mkIf (mainBridge != null) (mkDefault bridges.${mainBridge}.name);
              hostAddress = mkIf (hostAddresses != null) (mkDefault hostAddresses.ip4);
              hostAddress6 = mkIf (hostAddresses != null) (mkDefault hostAddresses.ip6);
              localAddress = mkIf (localAddresses != null) (
                mkDefault (localAddresses.ip4 + (if localAddresses.subnet then "/24" else ""))
              );
              localAddress6 = mkIf (localAddresses != null) (
                mkDefault (localAddresses.ip6 + (if localAddresses.subnet then "/112" else ""))
              );

              # Iterate over all valid bridges for this container (that aren't the main bridge) and form the interface config.
              extraVeths = mapAttrs' (
                _: value:
                nameValuePair value.${cfg.shortName}.interface {
                  hostBridge = mkDefault value.name;
                  localAddress = mkDefault "${value.${cfg.shortName}.ip4}/24";
                  localAddress6 = mkDefault "${value.${cfg.shortName}.ip6}/112";
                }
              ) (filterAttrs (key: _: key != mainBridge) bridges);

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
                      matches =
                        if isNull mainBridge then
                          [ ]
                        else
                          lib.remove null (
                            builtins.match "${escapeRegex cfg.shortName}-(.+)|(.+)-${escapeRegex cfg.shortName}" mainBridge
                          );
                      gateway = if length matches == 1 then bridges.${mainBridge}.${elemAt matches 0} else null;
                    in
                    mkIf (cfg.allowInternet && !isNull mainBridge) {
                      defaultGateway = {
                        address = mkDefault gateway.ip4;
                        interface = mkDefault "eth0";
                      };
                      defaultGateway6 = {
                        address = mkDefault gateway.ip6;
                        interface = mkDefault "eth0";
                      };
                      nameservers = [ nameserver ];
                    };

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

      networking.bridges =
        let
          # Get the configs for all network bridges used by a container.
          getBridgesForContainer =
            _: cfg:
            mapAttrs' (_: bridge: {
              name = bridge.name;
              value.interfaces = mkDefault [ ];
            }) (getBridges cfg);
        in
        mergeMapAttrs getBridgesForContainer config.modules.containers;

      systemd.services = mapAttrs' (
        name: cfg:
        nameValuePair "container@${name}" {
          serviceConfig = mkIf (hasAttr name constants.limits) (
            with constants.limits.${name};
            {
              MemoryHigh = mkDefault "${toString memory}G";
              CPUQuota = mkDefault "${toString (cpu * 100)}%";
            }
          );

          requires =
            let
              # Check if the given container is a dependency of the current container.
              # The container whose short name is first depends on the container whose short name is second.
              isContainerDep =
                _: cfg': builtins.elem "${cfg.shortName}-${cfg'.shortName}" (attrNames constants.bridges);

              # The attribute set of container configs of all containers that the current container depends on.
              deps = filterAttrs isContainerDep config.modules.containers;
            in
            map (name: "container@${name}.service") (attrNames deps);
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
