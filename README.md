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
