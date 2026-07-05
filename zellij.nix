{ pkgs, ... }:

{
  home.file.".config/zellij/config.kdl".source = ./zellij.kdl;
}
