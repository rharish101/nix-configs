# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.opencloud = {
    enable = lib.mkEnableOption "Enable OpenCloud";
    dataDir = lib.mkOption {
      description = "The OpenCloud directory path";
      type = lib.types.str;
    };
  };
  config =
    let
      constants = import ../constants.nix;
    in
    lib.mkIf (config.modules.opencloud.enable && config.modules.caddy-wg-client.enable) {
      modules.containers.opencloud = {
        shortName = "oc";
        username = "opencloud";
        allowInternet = true;
        credentials.env.name = "opencloud";

        bindMounts.data = with config.modules.opencloud; {
          hostPath = dataDir;
          mountPoint = "/var/lib/opencloud";
          isReadOnly = false;
        };

        config =
          { config, ... }:
          {
            networking.firewall.allowedTCPPorts = [ constants.ports.opencloud ];

            services.opencloud = {
              enable = true;
              address = "0.0.0.0";
              port = constants.ports.opencloud;
              url = with constants.domain; "https://${subdomains.oc}.${domain}";
              environmentFile = "/run/credentials/@system/env";
              environment = {
                OC_INSECURE = "true";
                PROXY_TLS = "false";
                SMTP_HOST = constants.smtp.host;
                SMTP_PORT = toString constants.smtp.port;
                SMTP_SENDER = with constants.domain; "OpenCloud <${subdomains.oc}@${domain}>";
                SMTP_USERNAME = constants.smtp.username;
                SMTP_TRANSPORT_ENCRYPTION = "true";
                SMTP_INSECURE = "false";
                STORAGE_USERS_ID_CACHE_STORE = "nats-js-kv";
                OC_OIDC_ISSUER = with constants.domain; "https://${subdomains.auth}.${domain}";
                WEB_OIDC_CLIENT_ID = "9j4m5zcr5c51gJB6Qs50bChpQFWj3Htzc4wj3F2SMGVtIw-LhF3k8XpdXsWLP7YN";
                WEB_OIDC_SCOPE = "openid profile email groups";
                OC_EXCLUDE_RUN_SERVICES = "idp";
                PROXY_USER_OIDC_CLAIM = "preferred_username";
                PROXY_USER_CS3_CLAIM = "username";
                PROXY_OIDC_ACCESS_TOKEN_VERIFY_METHOD = "none";
                PROXY_AUTOPROVISION_ACCOUNTS = "false";
                PROXY_CSP_CONFIG_FILE_LOCATION = "/etc/opencloud/csp.yaml";
              };
              settings.csp.directives = {
                child-src = [ "'self'" ];
                connect-src = [
                  "'self'"
                  "blob:"
                  "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
                  (with constants.domain; "https://${subdomains.auth}.${domain}/")
                ];
                default-src = [ "'none'" ];
                font-src = [ "'self'" ];
                frame-ancestors = [ "'self'" ];
                frame-src = [
                  "'self'"
                  "blob:"
                  "https://embed.diagrams.net"
                ];
                img-src = [
                  "'self'"
                  "data:"
                  "blob:"
                  "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
                ];
                manifest-src = [ "'self'" ];
                media-src = [ "'self'" ];
                object-src = [
                  "'self'"
                  "blob:"
                ];
                script-src = [
                  "'self'"
                  "'unsafe-inline'"
                  "'unsafe-eval'"
                ];
                style-src = [
                  "'self'"
                  "'unsafe-inline'"
                ];
              };
            };

            # NOTE: This is created when running OpenCloud with an empty state directory.
            # You have to then copy /etc/opencloud/opencloud.yaml to the state directory.
            environment.etc."opencloud/opencloud.yaml" = {
              user = config.services.opencloud.user;
              group = config.services.opencloud.group;
              source = "${config.services.opencloud.stateDir}/opencloud.yaml";
            };

            system.stateVersion = "25.11";
          };
      };
    };
}
