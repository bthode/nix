{
  description = "Shared nix-darwin + home-manager flake for work and personal machines";

  inputs = {
    # Nix Packages collection
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "flake:nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "flake:home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.darwin.follows = "nix-darwin";
    };

    nix-secrets = {
      url = "git+ssh://git@github.com/bthode/nix-secrets.git";
      # TODO: Doesn't seem like either of these are working
      # url = "git@gh-deploykey:bthode/nix-secrets.git";
      flake = false; # This is just a source, not a flake
    };

    herdr.url = "github:ogulcancelik/herdr";

    helix-steel = {
      url = "github:mattwparas/helix/steel-event-system";
      flake = false;
    };

    vim-hx = {
      url = "github:mattwparas/vim.hx";
      flake = false;
    };

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      homebrew-core,
      homebrew-cask,
      agenix,
      nix-secrets,
      herdr,
      helix-steel,
      vim-hx,
      fenix,
      ...
    }@inputs:
    let
      system = "aarch64-darwin";

      mkHost =
        {
          hostname,
          username,
          isWork,
          gitUserEmail,
        }:
        nix-darwin.lib.darwinSystem {
          inherit system;

          # Pass inputs to the modules so they can be accessed later
          specialArgs = { inherit inputs; };

          # List of modules to import
          modules = [
            home-manager.darwinModules.home-manager
            inputs.agenix.darwinModules.default
            inputs.nix-homebrew.darwinModules.nix-homebrew
            # Your main configuration, defined inline
            (
              {
                config,
                pkgs,
                lib,
                inputs,
                ...
              }:

              {

                age.identityPaths = [ "/etc/agenix/keys/agenix_key" ];

                age.secrets = lib.optionalAttrs isWork {
                  npmrc = {
                    file = "${inputs.nix-secrets}/npmrc-smithrx.age";
                    path = "/Users/${username}/.npmrc";
                    owner = username;
                    group = "staff";
                    mode = "0600";
                  };

                  forge-envrc = {
                    file = "${inputs.nix-secrets}/forge-envrc.age";
                    path = "/Users/${username}/Code/forge/.envrc";
                    owner = username;
                    group = "staff";
                    mode = "0600";
                  };

                  github-pat = {
                    file = "${inputs.nix-secrets}/github-pat.age";
                    path = "/Users/${username}/.github-pat";
                    owner = username;
                    group = "staff";
                    mode = "0600";
                  };

                  automation-envrc = {
                    file = "${inputs.nix-secrets}/automation-envrc.age";
                    path = "/Users/${username}/Code/automation/.envrc";
                    owner = username;
                    group = "staff";
                    mode = "0600";
                  };
                };

                nix.package = pkgs.nix;

                nix.settings = {
                  experimental-features = "nix-command flakes";
                  trusted-users = [ "root" ] ++ lib.optionals isWork [ username ];
                };

                # Set the state version for darwin for backwards compatibility.
                system.stateVersion = 6;

                # List packages installed system-wide.
                environment.systemPackages =
                  (with pkgs; [
                    age
                    ast-grep
                    bruno
                    buf
                    bun
                    claude-code
                    curl
                    delta
                    docker
                    docker-compose
                    eza # https://mynixos.com/home-manager/options/programs.eza
                    gitleaks
                    glow
                    grpcurl
                    hyperfine
                    inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
                    herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
                    jetbrains.idea
                    jless
                    just
                    maccy
                    neovim
                    nil
                    nixd
                    nodejs_22
                    openssl
                    posting # Modern API client that lives in your terminal.
                    pre-commit
                    protobuf
                    tree
                    uv
                    vim
                    wget
                    xan # Tool for csv viewing/manipulation

                    # Rust toolchain via fenix
                    (fenix.packages.${pkgs.stdenv.hostPlatform.system}.stable.withComponents [
                      "cargo"
                      "clippy"
                      "rust-src"
                      "rustc"
                      "rustfmt"
                      "rust-analyzer"
                    ])
                  ])
                  ++ lib.optionals isWork (
                    with pkgs;
                    [
                      acli
                      awscli2
                      goose
                      jdk25
                      jmeter
                      rancher
                      rectangle
                      redis
                      teleport
                    ]
                  )
                  ++ lib.optionals (!isWork) (
                    with pkgs;
                    [
                      brave
                      google-chrome
                    ]
                  );
                nixpkgs.config.allowUnfree = true;

                nix-homebrew = {
                  enable = true;
                  enableRosetta = true;
                  user = username;
                  taps = {
                    "homebrew/homebrew-core" = inputs.homebrew-core;
                    "homebrew/homebrew-cask" = inputs.homebrew-cask;
                  };
                  mutableTaps = false;
                };

                homebrew = {
                  enable = true;

                  brews = [
                    "displayplacer"
                    "mas"
                  ]
                  ++ lib.optionals isWork [ "libpq" ];

                  casks = [
                    "apidog"
                    "emacs-app"
                    "ghostty"
                    "spotify"
                    "sublime-text"
                    "tableplus"
                    "yubico-authenticator"
                    # See if this is being broken by MDM
                    # https://github.com/pqrs-org/Karabiner-Elements/issues/3941
                    # https://github.com/pqrs-org/Karabiner-Elements/issues/3941#issuecomment-3223503610
                    # "karabiner-elements"
                    "zed"
                  ]
                  ++ lib.optionals (!isWork) [
                    "github"
                    "multipass"
                    "steam"
                    "telegram"
                  ];

                  masApps = lib.optionalAttrs (!isWork) {
                    "Magnet" = 441258766;
                    "XCode" = 497799835;
                  };

                  taps = builtins.attrNames config.nix-homebrew.taps;

                  onActivation = {
                    autoUpdate = true;
                    cleanup = "zap"; # Uninstall packages/casks not in Brewfile
                    upgrade = true;
                  };

                  global = {
                    brewfile = true;
                  };

                  user = username;
                };

                power = {
                  restartAfterFreeze = true;
                  # restartAfterPowerFailure = true; # Not supported on laptops
                  sleep = {
                    display = 15; # minutes
                  };
                };

                fonts = {
                  packages = [ pkgs.nerd-fonts.jetbrains-mono ];
                };

                security = {

                  pam = {
                    services = {
                      sudo_local = {
                        enable = true;
                        # This may be required using DisplayLink
                        # /usr/bin/defaults write ~/Library/Preferences/com.apple.security.authorization.plist ignoreArd -bool TRUE
                        # https://discussions.apple.com/thread/255187302?sortBy=rank
                        touchIdAuth = true;
                      };
                    };
                  };
                };

                system = {
                  activationScripts.extraActivation.text = ''
                    # softwareupdate --install-rosetta --agree-to-license
                    # sudo xcodebuild -license accept
                    sudo -u ${username} /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u

                    # Obtain the shell that activation actions should be executed as
                    # nix-store -q --tree /run/current-system  | grep -oE '/nix/store/.+-activate-system-start' | xargs nix-store --query -R | grep bash
                    # # This will need permission to change Input Services
                    # #
                    # # defaults read /Library/LaunchDaemons/org.nixos.activate-system.plist | rg activate-system-start
                    # cat (Obtained location ) /nix/store/qjn5pvqdkr9g5qxp2wdbx95vrj3rpskn-activate-system-start
                  '';
                  defaults = {
                    # Fixes, https://github.com/nix-darwin/nix-darwin/issues/905#issuecomment-2816260787
                    # https://github.com/nix-darwin/nix-darwin/issues/905
                    NSGlobalDomain = {
                      "com.apple.keyboard.fnState" = true;
                      AppleInterfaceStyle = "Dark";
                      AppleInterfaceStyleSwitchesAutomatically = false;
                      "com.apple.swipescrolldirection" = false; # "natural" scrolling
                      "com.apple.springing.enabled" = false;
                      "com.apple.trackpad.scaling" = 3.0; # fast
                      AppleTemperatureUnit = "Fahrenheit";
                      AppleMeasurementUnits = "Inches";
                      NSAutomaticDashSubstitutionEnabled = false;
                      NSAutomaticPeriodSubstitutionEnabled = false;
                      # no automatic smart quotes
                      NSAutomaticQuoteSubstitutionEnabled = false;
                      NSAutomaticSpellingCorrectionEnabled = false;
                      NSNavPanelExpandedStateForSaveMode = true;
                      NSNavPanelExpandedStateForSaveMode2 = true;
                      NSDocumentSaveNewDocumentsToCloud = false;
                      # speed up animation on open/save boxes (default:0.2)
                      NSWindowResizeTime = 0.001;
                      AppleKeyboardUIMode = 3;
                      ApplePressAndHoldEnabled = false;
                      InitialKeyRepeat = 14;
                      KeyRepeat = 3;
                      NSAutomaticCapitalizationEnabled = false;
                      NSScrollAnimationEnabled = true;
                      NSAutomaticWindowAnimationsEnabled = false;
                    };

                    WindowManager = {
                      EnableStandardClickToShowDesktop = false;
                    };
                    controlcenter = {
                      BatteryShowPercentage = true;
                    };
                    dock = {
                      autohide = true;
                      largesize = null;
                      show-recents = false;
                      magnification = false;
                      mineffect = "genie";
                      tilesize = 10;
                      wvous-bl-corner = 1;
                      wvous-br-corner = 1;
                      wvous-tl-corner = 1;
                      wvous-tr-corner = 1;
                      persistent-apps = [
                        "/Applications/ghostty.app"
                      ];
                    };
                    finder = {
                      CreateDesktop = false;
                      FXDefaultSearchScope = "SCcf";
                      FXEnableExtensionChangeWarning = false;
                      FXPreferredViewStyle = "clmv";
                      NewWindowTarget = "Home";
                      ShowStatusBar = true;
                      _FXSortFoldersFirst = true;
                    };
                    hitoolbox = {
                      AppleFnUsageType = "Do Nothing";
                    };
                    loginwindow = {
                      GuestEnabled = false;
                    };
                    menuExtraClock = {
                      ShowDayOfMonth = true;
                    };
                    screensaver = {
                      askForPasswordDelay = 5;
                    };
                    CustomUserPreferences = {
                      NSGlobalDomain = {
                        CGDisableCursorLocationMagnification = true;
                      };
                    };
                  };
                  keyboard = {
                    enableKeyMapping = true;
                    remapCapsLockToEscape = true;
                  };
                  primaryUser = username;
                  startup = {
                    chime = false;
                  };
                };

                # Create /etc/zshrc that loads the nix-darwin environment.
                programs.zsh.enable = true;
                programs.bash.enable = true;

                # Still not working as the driver won't load and karabiner crashes when trying
                # Maybe v15 will fix this when it isn't busted.
                # https://github.com/nix-darwin/nix-darwin/issues/1041
                # services.karabiner-elements = {
                #   enable = true;
                #   package = pkgs.karabiner-elements.overrideAttrs (old: {
                #     version = "14.13.0";

                #     src = pkgs.fetchurl {
                #       inherit (old.src) url;
                #       hash = "sha256-gmJwoht/Tfm5qMecmq1N6PSAIfWOqsvuHU8VDJY8bLw=";
                #     };

                #     dontFixup = true;
                #   });
                # };

                # Define your user account.
                users.users."${username}" = {
                  home = "/Users/${username}";
                };

                # ==> HOME-MANAGER CONFIGURATION <==
                # --------------------------------------------------------------------
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.backupFileExtension = "backup";
                home-manager.extraSpecialArgs = { inherit helix-steel vim-hx; };

                home-manager.users."${username}" = {
                  imports = [
                    ./zed.nix
                    ./zellij.nix
                    ./git.nix
                    ./helix.nix
                    ./spacemacs.nix
                  ];
                  # Set the state version for home-manager for backwards compatibility.
                  home.stateVersion = "24.05";

                  home.sessionVariables = {
                    EDITOR = "hx";
                  }
                  // lib.optionalAttrs (!isWork) {
                    LPASS_AGENT_TIMEOUT = "0";
                  };

                  # User-specific packages
                  home.packages = with pkgs; [
                    fd
                    htop
                    jq
                    lastpass-cli
                    ripgrep
                    starship
                    zellij
                  ];

                  services.syncthing = {
                    enable = true; # Portal: http://127.0.0.1:8384/
                    overrideDevices = true;
                    overrideFolders = true;
                    settings = {
                      devices = {
                        "workbook" = {
                          id = "PRX6LFD-JMYAOPI-KX2EVUV-2U6BAWV-FJPUQCX-L32YEWK-BILXZF3-DHPPSAY";
                        };
                      };
                      folders = {
                        "Index" = {
                          path = "/Users/${username}/Index";
                          devices = [ "workbook" ];
                        };
                      };
                    };
                  };

                  programs.ssh = {
                    enable = true;
                    enableDefaultConfig = false;
                    # agentTimeout = "12h"; # TODO: Figure out and fix
                    settings = {
                      gh-deploykey = {
                        HostName = "github.com";
                        IdentityFile = "~/.ssh/deploy_key";
                        User = "git";
                        AddKeysToAgent = "yes";
                      };
                    };
                  };

                  programs.gh = {
                    enable = true;
                  };

                  programs.go = {
                    enable = true;
                    env = {
                      GOPATH = "/Users/${username}/go";
                    }
                    // lib.optionalAttrs isWork {
                      GOPRIVATE = [
                        "github.com/smithhealth"
                        "github.com/SmithHealth"
                      ];
                    };
                  };

                  programs.bat = {
                    enable = true;
                  };

                  programs.zoxide = {
                    enable = true;
                    enableZshIntegration = true;
                  };

                  programs.fzf = {
                    enable = true;
                    enableZshIntegration = true;
                  };

                  programs.direnv = {
                    enable = true;
                    enableZshIntegration = true;
                    nix-direnv.enable = true;
                  };

                  programs.git.settings.user = {
                    name = "Bryan Thode";
                    email = gitUserEmail;
                  };

                  programs.zsh = {
                    enable = true;
                    shellAliases = {
                      "nix-switch" =
                        if isWork then
                          "sudo sh -c 'darwin-rebuild switch --flake ~/singlenix/'"
                        else
                          "sudo nix run nix-darwin --extra-experimental-features \"nix-command flakes\" -- switch --flake /Users/bthode/Code/nix-darwin";
                      "nix-apply" =
                        if isWork then
                          "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u && source ~/.zshrc"
                        else
                          "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u";
                      "ls" = "eza";
                      "cat" = "bat";
                      "g" = "git";
                    };
                    initContent = ''
                      ulimit -f unlimited
                      ulimit -n 65536

                      export PATH="$HOME/.local/bin:$PATH"

                      g.rp() {
                        git ls-files --full-name "$1" | pbcopy
                      }
                    ''
                    + lib.optionalString isWork ''

                      if [ -f "/Users/${username}/.github-pat" ]; then
                        # export GITHUB_PERSONAL_ACCESS_TOKEN=$(cat "/Users/${username}/.github-pat")
                        export GITHUB_TOKEN=$(cat "/Users/${username}/.github-pat")
                      fi
                    '';
                  };
                };
              }
            )
          ];
        };
    in
    {
      darwinConfigurations = {
        "SRX-US-DWVKDYXQHV" = mkHost {
          hostname = "SRX-US-DWVKDYXQHV";
          username = "bryan.thode";
          isWork = true;
          gitUserEmail = "bryan.thode@smithrx.com";
        };

        "air" = mkHost {
          hostname = "air";
          username = "bthode";
          isWork = false;
          gitUserEmail = "bryan@tatq.com";
        };
      };
    };
}
