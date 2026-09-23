{
  description = "Wallpick — self-contained Quickshell wallpaper browser";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/6774f7bc253789b113a4f39285dc0fa100abeacc";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system (import nixpkgs { inherit system; }));
      pythonFor = pkgs: pkgs.python3.withPackages (ps: [ ps.pillow ]);
      runtimeFor = pkgs: [ (pythonFor pkgs) pkgs.awww pkgs.curl pkgs.cacert pkgs.coreutils pkgs.pywal ];
      cleanSource = builtins.path {
        path = ./.;
        name = "wallpick-source";
        filter = path: type:
          let name = builtins.baseNameOf path;
          in !(builtins.elem name [ "result" ".git" ".direnv" "__pycache__" ])
             && !(nixpkgs.lib.hasSuffix ".qsb" name);
      };
    in {
      packages = forAllSystems (system: pkgs:
        let
          wallpick = pkgs.stdenvNoCC.mkDerivation {
            pname = "wallpick";
            version = "0.2.0";
            src = cleanSource;
            nativeBuildInputs = [ pkgs.qt6.qtshadertools pkgs.makeWrapper ];
            dontWrapQtApps = true;
            dontConfigure = true;
            buildPhase = ''
              runHook preBuild
              qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 \
                -o src/shaders/liquidmetal.frag.qsb src/shaders/liquidmetal.frag
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/share/wallpick" "$out/bin" "$out/share/applications"
              cp -r src scripts "$out/share/wallpick/"
              cp scripts/run.sh "$out/bin/wallpick"
              chmod +x "$out/bin/wallpick"
              patchShebangs "$out/bin/wallpick"
              wrapProgram "$out/bin/wallpick" \
                --set WALLPICK_APP_DIR "$out/share/wallpick" \
                --set WALLPICK_PACKAGED 1 \
                --set WALLPICK_QS ${pkgs.quickshell}/bin/qs \
                --set WALLPICK_PYTHON ${pythonFor pkgs}/bin/python3 \
                --set-default SSL_CERT_FILE ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
                --prefix PATH : ${pkgs.lib.makeBinPath (runtimeFor pkgs)}
              cp packaging/wallpick.desktop "$out/share/applications/wallpick.desktop"
              substituteInPlace "$out/share/applications/wallpick.desktop" \
                --replace-fail "Exec=wallpick" "Exec=$out/bin/wallpick"
              runHook postInstall
            '';
            meta = {
              description = "Native Wayland wallpaper browser with bundled downloads and wallpaper backend";
              mainProgram = "wallpick";
              platforms = systems;
            };
          };
        in { default = wallpick; inherit wallpick; });

      apps = forAllSystems (system: pkgs: {
        default = { type = "app"; program = "${self.packages.${system}.default}/bin/wallpick";
          meta.description = "Browse, download and apply wallpapers"; };
      });

      checks = forAllSystems (system: pkgs: {
        backend = pkgs.runCommand "wallpick-backend-tests" {
          nativeBuildInputs = [ (pythonFor pkgs) ];
        } ''
          export HOME="$TMPDIR/home"
          mkdir -p "$HOME"
          export PYTHONDONTWRITEBYTECODE=1
          python3 ${cleanSource}/tests/actions_test.py
          touch "$out"
        '';
      });

      devShells = forAllSystems (system: pkgs: {
        default = pkgs.mkShell {
          packages = runtimeFor pkgs ++ [ pkgs.quickshell pkgs.qt6.qtdeclarative pkgs.qt6.qtshadertools ];
        };
      });

      nixosModules.default = { config, lib, pkgs, ... }: {
        options.programs.wallpick = {
          enable = lib.mkEnableOption "Wallpick wallpaper browser";
          package = lib.mkOption { type = lib.types.package; default = self.packages.${pkgs.stdenv.hostPlatform.system}.default; };
        };
        config = lib.mkIf config.programs.wallpick.enable {
          environment.systemPackages = [ config.programs.wallpick.package ];
        };
      };
      homeManagerModules.default = { config, lib, pkgs, ... }: {
        options.programs.wallpick = {
          enable = lib.mkEnableOption "Wallpick wallpaper browser";
          package = lib.mkOption { type = lib.types.package; default = self.packages.${pkgs.stdenv.hostPlatform.system}.default; };
        };
        config = lib.mkIf config.programs.wallpick.enable {
          home.packages = [ config.programs.wallpick.package ];
        };
      };
    };
}
