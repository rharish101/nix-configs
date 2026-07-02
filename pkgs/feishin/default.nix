# SPDX-FileCopyrightText: 2023 Eelco Dolstra and the Nixpkgs/NixOS contributors
# SPDX-FileCopyrightText: 2026 Harish Rajagopal <harish.rajagopals@gmail.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later AND MIT

{
  lib,
  buildNpmPackage,
  dart-sass,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_10,
}:
let
  pname = "feishin";
  version = "1.13.0";

  src = fetchFromGitHub {
    owner = "jeffvli";
    repo = "feishin";
    tag = "v${version}";
    hash = "sha256-v6dWzEB1+IK4bHmDo8Rr5e0Xi3OWKcm+UPBmBiSfdZ0=";
  };
in
buildNpmPackage {
  inherit pname version;

  inherit src;

  npmConfigHook = pnpmConfigHook;
  npmBuildScript = "build:web";

  npmDeps = null;
  pnpmDeps = fetchPnpmDeps {
    inherit
      pname
      version
      src
      ;
    pnpm = pnpm_10;
    fetcherVersion = 3;
    hash = "sha256-zNOGJ24G0xcgsGK4DmbBm7d1PHTp7IJS+RTALGRtfDg=";
  };

  nativeBuildInputs = [ pnpm_10 ];

  postPatch = ''
    # release/app dependencies are installed on preConfigure
    substituteInPlace package.json \
      --replace-fail '"postinstall": "electron-builder install-app-deps",' ""
  '';

  preBuild = ''
    rm -r node_modules/.pnpm/sass-embedded-*

    test -d node_modules/.pnpm/sass-embedded@*
    dir="$(echo node_modules/.pnpm/sass-embedded@*)/node_modules/sass-embedded/dist/lib/src/vendor/dart-sass"
    mkdir -p "$dir"
    ln -s ${dart-sass}/bin/dart-sass "$dir"/sass
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -r out/web/* "$out"

    runHook postInstall
  '';

  meta = {
    description = "Full-featured Jellyfin, Navidrome, and OpenSubsonic Compatible Music Player";
    homepage = "https://github.com/jeffvli/feishin";
    changelog = "https://github.com/jeffvli/feishin/releases/tag/v${version}";
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.unix;
  };
}
