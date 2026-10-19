{
  description = "Nautili, DevZero's coding agent: the CLI (@nautili/tui) and desktop app, packaged from their prebuilt releases";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      forEachSystem = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      mkApp = drv: {
        type = "app";
        program = lib.getExe drv;
      };
    in
    {
      overlays.default = final: _prev: {
        nautili = final.callPackage ./nix/cli.nix { };
        nautili-desktop = final.callPackage ./nix/desktop.nix { };
      };

      packages = forEachSystem (pkgs: rec {
        nautili = pkgs.callPackage ./nix/cli.nix { };
        nautili-desktop = pkgs.callPackage ./nix/desktop.nix { };
        default = nautili;
      });

      apps = forEachSystem (
        pkgs:
        let
          packages = self.packages.${pkgs.stdenv.hostPlatform.system};
        in
        rec {
          nautili = mkApp packages.nautili;
          nautili-desktop = mkApp packages.nautili-desktop;
          default = nautili;
        }
      );
    };
}
