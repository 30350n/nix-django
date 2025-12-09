{
    pkgs,
    lib,
    uv2nix,
    pyproject-nix,
    pyproject-build-systems,
    ...
}:
lib.extendMkDerivation {
    constructDrv = pkgs.stdenvNoCC.mkDerivation;
    extendDrvArgs = finalAttrs: {
        name,
        version ? "0",
        nativeBuildInputs ? [],
        buildPhase ? "",
        doCheck ? true,
        checkPhase ? "",
        python ? pkgs.python3,
        skipInstall ? [
            "flake.lock"
            "flake.nix"
            "pyproject.toml"
            "uv.lock"
        ],
        installPhase ? "",
        staticRoot ? "staticfiles",
        ...
    }: {
        pname = name;
        inherit version;

        nativeBuildInputs = let
            workspace = uv2nix.lib.workspace.loadWorkspace {workspaceRoot = finalAttrs.src;};
            overlay = workspace.mkPyprojectOverlay {sourcePreference = "wheel";};
            pythonSet = (
                (pkgs.callPackage pyproject-nix.build.packages {inherit python;}).overrideScope (
                    lib.composeManyExtensions [
                        pyproject-build-systems.overlays.wheel
                        overlay
                    ]
                )
            );
        in
            [(pythonSet.mkVirtualEnv "${name}-env" workspace.deps.default)]
            ++ nativeBuildInputs;

        LD_LIBRARY_PATH = lib.makeLibraryPath nativeBuildInputs;

        buildPhase = let
            generate_secret_key = pkgs.writeText "generate_secret_key.py" ''
                from django.core.management.utils import get_random_secret_key
                print(get_random_secret_key())
            '';
        in
            ''
                python "${generate_secret_key}" > secret-key.txt
                python manage.py collectstatic --no-input
            ''
            + buildPhase;

        inherit doCheck;
        checkPhase =
            ''
                python manage.py test
                python manage.py check --deploy --fail-level WARNING
            ''
            + checkPhase;

        installPhase = let
            clean_static_sources = pkgs.writeText "clean_static_sources.py" ''
                import importlib, os, shutil
                settings = importlib.import_module(os.environ["DJANGO_SETTINGS_MODULE"])
                for _, source in settings.STATICFILES_DIRS:
                    shutil.rmtree(source, ignore_errors=True)
            '';
        in
            ''
                python manage.py shell < "${clean_static_sources}"
                find . -type d \( -name "__pycache__" -or -empty \) -exec rm -rf {} +

                rm ${lib.concatStringsSep " " skipInstall}

                mkdir -p $out/var/www/${name}
                cp -r ./* $out/var/www/${name}/
            ''
            + installPhase;

        passthru.staticRoot = "${placeholder "out"}/var/www/${staticRoot}";
    };
}
