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
        enabledDjangoServices = lib.filterAttrs (_: config: config.enable) config.services.django;
        gunicornSocket = name: "/run/gunicorn-${name}/gunicorn.sock";
    in {
        systemd.services = let
            migrationServices = lib.mapAttrs' (name: config:
                lib.nameValuePair "${name}-migrate" {
                    description = "${name} database migrations";
                    wantedBy = ["multi-user.target"];
                    after = ["network.target"];
                    serviceConfig = {
                        Type = "oneshot";
                        User = name;
                        Group = name;
                        WorkingDirectory = "${config.package}";
                    };
                    script = ''
                        ${config.package.pythonVirtualEnv}/bin/python manage.py migrate --no-input
                    '';
                })
            enabledDjangoServices;
            gunicornServices = builtins.mapAttrs (name: config: {
                description = "${name} django application";
                wantedBy = ["multi-user.target"];
                requires = ["${name}-migrate.service"];
                serviceConfig = {
                    Type = "notify";
                    NotifyAccess = "all";
                    User = name;
                    Group = name;
                    RuntimeDirectory = "gunicorn-${name}";
                    WorkingDirectory = config.package;
                    ExecReload = "kill -s HUP $MAINPID";
                    KillMode = "mixed";
                    PrivateTmp = true;
                };
                script = ''
                    ${config.package.pythonVirtualEnv}/bin/python -m gunicorn ${name}.wsgi \
                        --workers ${toString config.workers} \
                        --bind unix:${gunicornSocket name}
                '';
            })
            enabledDjangoServices;
        in
            migrationServices // gunicornServices;

        systemd.tmpfiles.rules =
            ["d /var/www 0755 root root - -"]
            ++ (
                lib.mapAttrsToList (name: _: "d /var/www/${name} 0750 ${name} ${name} - -")
                enabledDjangoServices
            );

        users.users = builtins.mapAttrs (name: _: {
            inherit name;
            group = name;
            isSystemUser = true;
        })
        enabledDjangoServices;
        users.groups = builtins.mapAttrs (name: _: {inherit name;}) enabledDjangoServices;

        services.caddy.virtualHosts = lib.mapAttrs' (name: config:
            lib.nameValuePair (lib.concatStringsSep ", " config.package.settings.ALLOWED_HOSTS) {
                extraConfig = ''
                    handle_path ${config.package.settings.STATIC_URL} {
                        root * ${config.package.settings.STATIC_ROOT}
                        file_server
                    }

                    reverse_proxy unix/${gunicornSocket name}
                '';
            }) (lib.filterAttrs (_: config: config.reverseProxy == "caddy") enabledDjangoServices);
    };
}
