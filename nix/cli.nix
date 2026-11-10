{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeBinaryWrapper,
  ripgrep,
  sysctl,
}:
let
  version = "0.0.7";

  # `@nautili/tui` is only a Node shim that locates and execs a prebuilt
  # binary from one of the `@nautili/nt-<platform>-<arch>` packages, so we
  # fetch the platform package directly and skip Node entirely.
  # @nautili/nt-linux-arm64 has no 0.0.4 release yet, so aarch64-linux is absent,
  # and nixpkgs 26.11 dropped x86_64-darwin.
  sources = {
    x86_64-linux = {
      npmName = "nt-linux-x64";
      hash = "sha512-zuj5aoMD+cZsQS4yCO46ThflYej6jEuenl6IXjw7W3+14nYF+1slkMVEh+/nSINA6EoEIuFW2Ba/aZytULuyjQ==";
    };
    aarch64-darwin = {
      npmName = "nt-darwin-arm64";
      hash = "sha512-SnsJpp/c8IPmGxkmI+9WiD8xr9VbFa8WscPP6/86e3WRrJ8EcmSxcLEtI7YELfFPHSMMgVMcBjLLXspDXgoXxg==";
    };
  };

  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "nautili: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "nautili";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@nautili/${source.npmName}/-/${source.npmName}-${version}.tgz";
    inherit (source) hash;
  };

  nativeBuildInputs = [ makeBinaryWrapper ] ++ lib.optional stdenv.hostPlatform.isLinux autoPatchelfHook;

  # The Bun single-file executable carries its JS bundle inside the
  # binary; stripping would destroy it.
  dontStrip = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 bin/nt $out/libexec/nautili/nt
    makeWrapper $out/libexec/nautili/nt $out/bin/nt \
      --set-default OPENCODE_DISABLE_AUTOUPDATE 1 \
      --prefix PATH : ${
        lib.makeBinPath (
          [ ripgrep ]
          # bun runs sysctl to detect if running on rosetta2
          ++ lib.optional stdenv.hostPlatform.isDarwin sysctl
        )
      }

    runHook postInstall
  '';

  meta = {
    description = "Nautili, DevZero's terminal coding agent";
    homepage = "https://www.nautili.ai";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames sources;
    mainProgram = "nt";
  };
}
