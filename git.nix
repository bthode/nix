# Shared git config. user.name/user.email are set per-host in flake.nix
# (under the same programs.git.settings tree, merged with what's here).
{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    signing.signByDefault = false;
    lfs.enable = true;

    settings = {
      alias = {
        a = "add";
        alias = "config --get-regexp ^alias\\.";
        blamer = "blame -w -C -C -C";
        bn = "rev-parse --abbrev-ref HEAD";
        c = "commit";
        cheat = "!cheat git";
        checkout = "help";
        d = "diff";
        extend = "commit --amend --no-edit";
        f = "fetch --all -p";
        ff = "pull --ff-only";
        fix-upstream = "branch --set-upstream-to=origin/$(git symbolic-ref --short HEAD)";
        fza = "!git ls-files -m -o --exclude-standard | fzf --print0 -m | xargs -0 -t -o git add";
        l = "cherry -v master";
        lastmerge = "rev-list --merges -n1 HEAD";
        lg = "log --graph -n 30 --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
        parent = ''!git show-branch | grep '*' | grep -v "$(git rev-parse --abbrev-ref HEAD)" | head -n1 | sed 's/.*\[\(.*\)\].*/\1/' | sed 's/[\^~].*//' #'';
        rb = "pull --rebase";
        reword = "commit --amend";
        rmt = "config --get remote.origin.url";
        root = "!cd \"$(git rev-parse --show-toplevel)\"";
        s = "status";
        scrap = "!git reset -q --hard HEAD && git clean -qfd";
        unstage = "restore --staged";
        vi = "!f() { vim $(git diff --name-only | head -n 1); }; f";
      };

      diff.tool = "vimdiff";
      pull.rebase = true;
      credential.helper = "cache --timeout=86400";
      gpg.program = "gpg";
      branch.sort = "-committerdate";
      color = {
        diff = "auto";
        status = "auto";
        branch = "auto";
        editor = "nvim";
        interactive = "auto";
        ui = true;
        pager = true;
      };
      column.ui = "auto";
      fetch.prune = true;
      rebase.autosquash = true;
      push = {
        default = "current";
        autoSetupRemote = true;
      };
      log.abbrevCommit = true;
      format.pretty = "oneline";
      core = {
        pager = "delta";
        excludesfile = "${config.home.homeDirectory}/.gitignore_global";
        autocrlf = "input";
      };
      interactive.diffFilter = "delta --color-only";
      delta = {
        navigate = true;
        features = "zebra-light";
        "side-by-side" = true;
      };
      merge.conflictstyle = "diff3";
      diff.colorMoved = "default";
      init.defaultBranch = "master";

      rerere.enabled = true;
      "url \"ssh://git@github.com/\"" = {
        insteadOf = "https://github.com/";
      };
    };
  };
}
