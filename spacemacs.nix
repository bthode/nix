{ config, pkgs, lib, ... }:

{
  home.activation.installSpacemacs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    SPACEMACS_DIR="$HOME/.emacs.d"
    SPACEMACS_REPO="https://github.com/syl20bnr/spacemacs"
    SPACEMACS_BRANCH="develop"

    if [ -d "$SPACEMACS_DIR" ] && [ ! -d "$SPACEMACS_DIR/.git" ]; then
      $DRY_RUN_CMD mv "$SPACEMACS_DIR" "$SPACEMACS_DIR.bak"
    fi

    if [ ! -d "$SPACEMACS_DIR/.git" ]; then
      $DRY_RUN_CMD env \
        GIT_SSH_COMMAND="/usr/bin/ssh -o BatchMode=yes" \
        GIT_TERMINAL_PROMPT=0 \
        GIT_CONFIG_GLOBAL=/dev/null \
        GIT_CONFIG_SYSTEM=/dev/null \
        ${pkgs.git}/bin/git clone \
          --branch "$SPACEMACS_BRANCH" \
          --depth 1 \
          "$SPACEMACS_REPO" \
          "$SPACEMACS_DIR"
    fi
  '';

  home.file.".spacemacs".text = ''
    ;; -*- mode: emacs-lisp; lexical-binding: t -*-

    (defun dotspacemacs/layers ()
      (setq-default
       dotspacemacs-distribution 'spacemacs
       dotspacemacs-enable-lazy-installation 'unused
       dotspacemacs-ask-for-lazy-installation t
       dotspacemacs-configuration-layers
       '(
         auto-completion
         better-defaults
         emacs-lisp
         git
         helm
         lsp
         markdown
         multiple-cursors
         org
         spell-checking
         syntax-checking
         treemacs
         version-control
       )
       dotspacemacs-additional-packages '()
       dotspacemacs-frozen-packages '()
       dotspacemacs-excluded-packages '(code-review)
       dotspacemacs-install-packages 'used-only))

    (defun dotspacemacs/init ()
      (setq-default
       dotspacemacs-enable-emacs-pdumper nil
       dotspacemacs-emacs-pdumper-executable-file "emacs"
       dotspacemacs-emacs-dumper-dump-file (format "spacemacs-%s.pdmp" emacs-version)
       dotspacemacs-elpa-https t
       dotspacemacs-elpa-timeout 5
       dotspacemacs-gc-cons '(100000000 0.1)
       dotspacemacs-read-process-output-max (* 1024 1024)
       dotspacemacs-use-spacelpa nil
       dotspacemacs-verify-spacelpa-archives t
       dotspacemacs-check-for-update nil
       dotspacemacs-elpa-subdirectory 'emacs-version
       dotspacemacs-editing-style 'vim
       dotspacemacs-startup-buffer-show-version t
       dotspacemacs-startup-banner 'official
       dotspacemacs-startup-banner-scale 'auto
       dotspacemacs-startup-lists '((recents . 5) (projects . 7))
       dotspacemacs-startup-buffer-responsive t
       dotspacemacs-show-changelog-at-startup nil
       dotspacemacs-default-theme 'spacemacs-dark
       dotspacemacs-mode-line-theme '(spacemacs :separator wave :separator-scale 1.5)
       dotspacemacs-colorize-cursor-according-to-state t
       dotspacemacs-default-font '("JetBrainsMono Nerd Font"
                                   :size 13.0
                                   :weight normal
                                   :width normal)
       dotspacemacs-leader-key "SPC"
       dotspacemacs-emacs-command-key "SPC"
       dotspacemacs-ex-command-key ":"
       dotspacemacs-emacs-leader-key "M-m"
       dotspacemacs-major-mode-leader-key ","
       dotspacemacs-major-mode-emacs-leader-key (if window-system "<M-return>" "C-M-m")
       dotspacemacs-distinguish-gui-tab nil
       dotspacemacs-default-layout-name "Default"
       dotspacemacs-display-default-layout nil
       dotspacemacs-auto-resume-layouts nil
       dotspacemacs-auto-generate-layout-names nil
       dotspacemacs-large-file-size 1
       dotspacemacs-auto-save-file-location 'cache
       dotspacemacs-max-rollback-slots 5
       dotspacemacs-enable-paste-transient-state nil
       dotspacemacs-which-key-delay 0.4
       dotspacemacs-which-key-position 'bottom
       dotspacemacs-switch-to-buffer-prefers-purpose nil
       dotspacemacs-loading-progress-bar t
       dotspacemacs-fullscreen-at-startup nil
       dotspacemacs-fullscreen-use-non-native nil
       dotspacemacs-maximized-at-startup nil
       dotspacemacs-undecorated-at-startup nil
       dotspacemacs-active-transparency 90
       dotspacemacs-inactive-transparency 90
       dotspacemacs-show-transient-state-title t
       dotspacemacs-show-transient-state-color-guide t
       dotspacemacs-mode-line-unicode-symbols t
       dotspacemacs-smooth-scrolling t
       dotspacemacs-scroll-bar-while-scrolling t
       dotspacemacs-line-numbers nil
       dotspacemacs-folding-method 'evil
       dotspacemacs-smartparens-strict-mode nil
       dotspacemacs-activate-smartparens-mode t
       dotspacemacs-smart-closing-parenthesis nil
       dotspacemacs-highlight-delimiters 'all
       dotspacemacs-enable-server nil
       dotspacemacs-server-socket-dir nil
       dotspacemacs-persistent-server nil
       dotspacemacs-search-tools '("rg" "ag" "pt" "ack" "grep")
       dotspacemacs-frame-title-format "%I@%S"
       dotspacemacs-icon-title-format nil
       dotspacemacs-show-trailing-whitespace t
       dotspacemacs-whitespace-cleanup nil
       dotspacemacs-use-clean-aindent-mode t
       dotspacemacs-use-SPC-as-y nil
       dotspacemacs-swap-number-row nil
       dotspacemacs-zone-out-when-idle nil
       dotspacemacs-pretty-docs nil
       dotspacemacs-home-shorten-agenda-source nil
       dotspacemacs-byte-compile nil))

    (defun dotspacemacs/user-env ()
      (spacemacs/load-spacemacs-env))

    (defun dotspacemacs/user-init ())

    (defun dotspacemacs/user-load ())

    (defun dotspacemacs/user-config ())
  '';
}
