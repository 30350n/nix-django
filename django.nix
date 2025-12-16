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
                    workers = 1;
                };
            });
        };

    config = let
        enabledDjangoServices = lib.filterAttrs (name: config: config.enable) config.django;
        gunicornSocket = name: "/run/gunicorn-${name}.sock";
    in {
        systemd.services = let
            migrationServices = lib.mapAttrs' (name: config:
                lib.nameValuePair "${name}_migrate" {
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
                        python manage.py migrate --no-input
                    '';
                })
            enabledDjangoServices;
            gunicornServices = builtins.mapAttrs (name: config: {
                description = "${name} django application";
                wantedBy = ["multi-user.target"];
                after = ["${name}_migrate"];
                serviceConfig = {
                    Type = "notify";
                    NotifyAccess = "main";
                    User = name;
                    Group = name;
                    WorkingDirectory = config.package;
                    ExecReload = "kill -s HUP $MAINPID";
                    KillMode = "mixed";
                    PrivateTmp = true;
                };
                script = ''
                    python -m gunicorn ${name}.wsgi \
                        --workers ${toString config.workers} \
                        --bind unix:${gunicornSocket name}
                '';
            })
            enabledDjangoServices;
        in
            migrationServices ++ gunicornServices;

        users.users = builtins.mapAttrs (name: config: {
            inherit name;
            value = {
                group = name;
                isSystemUser = true;
            };
        })
        enabledDjangoServices;
        users.groups = builtins.mapAttrs (name: config: {inherit name;}) enabledDjangoServices;

        services.caddy.virtualHosts = lib.mapAttrs' (name: config:
            lib.nameValuePair (lib.concatStringsSep "," config.package.settings.ALLOWED_HOSTS) {
                extraConfig = ''
                    handle_path ${config.package.settings.STATIC_URL} {
                        root * ${config.package.settings.STATIC_ROOT}
                        file_server
                    }

                    reverse_proxy unix/${gunicornSocket name}
                '';
            }) (lib.filterAttrs (name: config: config.reverseProxy == "caddy"));
    };
}
