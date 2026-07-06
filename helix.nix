{ pkgs, helix-steel, vim-hx, lib ? pkgs.lib, ... }:
let
  defaultRuntimeDir = pkgs.runCommand "helix-steel-default-runtime" { } ''
    cp -r --no-preserve=mode ${helix-steel}/runtime $out
    rm -rf $out/grammars $out/queries
  '';

  # nixpkgs builds grammars as .so but the helix-steel binary on macOS expects .dylib.
  # Create a grammars directory with .dylib symlinks pointing at the existing .so files.
  # See: https://github.com/helix-editor/helix/pull/14982
  helixRuntime = pkgs.helix.runtime;
  grammarsDylib = pkgs.runCommand "helix-grammars-dylib" { } ''
    mkdir -p $out
    for f in ${helixRuntime}/grammars/*.so; do
      name=$(basename "$f" .so)
      ln -s "$f" "$out/$name.dylib"
    done
  '';

  helix-steel-unwrapped = pkgs.rustPlatform.buildRustPackage {
    pname = "helix-steel-unwrapped";
    version = "steel-event-system";

    src = helix-steel;

    cargoLock = {
      lockFile = "${helix-steel}/Cargo.lock";
      outputHashes = {
        # steel-core, steel-derive, steel-doc, etc. all come from the same git rev
        "steel-core-0.8.2" = "sha256-TP1hmlju7h7ce0dnSKuIMk7XK5kcloqiyR+sxumNsQk=";
      };
    };

    nativeBuildInputs = with pkgs; [ installShellFiles ];

    env = {
      HELIX_DISABLE_AUTO_GRAMMAR_BUILD = "1";
      HELIX_DEFAULT_RUNTIME = defaultRuntimeDir;
    };

    postInstall = ''
      installShellCompletion contrib/completion/hx.{bash,fish,zsh}
    '';

    doCheck = false;
    doInstallCheck = false;

    meta = {
      description = "Post-modern modal text editor (Steel plugin fork)";
      homepage = "https://github.com/mattwparas/helix";
      license = lib.licenses.mpl20;
      mainProgram = "hx";
    };
  };

  helix-steel-pkg = pkgs.helix.override {
    helix-unwrapped = helix-steel-unwrapped;
  };
in
{
  # Symlink vim.hx Scheme files into Steel's cogs directory (its module root)
  # https://helix-plugins.com/
  home.file = builtins.listToAttrs (
    map (name: {
      name = ".local/share/steel/cogs/vim-hx/${name}";
      value = { source = "${vim-hx}/${name}"; };
    }) [
      "init.scm"
      "change-motions.scm"
      "delete-motions.scm"
      "key-emulation.scm"
      "normal-motions.scm"
      "utils.scm"
      "visual-motions.scm"
      "yank-motions.scm"
    ]
  ) // {
    ".config/helix/init.scm".text = ''
      (require "vim-hx/init.scm")
      (set-vim-keybindings!)
    '';

    ".config/helix/runtime/grammars".source = grammarsDylib;
  };

  programs.helix = {
    enable = true;
    package = helix-steel-pkg;

    extraPackages = with pkgs; [
      gopls
      basedpyright
      ruff
    ];

    settings = {
      theme = "catppuccin_mocha";
      editor = {
        line-number = "relative";
        cursor-shape = {
          insert = "bar";
          normal = "block";
        };
        auto-save = true;
        bufferline = "multiple";
        statusline = {
          left = [ "mode" "spinner" "file-name" "read-only-indicator" "file-modification-indicator" ];
          right = [ "diagnostics" "selections" "position" "file-encoding" "file-type" ];
        };
        lsp = {
          display-inlay-hints = true;
          display-messages = true;
        };
        indent-guides.render = true;
      };
    };

    languages = {
      language = [
        {
          name = "go";
          auto-format = true;
          language-servers = [ "gopls" ];
        }
        {
          name = "python";
          auto-format = true;
          language-servers = [ "basedpyright" "ruff" ];
          formatter = {
            command = "ruff";
            args = [ "format" "--stdin-filename" "file.py" "-" ];
          };
        }
      ];

      language-server = {
        basedpyright = {
          command = "basedpyright-langserver";
          args = [ "--stdio" ];
          config.basedpyright.analysis = {
            typeCheckingMode = "standard";
            autoImportCompletions = true;
          };
        };
        ruff = {
          command = "ruff";
          args = [ "server" ];
        };
      };
    };
  };
}
