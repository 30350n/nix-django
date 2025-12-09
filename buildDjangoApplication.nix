{
    pkgs,
    uv2nix,
    pyproject-nix,
    pyproject-build-systems,
    ...
}:
pkgs.lib.extendMkDerivation {
    constructDrv = pkgs.stdenvNoCC.mkDerivation;
    extendDrvArgs = finalAttrs: {
        name,
        version ? "0",
        nativeBuildInputs ? [],
        buildPhase ? "",
        doCheck ? true,
        checkPhase ? "",
        python ? pkgs.python3,
        skipInstall ? [],
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
                    pkgs.lib.composeManyExtensions [
                        pyproject-build-systems.overlays.wheel
                        overlay
                    ]
                )
            );
        in
            [(pythonSet.mkVirtualEnv "${name}-env" workspace.deps.default)]
            ++ nativeBuildInputs;

        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath nativeBuildInputs;

        buildPhase = let
            generate_secret_key = pkgs.writeText "generate_secret_key.py" ''
                from django.core.management.utils import get_random_secret_key
                print(get_random_secret_key())
            '';
            clean_static_sources = pkgs.writeText "clean_static_sources.py" ''
                import importlib, os, shutil
                settings = importlib.import_module(os.environ["DJANGO_SETTINGS_MODULE"])
                for _, source in settings.STATICFILES_DIRS:
                    shutil.rmtree(source, ignore_errors=True)
            '';
        in
            ''
                python "${generate_secret_key}" > secret-key.txt
                python manage.py collectstatic --no-input
                python manage.py shell < "${clean_static_sources}"
                find . -type d \( -name "__pycache__" -or -empty \) -exec rm -rf {} +
            ''
            + buildPhase;

        inherit doCheck;
        checkPhase =
            ''
                python manage.py test
                python manage.py check --deploy --fail-level WARNING
                find . -type d -name "__pycache__" -exec rm -rf {} +
            ''
            + checkPhase;

        installPhase = let
            skipInstallArgs = pkgs.lib.concatStringsSep " " (
                map (file: "-not -name \"${file}\"") ([
                    "flake.lock"
                    "flake.nix"
                    "pyproject.toml"
                    "uv.lock"
                ]
                ++ skipInstall)
            );
        in
            ''
                mkdir -p $out/var/www/${name}
                find . ${skipInstallArgs} -exec cp -r --parents {} $out/var/www/${name}/ \;
            ''
            + installPhase;

        passthru.staticRoot = "${placeholder "out"}/var/www/${staticRoot}";
    };
}
