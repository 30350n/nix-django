# nix-django

## Packaging Django Applications

To package a Django application, create a `flake.nix` file in your project repository, add `nix-django` as an input and build your package using `buildDjangoApplication`.

`flake.nix` example:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-django = {
      url = "github:30350n/nix-django";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    nix-django,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    packages.${system}.default = (nix-django.lib pkgs).buildDjangoApplication {
      name = ...;
      src = ./.;

      # optional: additional required nativeBuildInputs
      # nativeBuildInputs = with pkgs; [
      #     ... 
      # ];
    };
  };
}
```

### Application Requirements

#### `SECRET_KEY`

The `SECRET_KEY` setting has to be read from a `secret-key.txt` file in the current working directory (when not in `DEBUG` mode).

`settings.py` example:

```python
if DEBUG:
    SECRET_KEY = "django-insecure-..."
else:
    SECRET_KEY = Path("secret-key.txt").read_text().strip()
```

#### `SILENCED_SYSTEM_CHECKS`

By default the `buildDjangoApplication` builder cleans up all static file source directories after collecting static files, to reduce derivation size.
The subsequent invocation of `python manage.py check` will produce a bunch of `staticfiles.W004` warnings, which causes the `check` step to fail.

To circumvent this the warning has to be ignored in `settings.py`:

```python
SILENCED_SYSTEM_CHECKS = ["staticfiles.W004"]
```

Alternatively the previously described behavior can be disabled by disabling the `cleanStaticSources` setting:

```nix
buildDjangoApplication {
  ...

  cleanStaticSources = false;
}
```

#### `STATIC_ROOT`

The `STATIC_ROOT` directory has to be set relative to the project root.
