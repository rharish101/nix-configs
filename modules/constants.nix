# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{
  # IP addresses of containers inside the containers' bridge.
  # NOTE: Keys for containers **must** correspond to their names.
  bridge = {
    caddy-wg-client = {
      ip4 = "10.2.0.1";
      ip6 = "fc00::1";
    };
    minecraft = {
      ip4 = "10.2.0.2";
      ip6 = "fc00::2";
    };
    jellyfin = {
      ip4 = "10.2.0.3";
      ip6 = "fc00::3";
    };
    authelia = {
      ip4 = "10.2.0.4";
      ip6 = "fc00::4";
    };
    lldap = {
      ip4 = "10.2.0.5";
      ip6 = "fc00::5";
    };
    crowdsec-lapi = {
      ip4 = "10.2.0.6";
      ip6 = "fc00::6";
    };
    immich = {
      ip4 = "10.2.0.7";
      ip6 = "fc00::7";
    };
    tandoor = {
      ip4 = "10.2.0.8";
      ip6 = "fc00::8";
    };
    opencloud = {
      ip4 = "10.2.0.9";
      ip6 = "fc00::9";
    };
    collabora = {
      ip4 = "10.2.0.10";
      ip6 = "fc00::a";
    };
    vaultwarden = {
      ip4 = "10.2.0.11";
      ip6 = "fc00::b";
    };
    postgres = {
      ip4 = "10.2.0.12";
      ip6 = "fc00::c";
    };
  };

  # Container dependencies.
  # NOTE: Keys and values for containers **must** correspond to their names.
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
  };

  # Containers to which firewall must be open.
  # NOTE: Keys and values for containers **must** correspond to their names.
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
    lldap = [ "authelia" ];
    minecraft = [ "caddy-wg-client" ];
    opencloud = [ "caddy-wg-client" ];
    postgres = [
      "authelia"
      "crowdsec-lapi"
      "immich"
      "lldap"
      "tandoor"
      "vaultwarden"
    ];
    tandoor = [ "caddy-wg-client" ];
    vaultwarden = [ "caddy-wg-client" ];
  };

  # IP address pairs for various veth interfaces.
  veths = {
    caddy = {
      host = {
        ip4 = "10.1.0.1";
        ip6 = "fc00::0";
      };
      local = {
        ip4 = "10.1.0.2";
        ip6 = "fc00::1";
      };
    };
    tunnel = {
      server = {
        ip4 = "10.100.0.1";
        ip6 = "fc10::0";
      };
      client = {
        ip4 = "10.100.0.2";
        ip6 = "fc10::1";
      };
    };
  };

  # UIDs/GIDs that are multiples of 65536 are chosen a/c to how systemd-nspawn chooses one for user namespacing.
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
  };

  ports = {
    authelia = 9091;
    collabora = 9980;
    crowdsec = 20546; # Don't use defaut of 8080, since it's not unique.
    immich = 2283;
    jellyfin = 8096;
    lldap = 3890;
    minecraft = 25565; # Used for both Java (TCP) & Bedrock (UDP) editions
    opencloud = 9200;
    postgres = 5432;
    tandoor = 2113; # Don't use defaut of 8080, since it's not unique.
    wireguard = 51820;
    vaultwarden = 6062; # Don't use default of 8000, since it's not unique.
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
}
