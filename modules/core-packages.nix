# modules/core-packages.nix
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    git
  ];
}
