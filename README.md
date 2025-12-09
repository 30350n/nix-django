# nix-django

## Usage Example

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
    packages.${system}.default = (nix-django.lib pkgs).buildDjangoApplication rec {
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
