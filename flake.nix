{
  description = "MSI Thin GF63 12VF (i7-12650H + RTX 4060) — NixOS Ephemeral";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
    };
  };

  outputs = { self, nixpkgs, disko, impermanence, ... }@inputs: {
    nixosConfigurations.msi-thin = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        disko.nixosModules.disko
        impermanence.nixosModules.impermanence
        ./disko.nix
        ./hardware-configuration.nix
        ./configuration.nix
      ];
    };
  };
}