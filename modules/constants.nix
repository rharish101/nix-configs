# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{
  # NOTE: Keys **must** use corresponding container short names, such that the first one depends on the second.
  bridges = {
    auth-caddy = {
      name = "br-auth-caddy";
      auth = {
        ip4 = "10.4.0.2";
        ip6 = "fc00::402";
      };
      caddy = {
        interface = "caddy-auth";
        ip4 = "10.4.0.1";
        ip6 = "fc00::401";
      };
    };
    auth-csec = {
      name = "br-auth-csec";
      auth = {
        interface = "auth-csec";
        ip4 = "10.4.4.1";
        ip6 = "fc00::441";
      };
      csec = {
        interface = "csec-auth";
        ip4 = "10.4.4.2";
        ip6 = "fc00::442";
      };
    };
    auth-ldap = {
      name = "br-auth-ldap";
      auth = {
        interface = "auth-ldap";
        ip4 = "10.4.3.1";
        ip6 = "fc00::431";
      };
      ldap = {
        ip4 = "10.4.3.2";
        ip6 = "fc00::432";
      };
    };
    auth-pg = {
      name = "br-auth-pg";
      auth = {
        interface = "auth-pg";
        ip4 = "10.4.2.1";
        ip6 = "fc00::421";
      };
      pg = {
        interface = "pg-auth";
        ip4 = "10.4.2.2";
        ip6 = "fc00::422";
      };
    };
    csec-caddy = {
      name = "br-caddy-csec";
      caddy = {
        interface = "caddy-csec";
        ip4 = "10.6.0.1";
        ip6 = "fc00::601";
      };
      csec = {
        ip4 = "10.6.0.2";
        ip6 = "fc00::601";
      };
    };
    csec-pg = {
      name = "br-csec-pg";
      csec = {
        interface = "csec-pg";
        ip4 = "10.6.1.1";
        ip6 = "fc00::611";
      };
      pg = {
        interface = "pg-csec";
        ip4 = "10.6.1.2";
        ip6 = "fc00::612";
      };
    };
    imm-caddy = {
      name = "br-caddy-imm";
      caddy = {
        interface = "caddy-imm";
        ip4 = "10.7.0.1";
        ip6 = "fc00::701";
      };
      imm = {
        ip4 = "10.7.0.2";
        ip6 = "fc00::702";
      };
    };
    imm-pg = {
      name = "br-imm-pg";
      imm = {
        interface = "imm-pg";
        ip4 = "10.7.1.1";
        ip6 = "fc00::711";
      };
      pg = {
        interface = "pg-imm";
        ip4 = "10.7.1.2";
        ip6 = "fc00::712";
      };
    };
    jf-caddy = {
      name = "br-caddy-jf";
      caddy = {
        interface = "caddy-jf";
        ip4 = "10.3.0.1";
        ip6 = "fc00::301";
      };
      jf = {
        ip4 = "10.3.0.2";
        ip6 = "fc00::302";
      };
    };
    jf-csec = {
      name = "br-csec-jf";
      jf = {
        interface = "jf-csec";
        ip4 = "10.3.1.1";
        ip6 = "fc00::311";
      };
      csec = {
        interface = "csec-jf";
        ip4 = "10.3.1.2";
        ip6 = "fc00::312";
      };
    };
    mc-caddy = {
      name = "br-caddy-mc";
      caddy = {
        interface = "caddy-mc";
        ip4 = "10.2.0.1";
        ip6 = "fc00::201";
      };
      mc = {
        ip4 = "10.2.0.2";
        ip6 = "fc00::202";
      };
    };
    mc-csec = {
      name = "br-csec-mc";
      csec = {
        interface = "csec-mc";
        ip4 = "10.2.1.1";
        ip6 = "fc00::211";
      };
      mc = {
        interface = "mc-csec";
        ip4 = "10.2.1.2";
        ip6 = "fc00::212";
      };
    };
    ldap-pg = {
      name = "br-ldap-pg";
      ldap = {
        interface = "ldap-pg";
        ip4 = "10.5.0.1";
        ip6 = "fc00::501";
      };
      pg = {
        interface = "pg-ldap";
        ip4 = "10.5.0.2";
        ip6 = "fc00::502";
      };
    };
    tr-caddy = {
      name = "br-caddy-tr";
      caddy = {
        interface = "caddy-tr";
        ip4 = "10.8.0.1";
        ip6 = "fc00::801";
      };
      tr = {
        ip4 = "10.8.0.2";
        ip6 = "fc00::802";
      };
    };
    tr-pg = {
      name = "br-pg-tr";
      tr = {
        interface = "tr-pg";
        ip4 = "10.8.1.1";
        ip6 = "fc00::811";
      };
      pg = {
        interface = "pg-tr";
        ip4 = "10.8.1.2";
        ip6 = "fc00::812";
      };
    };
    oc-caddy = {
      name = "br-caddy-oc";
      caddy = {
        interface = "caddy-oc";
        ip4 = "10.9.0.1";
        ip6 = "fc00::901";
      };
      oc = {
        ip4 = "10.9.0.2";
        ip6 = "fc00::902";
      };
    };
  };

  # NOTE: Keys for containers **must** correspond to their short names.
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
  };

  ports = {
    authelia = 9091;
    crowdsec = 20546; # Don't use defaut of 8080, since it's not unique.
    immich = 2283;
    jellyfin = 8096;
    lldap = 3890;
    minecraft = 25565; # Used for both Java (TCP) & Bedrock (UDP) editions
    opencloud = 9200;
    postgres = 5432;
    tandoor = 2113; # Don't use defaut of 8080, since it's not unique.
    wireguard = 51820;
  };

  # Constants related to my personal domain.
  domain = {
    domain = "rharish.dev";
    subdomains = {
      auth = "auth";
      imm = "photos";
      jf = "media";
      oc = "cloud";
      tr = "recipes";
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
  };
}
