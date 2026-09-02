# Colima container runtime, work host only.
#
# Two responsibilities:
#   1. The VM template Colima stamps new instances from. A read-only store
#      symlink is safe here because Colima only ever reads the template.
#   2. Repairing ~/.docker/config.json (added in a later task). That file is
#      merged rather than symlinked, because `docker login` and Colima both
#      need to write it.
#
# The VM is started manually with `colima start`; there is deliberately no
# launchd agent, so the VM's 8 GB is only committed when it is wanted.
{
  pkgs,
  lib,
  isWork,
  ...
}:

lib.mkIf isWork {
  home.file.".colima/_templates/default.yaml".source = ./colima-template.yaml;

  # ~/.docker/config.json is merged, never symlinked: `docker login` writes
  # `auths` and Colima writes `currentContext`, so the file must stay writable.
  # Idempotent, so it is safe on every rebuild.
  home.activation.dockerConfigForColima = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    config_file="$HOME/.docker/config.json"
    mkdir -p "$HOME/.docker"
    if [ ! -s "$config_file" ]; then
      echo '{}' > "$config_file"
    fi

    if ${pkgs.jq}/bin/jq '
        .credsStore = "osxkeychain"
      | .credHelpers = ((.credHelpers // {}) + {
          "467554678334.dkr.ecr.us-west-2.amazonaws.com": "ecr-login",
          "600461924372.dkr.ecr.us-west-1.amazonaws.com": "ecr-login"
        })
      | del(.plugins, .features)
      | if .currentContext == "desktop-linux" then del(.currentContext) else . end
    ' "$config_file" > "$config_file.tmp"; then
      mv "$config_file.tmp" "$config_file"
      chmod 600 "$config_file"
    else
      rm -f "$config_file.tmp"
      echo "warning: could not patch $config_file; left unchanged" >&2
    fi
  '';
}
