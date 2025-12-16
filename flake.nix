{
    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

        pyproject-nix = {
            url = "github:pyproject-nix/pyproject.nix";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        uv2nix = {
            url = "github:pyproject-nix/uv2nix";
            inputs.pyproject-nix.follows = "pyproject-nix";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        pyproject-build-systems = {
            url = "github:pyproject-nix/build-system-pkgs";
            inputs.pyproject-nix.follows = "pyproject-nix";
            inputs.uv2nix.follows = "uv2nix";
            inputs.nixpkgs.follows = "nixpkgs";
        };
    };

    outputs = {self, ...} @ inputs: {
        lib = {
            lib ? pkgs.lib,
            pkgs,
            ...
        }: {
            buildDjangoApplication = import ./buildDjangoApplication.nix (
                {inherit lib pkgs;}
                // inputs
            );
        };
        nixosModules.nix-django = ./django.nix;
    };
}
