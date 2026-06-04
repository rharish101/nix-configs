# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

rec {
  ip6Subnets =
    let
      global = "2a01:4f8:1c1e:d4ed:";
    in
    {
      caddy-wg-client = "${global}2::";
      caddy-wg-server = "${global}1::";
      tunnel = "${global}10::";
    };

  # IPv4 private addressing for container-to-container communication in each containers' bridge
  # Includes IPv6 GUAs for containers that need to connect to the internet.
  # Addresses are kept static to avoid running a DHCP server.
  # NOTE: Keys for containers **must** correspond to their names.
  bridges = {
    caddy =
      let
        ip6Prefix = ip6Subnets.caddy-wg-client;
      in
      {
        caddy-wg-client = {
          ip4 = "10.2.0.1";
          ip6 = "${ip6Prefix}1";
        };
        minecraft = {
          ip4 = "10.2.0.2";
          ip6 = "${ip6Prefix}2";
        };
        jellyfin = {
          ip4 = "10.2.0.3";
          ip6 = "${ip6Prefix}3";
        };
        authelia = {
          ip4 = "10.2.0.4";
          ip6 = "${ip6Prefix}4";
        };
        lldap = {
          ip4 = "10.2.0.5";
        };
        crowdsec-lapi = {
          ip4 = "10.2.0.6";
          ip6 = "${ip6Prefix}6";
        };
        immich = {
          ip4 = "10.2.0.7";
          ip6 = "${ip6Prefix}7";
        };
        tandoor = {
          ip4 = "10.2.0.8";
          ip6 = "${ip6Prefix}8";
        };
        opencloud = {
          ip4 = "10.2.0.9";
          ip6 = "${ip6Prefix}9";
        };
        collabora = {
          ip4 = "10.2.0.10";
          ip6 = "${ip6Prefix}a";
        };
        vaultwarden = {
          ip4 = "10.2.0.11";
          ip6 = "${ip6Prefix}b";
        };
        postgres = {
          ip4 = "10.2.0.12";
        };
      };

    qb = {
      qbittorrent.ip4 = "10.2.1.1";
      postgres.ip4 = "10.2.1.2";
    };
  };

  # Container dependencies for a container's systemd unit.
  # Also used for determining the default gateway, for containers who need internet access.
  # NOTE: Keys and list values for containers **must** correspond to their names.
  containerDeps = {
    authelia = [
      "caddy-wg-client"
      "crowdsec-lapi"
      "lldap"
      "postgres"
    ];
    collabora = [ "caddy-wg-client" ];
    crowdsec-lapi = [
      "caddy-wg-client"
      "postgres"
    ];
    immich = [
      "caddy-wg-client"
      "postgres"
    ];
    jellyfin = [
      "caddy-wg-client"
      "crowdsec-lapi"
    ];
    lldap = [ "postgres" ];
    minecraft = [
      "caddy-wg-client"
      "crowdsec-lapi"
    ];
    opencloud = [ "caddy-wg-client" ];
    tandoor = [
      "caddy-wg-client"
      "postgres"
    ];
    vaultwarden = [
      "caddy-wg-client"
      "postgres"
    ];
    qbittorrent = [ "postgres" ];
  };

  # List of containers to which a container's firewall must be open.
  # Used to determine which IPs can access which ports (via firewallOpen in base.nix)
  # NOTE: Keys and list values for containers **must** correspond to their names.
  firewallOpen = {
    authelia = [ "caddy-wg-client" ];
    collabora = [ "caddy-wg-client" ];
    crowdsec-lapi = [
      "authelia"
      "caddy-wg-client"
      "jellyfin"
      "minecraft"
    ];
    immich = [ "caddy-wg-client" ];
    jellyfin = [ "caddy-wg-client" ];
    lldap = [
      "authelia"
      "jellyfin"
    ];
    minecraft = [ "caddy-wg-client" ];
    opencloud = [ "caddy-wg-client" ];
    postgres = [
      "authelia"
      "crowdsec-lapi"
      "immich"
      "lldap"
      "qbittorrent"
      "tandoor"
      "vaultwarden"
    ];
    tandoor = [ "caddy-wg-client" ];
    vaultwarden = [ "caddy-wg-client" ];
  };

  # IPv4 private addresses for host and container veth pairs for reverse proxy container
  # networking
  # Includes IPv6 GUAs for containers that need to connect to the internet.
  veths = {
    caddy-wg-client = {
      host.ip4 = "10.1.0.1";
      local.ip4 = "10.1.0.2";
    };
    caddy-wg-server = {
      host = {
        ip4 = "10.1.0.1";
        ip6 = "${ip6Subnets.caddy-wg-server}1";
      };
      local = {
        ip4 = "10.1.0.2";
        ip6 = "${ip6Subnets.caddy-wg-server}2";
      };
    };
    qbittorrent = {
      host.ip4 = "10.1.1.1";
      local.ip4 = "10.1.1.2";
    };
    tunnel = {
      server = {
        ip4 = "10.100.0.1";
        ip6 = "${ip6Subnets.tunnel}1";
      };
      client = {
        ip4 = "10.100.0.2";
        ip6 = "${ip6Subnets.tunnel}2";
      };
    };
  };

  # UIDs/GIDs that are multiples of 65536 are chosen a/c to how systemd-nspawn chooses one for user
  # namespacing.
  # Only used for containers who need to access the filesystem, as the file/directory owner in the
  # host must be fixed. Containers without these UIDs use "pick" for private user namespace mapping
  # NOTE: Keys for containers **must** correspond to their usernames.
  uids = {
    minecraft = 65536 * 9;
    caddywg = 65536 * 10;
    jellyfin = 65536 * 11;
    postgres = 65536 * 13;
    crowdsec = 65536 * 15;
    immich = 65536 * 16;
    tandoor = 65536 * 17;
    opencloud = 65536 * 18;
    vaultwarden = 65536 * 19;
    qbittorrent = 65536 * 20;
  };

  ports = {
    authelia = 9091;
    collabora = 9980;
    crowdsec = 20546; # Avoid default 8080 to prevent conflicts
    immich = 2283;
    jellyfin = 8096;
    lldap = 3890;
    minecraft = 25565; # Used for both Java (TCP) & Bedrock (UDP) editions
    opencloud = 9200;
    postgres = 5432;
    tandoor = 2113; # Avoid default 8080 to prevent conflicts
    wireguard = 51820;
    vaultwarden = 6062; # Avoid default 8000 to prevent conflicts
  };

  # Constants related to my personal domain.
  domain = {
    domain = "rharish.dev";
    subdomains = {
      authelia = "auth";
      bentopdf = "pdf";
      collabora = "office";
      immich = "photos";
      jellyfin = "media";
      opencloud = "cloud";
      tandoor = "recipes";
      vaultwarden = "vault";
    };
    ldapBaseDn = "dc=rharish,dc=dev";
  };

  # SMTP configuration for sending emails.
  smtp = {
    host = "smtp.gmail.com";
    port = 587;
    username = "harish.rajagopals@gmail.com";
  };

  # Resource limits
  # These are initialized from the minimum requirements in their docs.
  # CPU: #(virtual) threads, memory: GiB
  # NOTE: Keys for containers **must** correspond to their names.
  limits = {
    authelia = {
      cpu = 2;
      memory = 2;
    };
    caddy-wg-client = {
      cpu = 1;
      memory = 1;
    };
    caddy-wg-server = {
      cpu = 1;
      memory = 1;
    };
    collabora = {
      cpu = 1;
      memory = 1;
    };
    immich = {
      cpu = 4;
      memory = 8;
    };
    jellyfin = {
      cpu = 4;
      memory = 4;
    };
    minecraft = {
      cpu = 6;
      memory = 9;
    };
    opencloud = {
      cpu = 1;
      memory = 1;
    };
    vaultwarden = {
      cpu = 1;
      memory = 1;
    };
  };

  # DNS provider.
  nameservers = [
    "1.1.1.1"
    "1.0.0.1"
    "2606:4700:4700::1111"
    "2606:4700:4700::1001"
  ];
}
