{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-22.11";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils, ... }: {
    lib = { writeRubyApplication = import ./write-ruby-application.nix; };
  };
}
