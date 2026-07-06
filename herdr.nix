{ pkgs, ... }:

{
  home.file.".config/herdr/config.toml" = {
    source = ./herdr-config.toml;
    force = true;
  };
}
