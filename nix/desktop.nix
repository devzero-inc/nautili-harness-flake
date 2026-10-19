{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  dpkg,
  unzip,
  makeShellWrapper,
  wrapGAppsHook3,
  ripgrep,
  alsa-lib,
  at-spi2-atk,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libdrm,
  libgbm,
  libGL,
  libnotify,
  libsecret,
  libuuid,
  libxkbcommon,
  nspr,
  nss,
  pango,
  systemd,
  libx11,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  libxcb,
}:
let
  version = "0.0.4";

  # The versioned directory is immutable; the flat copies in stable/desktop/
  # (and the www.nautili.dev/download/stable/* redirects) move with each release.
  # Hashes come from https://releases.nautili.ai/stable/desktop/<version>/SHA256SUMS.
  sources = {
    x86_64-linux = {
      file = "nautili-desktop-linux-amd64.deb";
      hash = "sha256-ToFQNssqqo9456q9ecDKldJbCz7ZKHrhza02zamBuP4=";
    };
    aarch64-darwin = {
      file = "nautili-desktop-mac-arm64.zip";
      hash = "sha256-U2Z/nWHSt2psSp/qI2yROUIfQoNdW9lIyH0+f+vjp4o=";
    };
  };

  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "nautili-desktop: unsupported system ${stdenv.hostPlatform.system}");

  appId = "io.devzero.nautir";
in
stdenv.mkDerivation {
  pname = "nautili-desktop";
  inherit version;

  src = fetchurl {
    url = "https://releases.nautili.ai/stable/desktop/${version}/${source.file}";
    inherit (source) hash;
  };

  nativeBuildInputs = [
    makeShellWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    autoPatchelfHook
    dpkg
    # Only for the GSettings schemas and gdk-pixbuf loaders; the wrapper below
    # picks up gappsWrapperArgs.
    wrapGAppsHook3
  ]
  ++ lib.optional stdenv.hostPlatform.isDarwin unzip;

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    alsa-lib
    at-spi2-atk
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libdrm
    libgbm
    libnotify
    libsecret
    libuuid
    libxkbcommon
    nspr
    nss
    pango
    (lib.getLib stdenv.cc.cc)
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxcb
  ];

  # Chromium dlopens these rather than linking them.
  runtimeDependencies = lib.optionals stdenv.hostPlatform.isLinux [
    (lib.getLib systemd)
    libGL
    libnotify
    libsecret
  ];

  sourceRoot = ".";
  unpackCmd = lib.optionalString stdenv.hostPlatform.isLinux "dpkg-deb -x $curSrc .";

  dontWrapGApps = true;
  # Both Electron and the bundled Bun CLI (resources/nautili-cli) carry
  # payloads that stripping would corrupt.
  dontStrip = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    mkdir -p $out/opt $out/share
    cp -r opt/Nautili $out/opt/nautili-desktop
    cp -r usr/share/{applications,icons,metainfo} $out/share/

    # electron-updater reads this to find the release feed; an update could not
    # replace files in the Nix store anyway.
    rm $out/opt/nautili-desktop/resources/app-update.yml

    substituteInPlace $out/share/applications/${appId}.desktop \
      --replace-fail "Exec=/opt/Nautili/${appId}" "Exec=nautili-desktop"
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    mkdir -p $out/Applications
    cp -r *.app $out/Applications/
    app=$(echo $out/Applications/*.app)
    makeShellWrapper "$app/Contents/MacOS/$(basename "$app" .app)" $out/bin/nautili-desktop \
      --set-default OPENCODE_DISABLE_AUTOUPDATE 1 \
      --prefix PATH : ${lib.makeBinPath [ ripgrep ]}
  ''
  + ''
    runHook postInstall
  '';

  # wrapGAppsHook3 only fills gappsWrapperArgs during fixup. A shell wrapper,
  # not the binary one wrapGAppsHook3 brings, so the ozone flags get expanded.
  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    makeShellWrapper $out/opt/nautili-desktop/${appId} $out/bin/nautili-desktop \
      "''${gappsWrapperArgs[@]}" \
      --set-default OPENCODE_DISABLE_AUTOUPDATE 1 \
      --prefix PATH : ${lib.makeBinPath [ ripgrep ]} \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"
  '';

  meta = {
    description = "Nautili Desktop, DevZero's AI coding agent";
    homepage = "https://www.nautili.ai";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames sources;
    mainProgram = "nautili-desktop";
  };
}
