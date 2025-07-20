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
}
