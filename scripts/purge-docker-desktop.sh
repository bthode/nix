#!/usr/bin/env bash
# One-shot removal of Docker Desktop leftovers.
#
# Docker Desktop was uninstalled by hand; this removes what the drag-to-trash
# does not: root-owned launch daemons, the privileged helper, dangling
# /usr/local/bin symlinks, and the stranded VM disk.
#
# Idempotent and safe to re-run. Safe on a machine that never had Docker
# Desktop: every step reports and skips what is already absent. Never removes a
# symlink that still resolves.
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "macOS only." >&2
  exit 1
fi

echo "==> Docker Desktop purge (sudo required for steps 1-3)"
sudo -v

echo "--> 1/5 unloading launch daemons"
for label in com.docker.vmnetd com.docker.socket; do
  if sudo launchctl print "system/$label" >/dev/null 2>&1; then
    echo "    unloading system/$label"
    sudo launchctl bootout "system/$label" || true
  else
    echo "    system/$label not loaded (skip)"
  fi
done

echo "--> 2/5 removing root-owned daemon plists and privileged helper"
for p in \
  /Library/LaunchDaemons/com.docker.socket.plist \
  /Library/LaunchDaemons/com.docker.vmnetd.plist \
  /Library/PrivilegedHelperTools/com.docker.vmnetd; do
  if [ -e "$p" ]; then
    echo "    removing $p"
    sudo rm -rf "$p"
  else
    echo "    $p absent (skip)"
  fi
done

echo "--> 3/5 removing dangling /usr/local/bin symlinks"
# These do NOT shadow Nix: PATH lookup requires an executable file, and a broken
# symlink fails that test, so lookup skips it. This is cleanup, not a fix. Worth
# doing anyway: they are misleading, and they would spring back to life pointing
# at unlicensed binaries if anything ever recreated /Applications/Docker.app.
for name in docker docker-compose docker-credential-desktop \
  docker-credential-ecr-login docker-credential-osxkeychain \
  kubectl kubectl.docker; do
  p="/usr/local/bin/$name"
  if [ -L "$p" ] && [ ! -e "$p" ]; then
    echo "    removing dangling $p -> $(readlink "$p")"
    sudo rm -f "$p"
  elif [ -e "$p" ]; then
    echo "    $p resolves; LEAVING ALONE"
  else
    echo "    $p absent (skip)"
  fi
done

echo "--> 4/5 removing Docker Desktop application data"
for p in \
  "$HOME/Library/Containers/com.docker.docker" \
  "$HOME/Library/Group Containers/group.com.docker" \
  "$HOME/Library/Application Support/Docker Desktop" \
  "$HOME/Library/Preferences/com.electron.dockerdesktop.plist"; do
  if [ -e "$p" ]; then
    echo "    removing $p ($(du -sh "$p" 2>/dev/null | cut -f1))"
    rm -rf "$p"
  else
    echo "    $p absent (skip)"
  fi
done

echo "--> 5/5 removing Docker Desktop parts of ~/.docker"
# config.json is deliberately preserved: the home-manager activation in
# colima.nix repairs it in place.
for name in cli-plugins bin desktop-build docker-next gordon models modules \
  mutagen sandboxes run contexts daemon.json .token_seed \
  .token_seed.lock; do
  p="$HOME/.docker/$name"
  if [ -e "$p" ]; then
    echo "    removing $p"
    rm -rf "$p"
  else
    echo "    $p absent (skip)"
  fi
done

echo
echo "==> Purge complete. ~/.docker/config.json was left in place for"
echo "    home-manager activation to repair. Next: colima start"
