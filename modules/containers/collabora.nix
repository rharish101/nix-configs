# SPDX-FileCopyrightText: 2025 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later

{ config, lib, ... }:
{
  options.modules.collabora.enable = lib.mkEnableOption "Enable Collabora Online";
  config =
    let
      constants = import ../constants.nix;
    in
    lib.mkIf (config.modules.collabora.enable && config.modules.caddy-wg-client.enable) {
      modules.containers.collabora = {
        shortName = "cb";
        allowInternet = true;
        extraFlags = [ "--notify-ready=yes" ]; # Notify that the container is ready only after the init process is ready (i.e. ready.target).

        config =
          { pkgs, ... }:
          {
            networking.firewall.allowedTCPPorts = [ constants.ports.collabora ];

            services.collabora-online = {
              enable = true;
              port = constants.ports.collabora;
              package = pkgs.collabora-online.overrideAttrs (old: {
                postInstall = old.postInstall + ''
                  ${lib.getExe' pkgs.openssh "ssh-keygen"} -t rsa -N "" -m PEM -f $out/etc/coolwsd/proof_key
                '';
              });
              settings = {
                user_interface.mode = "tabbed";
                ssl = {
                  enable = false;
                  termination = true;
                };
                storage.wopi.host = with constants.domain; "https://${subdomains.wopi}.${domain}";
                per_document.max_concurrency = constants.limits.collabora.cpu;
                net.content_security_policy = with constants.domain; "frame-ancestors ${subdomains.oc}.${domain}";
              };
            };

            # Make sure that the container reports itself as ready only after Collabora is ready.
            systemd.targets.ready = {
              after = [ "coolwsd.service" ];
              requires = [ "coolwsd.service" ];
            };

            system.stateVersion = "25.11";
          };
      };
    };
}
