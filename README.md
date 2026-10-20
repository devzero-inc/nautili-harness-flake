# nautili-harness-flake

A Nix flake for [Nautili](https://www.nautili.ai), DevZero's coding agent. It
packages the prebuilt releases:

| Package | What it is | Command |
|---|---|---|
| `nautili` (default) | The terminal client, from the `@nautili/tui` npm release | `nt` |
| `nautili-desktop` | The desktop app, from releases.nautili.ai | `nautili-desktop` |

Supported systems: `x86_64-linux` and `aarch64-darwin`.

Both packages turn off the built-in auto-updater (it could not replace files in
the Nix store anyway); update by updating the flake input.

## Try it

```bash
# Terminal client
nix run github:devzero-inc/nautili-harness-flake

# Pass arguments after --
nix run github:devzero-inc/nautili-harness-flake -- login

# Desktop app
nix run github:devzero-inc/nautili-harness-flake#nautili-desktop
```

## Use it in your own flake

Add the input, and have it follow your nixpkgs so you don't pull in a second one:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nautili.url = "github:devzero-inc/nautili-harness-flake";
    nautili.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nautili, ... }: {
    # NixOS
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [
            nautili.packages.${pkgs.stdenv.hostPlatform.system}.nautili
            nautili.packages.${pkgs.stdenv.hostPlatform.system}.nautili-desktop
          ];
        })
      ];
    };
  };
}
```

The same `nautili.packages.${system}.<name>` works in a home-manager
`home.packages`, a nix-darwin `environment.systemPackages` or a dev shell:

```nix
devShells.x86_64-linux.default = pkgs.mkShell {
  packages = [ nautili.packages.x86_64-linux.nautili ];
};
```

### Overlay

To get `pkgs.nautili` and `pkgs.nautili-desktop` instead, apply the overlay:

```nix
{
  nixpkgs.overlays = [ nautili.overlays.default ];
  environment.systemPackages = with pkgs; [ nautili nautili-desktop ];
}
```

## Updating to a new release

Each package pins a version and one hash per system:

- `nix/cli.nix`: the `@nautili/nt-<platform>-<arch>` tarballs on npm. The hash
  is the tarball's `dist.integrity`:
  `npm view @nautili/nt-linux-x64@<version> dist.integrity`
- `nix/desktop.nix`: the files under
  `https://releases.nautili.ai/stable/desktop/<version>/`. Take the hex digest
  from that directory's `SHA256SUMS` and convert it:
  `nix hash convert --hash-algo sha256 --to sri <hex>`

Then check that both packages still build: `nix build .#nautili .#nautili-desktop`.
