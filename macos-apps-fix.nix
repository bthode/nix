{
  pkgs,
  config,
  lib,
  ...
}:
{
  home.activation = {
    copyNixApps = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      # Create directory for the applications
      mkdir -p "$HOME/Applications/Nix-Apps"

      # Remove old entries
      rm -rf "$HOME/Applications/Nix-Apps"/*

      # Get the target of the symlink
      NIXAPPS=$(readlink -f "$HOME/.nix-profile/Applications")

      # For each application
      for app_source in "$NIXAPPS"/*; do
        if [ -d "$app_source" ]; then # Handle .app bundles
          rsync -a --delete "$app_source/" "$HOME/Applications/Nix-Apps/$(basename "$app_source")"
        elif [ -f "$app_source" ] && [[ "$app_source" == *.dmg ]]; then # Handle .dmg files
          # Mount the dmg
          MOUNT_POINT=$(hdiutil attach -nobrowse "$app_source" | grep /Volumes | cut -f 3)

          # Find the .app directory in the mounted volume
          APP_PATH=$(find "$MOUNT_POINT" -name "*.app" -maxdepth 1 -print -quit)

          if [ -n "$APP_PATH" ]; then
            # Copy the .app to the Nix-Apps directory
            rsync -a --delete "$APP_PATH/" "$HOME/Applications/Nix-Apps/$(basename "$APP_PATH")"
          fi

          # Unmount the dmg
          hdiutil detach "$MOUNT_POINT"
        fi
      done
    '';
  };
}
