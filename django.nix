{
    config,
    lib,
    ...
}: {
    options.services.django = with lib;
        mkOption {
            type = types.attrsOf (types.submodule {
                options = {
                    enable = mkEnableOption "enable";
                    package = mkOption {type = types.package;};
                    reverseProxy = mkOption {type = types.nullOr (types.enum ["caddy"]);};
                    workers = mkOption {
                        type = types.int;
                        default = 1;
                    };
                };
            });
        };

    config = let
        djangoServices =
            lib.filterAttrs (_: djangoConfig: djangoConfig.enable) config.services.django;
        gunicornSocket = name: "/run/gunicorn-${name}/gunicorn.sock";
        python = djangoConfig: "${djangoConfig.package.pythonVirtualEnv}/bin/python";
    in {
        systemd.services = let
            migrationServices = lib.mapAttrs' (name: djangoConfig:
                lib.nameValuePair "${name}-migrate" {
                    description = "${name} database migrations";
                    wantedBy = ["multi-user.target"];
                    after = ["network.target"];
                    serviceConfig = {
                        Type = "oneshot";
                        User = name;
                        Group = name;
                        WorkingDirectory = djangoConfig.package.appDirectory;
                    };
                    environment.DATA_DIR = "/var/www/${name}";
                    script = ''
                        ${python djangoConfig} manage.py migrate --no-input
                    '';
                })
            djangoServices;
            gunicornServices = builtins.mapAttrs (name: djangoConfig: {
                description = "${name} django application";
                wantedBy = ["multi-user.target"];
                requires = ["${name}-migrate.service"];
                serviceConfig = {
                    Type = "notify";
                    NotifyAccess = "all";
                    User = name;
                    Group = name;
                    RuntimeDirectory = "gunicorn-${name}";
                    WorkingDirectory = djangoConfig.package.appDirectory;
                    ExecReload = "kill -s HUP $MAINPID";
                    KillMode = "mixed";
                    PrivateTmp = true;
                };
                environment.DATA_DIR = "/var/www/${name}";
                script = ''
                    ${python djangoConfig} -m gunicorn ${name}.wsgi \
                        --workers ${toString djangoConfig.workers} \
                        --bind unix:${gunicornSocket name}
                '';
            })
            djangoServices;
        in
            migrationServices // gunicornServices;

        systemd.tmpfiles.rules =
            ["d /var/www 0755 root root - -"]
            ++ (
                lib.mapAttrsToList (name: _: "d /var/www/${name} 0750 ${name} ${name} - -")
                djangoServices
            );

        users.users = builtins.mapAttrs (name: _: {
            inherit name;
            group = name;
            isSystemUser = true;
        })
        djangoServices;
        users.groups = builtins.mapAttrs (name: _: {inherit name;}) djangoServices;

        services.caddy.virtualHosts = lib.mapAttrs' (name: djangoConfig: let
            settings = djangoConfig.package.settings;
        in
            lib.nameValuePair (lib.concatStringsSep ", " settings.ALLOWED_HOSTS) {
                extraConfig = ''
                    handle_path ${settings.STATIC_URL} {
                        root * ${settings.STATIC_ROOT}
                        file_server
                    }

                    reverse_proxy unix/${gunicornSocket name}
                '';
                logFormat = ''
                    output file ${config.services.caddy.logDir}/access-${name}.log
                '';
            })
        (lib.filterAttrs (_: djangoConfig: djangoConfig.reverseProxy == "caddy") djangoServices);
    };
}
