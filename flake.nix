{
  description = ".NET & Powershell Development Environment";

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://devenv.cachix.org"
      "https://pre-commit-hooks.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "pre-commit-hooks.cachix.org-1:Pkk3Panw5AW24TOv6kz3PvLhlH8puAsJTBbOPmBo7Rc="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devenv.url = "github:cachix/devenv";
    treefmt.url = "github:numtide/treefmt-nix";
  };

  outputs =
    inputs@{
      flake-parts,
      devenv,
      treefmt,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      {
        ...
      }:
      {
        imports = [
          devenv.flakeModule
          treefmt.flakeModule
        ];

        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "x86_64-darwin"
          "aarch64-darwin"
        ];

        perSystem =
          {
            pkgs,
            lib,
            ...
          }:
          {
            packages.compiler = pkgs.buildDotnetModule {
              pname = "Compiler";
              version = "0.0.1";

              src = ./.;

              projectFile = "./scripts.sln";
              nugetDeps = ./src/Compiler/deps.json;

              buildInputs = [ ];
              runtimeDeps = [ ];

              dotnet-sdk = pkgs.dotnetCorePackages.sdk_10_0;
              dotnet-runtime = pkgs.dotnetCorePackages.runtime_10_0;

              executables = [ "Compiler" ];
            };

            treefmt = {
              programs = {
                actionlint.enable = true;
                deadnix.enable = true;
                nixfmt.enable = true;
                statix.enable = true;
                mdformat.enable = true;
              };

              settings.global.excludes = [
                "docs/**"
              ];
            };

            devenv.shells.default = {
              # Fixes https://github.com/cachix/devenv/issues/528
              containers = lib.mkForce { };

              packages = with pkgs; [
                powershell
                nixfmt-rfc-style
                nuget-to-json
              ];

              languages = {
                nix.enable = true;
                dotnet = {
                  enable = true;
                  package = pkgs.dotnet-sdk_10.overrideAttrs (oldAttrs: {
                    postBuild =
                      (oldAttrs.postBuild or '''')
                      + ''
                        for i in $out/sdk/*; do
                            i=$(basename $i)
                            mkdir -p $out/metadata/workloads/''${i/-*}
                            touch $out/metadata/workloads/''${i/-*}/userlocal
                        done
                      '';
                  });
                };
              };

              git-hooks = {
                hooks = {
                  nil.enable = true;
                  actionlint.enable = true;
                  deadnix.enable = true;
                  statix.enable = true;
                  nixfmt-rfc-style.enable = true;
                  flake-checker.enable = true;
                  editorconfig-checker.enable = true;
                };
              };
            };
          };
      }
    );
}
