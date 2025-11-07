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
      useCollabora = config.modules.collabora.enable;
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
          { config, pkgs, ... }:
          {
            networking.firewall.allowedTCPPorts =
              with constants.ports;
              [ opencloud ] ++ lib.optional useCollabora wopi;

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
                OC_OIDC_ISSUER = with constants.domain; "https://${subdomains.auth}.${domain}";
                WEB_OIDC_CLIENT_ID = "9j4m5zcr5c51gJB6Qs50bChpQFWj3Htzc4wj3F2SMGVtIw-LhF3k8XpdXsWLP7YN";
                WEB_OIDC_SCOPE = "openid profile email groups";
                OC_EXCLUDE_RUN_SERVICES = "idp";
                PROXY_OIDC_ACCESS_TOKEN_VERIFY_METHOD = "none";
                PROXY_CSP_CONFIG_FILE_LOCATION = "/etc/opencloud/csp.yaml";
              }
              // lib.optionalAttrs useCollabora {
                COLLABORATION_APP_PRODUCT = "Collabora";
                COLLABORATION_APP_ADDR = with constants.domain; "https://${subdomains.cb}.${domain}";
                COLLABORATION_WOPI_SRC = with constants.domain; "https://${subdomains.wopi}.${domain}";
                COLLABORATION_HTTP_ADDR = "0.0.0.0:${toString constants.ports.wopi}";
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
                  (with constants.domain; "https://${subdomains.cb}.${domain}/")
                  "https://docs.opencloud.eu"
                ];
                img-src = [
                  "'self'"
                  "data:"
                  "blob:"
                  "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
                  (with constants.domain; "https://${subdomains.cb}.${domain}/")
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

            systemd.services.opencloud-collaboration = lib.mkIf useCollabora {
              description = "Start OpenCloud collaboration service";
              after = [ "opencloud.service" ];
              requires = [ "opencloud.service" ];
              wantedBy = [ "multi-user.target" ];
              environment = config.systemd.services.opencloud.environment;
              serviceConfig = config.systemd.services.opencloud.serviceConfig // {
                # XXX: This is to ensure that Collabora fully starts before this service starts.
                ExecStartPre = "${lib.getExe' pkgs.coreutils-full "sleep"} 10";
                ExecStart = "${lib.getExe config.services.opencloud.package} collaboration server";
              };
            };

            system.stateVersion = "25.11";
          };
      };

      systemd.services."container@opencloud" = lib.mkIf useCollabora {
        after = [ "container@collabora.service" ];
        requires = [ "container@collabora.service" ];
      };
    };
}
