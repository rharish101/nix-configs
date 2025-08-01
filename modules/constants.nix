# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{
  bridges = {
    auth-caddy = {
      name = "br-auth-caddy";
      auth = {
        ip4 = "10.4.0.2";
        ip6 = "fc00::32";
      };
      caddy = {
        interface = "caddy-auth";
        ip4 = "10.4.0.1";
        ip6 = "fc00::31";
      };
    };
    auth-csec = {
      name = "br-auth-csec";
      auth = {
        interface = "auth-csec";
        ip4 = "10.4.4.1";
        ip6 = "fc00::39";
      };
      csec = {
        interface = "csec-auth";
        ip4 = "10.4.4.2";
        ip6 = "fc00::3a";
      };
    };
    auth-ldap = {
      name = "br-auth-ldap";
      auth = {
        interface = "auth-ldap";
        ip4 = "10.4.3.1";
        ip6 = "fc00::37";
      };
      ldap = {
        ip4 = "10.4.3.2";
        ip6 = "fc00::38";
      };
    };
    auth-pg = {
      name = "br-auth-pg";
      auth = {
        interface = "auth-pg";
        ip4 = "10.4.2.1";
        ip6 = "fc00::35";
      };
      pg = {
        interface = "pg-auth";
        ip4 = "10.4.2.2";
        ip6 = "fc00::36";
      };
    };
    auth-redis = {
      name = "br-auth-redis";
      auth = {
        interface = "auth-redis";
        ip4 = "10.4.1.1";
        ip6 = "fc00::33";
      };
      redis = {
        interface = "redis-auth";
        ip4 = "10.4.1.2";
        ip6 = "fc00::34";
      };
    };
    caddy-csec = {
      name = "br-caddy-csec";
      caddy = {
        interface = "caddy-csec";
        ip4 = "10.6.0.1";
        ip6 = "fc00::51";
      };
      csec = {
        ip4 = "10.6.0.2";
        ip6 = "fc00::52";
      };
    };
    caddy-imm = {
      name = "br-caddy-imm";
      caddy = {
        interface = "caddy-imm";
        ip4 = "10.7.0.1";
        ip6 = "fc00::61";
      };
      imm = {
        ip4 = "10.7.0.2";
        ip6 = "fc00::62";
      };
    };
    caddy-mc = {
      name = "br-caddy-mc";
      caddy = {
        interface = "caddy-mc";
        ip4 = "10.2.0.1";
        ip6 = "fc00::11";
      };
      mc = {
        ip4 = "10.2.0.2";
        ip6 = "fc00::12";
      };
    };
    csec-mc = {
      name = "br-csec-mc";
      csec = {
        interface = "csec-mc";
        ip4 = "10.2.1.1";
        ip6 = "fc00::13";
      };
      mc = {
        interface = "mc-csec";
        ip4 = "10.2.1.2";
        ip6 = "fc00::14";
      };
    };
    csec-pg = {
      name = "br-csec-pg";
      csec = {
        interface = "csec-pg";
        ip4 = "10.6.1.1";
        ip6 = "fc00::53";
      };
      pg = {
        interface = "pg-csec";
        ip4 = "10.6.1.2";
        ip6 = "fc00::54";
      };
    };
    imm-pg = {
      name = "br-imm-pg";
      imm = {
        interface = "imm-pg";
        ip4 = "10.7.1.1";
        ip6 = "fc00::63";
      };
      pg = {
        interface = "pg-imm";
        ip4 = "10.7.1.2";
        ip6 = "fc00::64";
      };
    };
    imm-redis = {
      name = "br-imm-redis";
      imm = {
        interface = "imm-redis";
        ip4 = "10.7.2.1";
        ip6 = "fc00::65";
      };
      redis = {
        interface = "redis-imm";
        ip4 = "10.7.2.2";
        ip6 = "fc00::66";
      };
    };
    ldap-pg = {
      name = "br-ldap-pg";
      ldap = {
        interface = "ldap-pg";
        ip4 = "10.5.0.1";
        ip6 = "fc00::41";
      };
      pg = {
        interface = "pg-ldap";
        ip4 = "10.5.0.2";
        ip6 = "fc00::42";
      };
    };
  };

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
  uids = {
    minecraft = 65536 * 9;
    caddywg = 65536 * 10;
    authelia = 65536 * 12;
    postgres = 65536 * 13;
    crowdsec = 65536 * 15;
    immich = 65536 * 16;
  };

  ports = {
    authelia = 9091;
    crowdsec = 20546; # Don't use defaut of 8080, since it's not unique.
    immich = 2283;
    lldap = 3890;
    minecraft = 25565; # Used for both Java (TCP) & Bedrock (UDP) editions
    postgres = 5432;
    wireguard = 51820;
  };

  # Constants related to my personal domain.
  domain = {
    domain = "rharish.dev";
    subdomains = {
      auth = "auth";
      imm = "photos";
    };
    ldapBaseDn = "dc=rharish,dc=dev";
  };

  # Resource limits
  # CPU: #(virtual) threads, memory: GiB
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
    immich = {
      cpu = 4;
      memory = 6;
    };
    minecraft = {
      cpu = 6;
      memory = 8;
    };
  };
}
