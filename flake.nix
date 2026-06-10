{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };


  };

  outputs = { self, nixpkgs, nixos-hardware, home-manager, zen-browser, claude-code, ... }:
  let
    user = import ./user.nix;
  in {
    nixosConfigurations.${user.hostname} = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit user zen-browser claude-code; };
      modules = [
        ./configuration.nix

        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit user claude-code; };
          home-manager.users.${user.username} = {
            imports = [ ./home.nix ];
          };
        }
      ] ++ nixpkgs.lib.optionals (user.hardware == "framework") [
        nixos-hardware.nixosModules.framework-16-7040-amd
      ];
    };
  };
}
