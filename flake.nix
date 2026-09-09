{
  description = "Botille — AI containment tool running agents in a rootless Podman container";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    serena = {
      url = "github:oraios/serena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-substituters = [
      "https://delirium-systems.cachix.org"
      "https://cache.numtide.com"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "delirium-systems.cachix.org-1:66ovNl3TR96B++WAvUK0U6nmrejRLR3DYoFzQbKnPHs="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  outputs =
    inputs:
    let
      cacheData = import ./nix/caches.nix;

      # Core builder - wraps all per-system derivations so that both
      # apps.default and lib.mkApp share the same logic.
      mkBotille =
        {
          system,
          extraHomeManagerModules ? [ ],
          extraContainerModules ? [ ],
        }:
        let
          # The container image and everything inside it are Linux
          # derivations.  On Darwin they are built for the matching Linux
          # architecture and run inside the podman machine VM.
          containerSystem = { "aarch64-darwin" = "aarch64-linux"; }.${system} or system;

          pkgs = import inputs.nixpkgs {
            system = containerSystem;
            config.allowUnfree = true;
          };

          # Host-side packages, used only for the launcher script.
          hostPkgs =
            if containerSystem == system then
              pkgs
            else
              import inputs.nixpkgs {
                inherit system;
                config.allowUnfree = true;
              };

          isDarwin = hostPkgs.stdenv.isDarwin;

          home = "/home/user";

          containerConfig =
            (pkgs.lib.evalModules {
              modules = [
                (import ./nix/container-options.nix { inherit home; })
              ]
              ++ extraContainerModules;
            }).config;

          renderPodmanFlags = import ./nix/render-podman-flags.nix { inherit (pkgs) lib; };
          podmanFlags = renderPodmanFlags containerConfig;

          containerPackages = import ./nix/packages.nix {
            inherit pkgs;
            llmAgentsPkgs = inputs.llm-agents.packages.${containerSystem};
            homeManagerPkg = inputs.home-manager.packages.${containerSystem}.home-manager;
            serenaPkg = inputs.serena.packages.${containerSystem}.default;
          };

          # Home-manager activation package (built at Nix time, activated at container start).
          # extraHomeManagerModules are appended last so they can override base settings.
          hmActivation =
            (inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                ./nix/home.nix
              ]
              ++ extraHomeManagerModules;
            }).activationPackage;

          # Generate nix.conf from shared cache data
          cacheLines = builtins.concatStringsSep "" (
            map (c: "extra-substituters = ${c.url}\nextra-trusted-public-keys = ${c.key}\n") cacheData.caches
          );
          nixConf = pkgs.writeTextDir "etc/nix/nix.conf" ''
            build-users-group =
            max-jobs = auto
            auto-optimise-store = true
            use-xdg-base-directories = true
            experimental-features = nix-command flakes
            ${cacheLines}
          '';

          # Registration info for all image store paths (nix-store --load-db format)
          imageClosureInfo = pkgs.closureInfo {
            rootPaths = containerPackages ++ [
              pkgs.dockerTools.fakeNss
              nixConf
              hmActivation
            ];
          };

          # closureInfo doesn't include itself in its own registration.
          # Without this, the GC root (which points to imageClosureInfo)
          # is dangling from Nix's perspective and nix store gc ignores it,
          # collecting unreferenced leaf paths like nixConf and fakeNss.
          closureInfoReg = pkgs.closureInfo {
            rootPaths = [ imageClosureInfo ];
          };

          entrypoint = import ./nix/entrypoint.nix {
            inherit
              pkgs
              imageClosureInfo
              closureInfoReg
              home
              hmActivation
              ;
          };

          container = import ./nix/container.nix {
            inherit
              pkgs
              containerPackages
              nixConf
              entrypoint
              home
              ;
          };

          # The firewall hook scripts run on the container host.  On Darwin
          # that host is the podman machine VM, which cannot see the Mac's
          # Nix store, so the hooks are skipped there (see launcher.nix).
          launcher = import ./nix/launcher.nix {
            pkgs = hostPkgs;
            inherit container podmanFlags;
            hooksDir = if isDarwin then null else (import ./nix/firewall.nix { inherit pkgs; }).hooksDir;
            inherit (containerConfig) hostPorts allowLan;
          };

        in
        {
          inherit
            pkgs
            hostPkgs
            container
            launcher
            ;
          app = {
            type = "app";
            program = pkgs.lib.getExe launcher;
          };
        };

    in
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem =
        { system, ... }:
        let
          built = mkBotille { inherit system; };
          inherit (built) hostPkgs container launcher;
          tests = import ./nix/tests.nix {
            pkgs = hostPkgs;
            inherit launcher;
          };
        in
        {
          packages = {
            inherit container;
            default = container;
          };

          apps.default = built.app;

          checks = {
            statix = hostPkgs.runCommand "statix" { nativeBuildInputs = [ hostPkgs.statix ]; } ''
              statix check ${inputs.self}
              touch $out
            '';

            deadnix = hostPkgs.runCommand "deadnix" { nativeBuildInputs = [ hostPkgs.deadnix ]; } ''
              deadnix --fail ${inputs.self}
              touch $out
            '';
          }
          // hostPkgs.lib.optionalAttrs hostPkgs.stdenv.isLinux tests;

          formatter = hostPkgs.nixfmt;
        };

      # Flake library - customise the home-manager configuration baked into
      # the container image without forking this repository.
      #
      # Usage: create a wrapper flake.nix in your project:
      #
      #   {
      #     inputs.botille.url = "github:delirium-systems/botille";
      #     outputs = { self, botille }: {
      #       apps.x86_64-linux.default = botille.lib.mkApp {
      #         system = "x86_64-linux";
      #         extraHomeManagerModules = [
      #           { programs.git.userEmail = "you@example.com"; }
      #           ./extra-hm.nix
      #         ];
      #         extraContainerModules = [
      #           { volumes = [ "/tmp/claude-dir:/home/user/.config/claude/:Z" ]; }
      #         ];
      #       };
      #     };
      #   }
      #
      # Note: customised images are not in the delirium-systems cachix cache
      # and will be built locally on first use.  `system` may also be a
      # Darwin system: the image is then built for the matching Linux
      # architecture and run inside the podman machine VM (on macOS,
      # customised images must be built with scripts/mac-build-image.sh,
      # since a Mac cannot build Linux derivations).
      flake.lib = {
        mkApp =
          {
            system,
            extraHomeManagerModules ? [ ],
            extraContainerModules ? [ ],
          }:
          (mkBotille { inherit system extraHomeManagerModules extraContainerModules; }).app;
      };
    };
}
