# Docker Desktop → Colima Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the uninstalled Docker Desktop with Colima on the work host, declaratively via nix-darwin, and purge the leftovers that currently break `kubectl`, ECR auth, and `docker login`.

**Architecture:** Four work-only packages join `flake.nix`. A new `colima.nix` home-manager module owns two things: the Colima VM template (a read-only store symlink, since Colima only reads it) and an idempotent `jq` merge that repairs `~/.docker/config.json` (a merge, not a symlink, because Docker and Colima must both write that file). A one-shot committed script removes the Docker Desktop remains, including root-owned launch daemons and the dangling `/usr/local/bin` symlinks that shadow Nix binaries.

**Tech Stack:** nix-darwin, home-manager, Nix flakes, Colima 0.10.3 (wrapping lima-full 2.1.4 / qemu 11.0.1 / krunkit 1.3.2), `jq`, bash.

**Spec:** `docs/superpowers/specs/2026-09-02-colima-migration-design.md`

## Global Constraints

- Target host is `SRX-US-DWVKDYXQHV` only (`isWork = true`), `aarch64-darwin`, 12 cores / 24 GB.
- The personal host `air` must be left **completely unchanged**. `docker` and `docker-compose` stay in the shared package list; do not move them.
- Every new package goes under `lib.optionals isWork`.
- ECR registries, exact strings: `467554678334.dkr.ecr.us-west-2.amazonaws.com` and `600461924372.dkr.ecr.us-west-1.amazonaws.com`. The `123456789012...` value seen in the codebase is a docs placeholder — do not include it.
- Colima template path is `~/.colima/_templates/default.yaml` (verified via `colima template --print`).
- The template file must be **complete**, not partial. Colima unmarshals it into the same struct that supplies flag defaults, so an omitted field becomes a Go zero value (`cpu: 0`), not a default.
- Work on branch `colima-migration`. The repo has no formatter config; match the existing 2-space style in `flake.nix` by hand.
- **Ordering dependency:** Task 4 (purge) is a prerequisite for Task 3's credential helpers to function, because `/usr/local/bin` (PATH position 2) shadows `/run/current-system/sw/bin` (position 17).
- Nix evaluation of this flake takes ~40s uncached for `systemPackages` queries. That is expected, not a hang.

---

### Task 1: Work-only packages in `flake.nix`

Adds the Colima engine plus the three tools that broke when Docker Desktop was removed.

**Files:**
- Modify: `flake.nix:220-232` (the `lib.optionals isWork` package list)

**Interfaces:**
- Consumes: nothing.
- Produces: `colima`, `kubectl`, `docker-credential-osxkeychain`, and `docker-credential-ecr-login` binaries in `/run/current-system/sw/bin` on the work host. Task 3's `credHelpers` config depends on the last two existing by those exact binary names.

- [ ] **Step 1: Write the failing check**

This repo has no test framework; `nix eval` is the check. Run this and save the output as the "before" state:

```bash
nix eval --json '.#darwinConfigurations."SRX-US-DWVKDYXQHV".config.environment.systemPackages' \
  --apply 'ps: builtins.filter (n: n != null) (map (p: p.pname or null) ps)' \
  | tr ',' '\n' | grep -iE 'colima|kubectl|credential|docker'
```

- [ ] **Step 2: Run it to verify it fails**

Expected output: only `"docker"` and `"docker-compose"`. No `colima`, no `kubectl`, no credential helpers. That absence is the failing check.

- [ ] **Step 3: Add the packages**

In `flake.nix`, the `isWork` list currently reads:

```nix
                  ++ lib.optionals isWork (
                    with pkgs;
                    [
                      acli
                      awscli2
                      goose
                      jdk25
                      jmeter
                      rancher
                      redis
                      teleport
                    ]
                  )
```

Replace the inner list with this, keeping alphabetical order:

```nix
                    [
                      acli
                      amazon-ecr-credential-helper
                      awscli2
                      colima
                      docker-credential-helpers
                      goose
                      jdk25
                      jmeter
                      kubectl
                      rancher
                      redis
                      teleport
                    ]
```

Do not touch the shared list above it. `docker`, `docker-compose`, and `rancher` all stay exactly where they are — `rancher` is the Rancher **Server CLI** and is unrelated to Rancher Desktop.

- [ ] **Step 4: Run the check to verify it passes**

```bash
nix eval --json '.#darwinConfigurations."SRX-US-DWVKDYXQHV".config.environment.systemPackages' \
  --apply 'ps: builtins.filter (n: n != null) (map (p: p.pname or null) ps)' \
  | tr ',' '\n' | grep -iE 'colima|kubectl|credential'
```

Expected: `"colima"`, `"kubectl"`, `"docker-credential-helpers"`, `"amazon-ecr-credential-helper"` all present.

- [ ] **Step 5: Confirm `air` is unaffected**

```bash
nix eval --json '.#darwinConfigurations."air".config.environment.systemPackages' \
  --apply 'ps: builtins.filter (n: n != null) (map (p: p.pname or null) ps)' \
  | tr ',' '\n' | grep -icE 'colima|kubectl|credential'
```

Expected: `0`.

- [ ] **Step 6: Verify the whole system still builds**

```bash
nix build --no-link '.#darwinConfigurations."SRX-US-DWVKDYXQHV".system'
```

Expected: exits 0. This is the real gate — evaluation success alone does not prove the packages build on `aarch64-darwin`.

- [ ] **Step 7: Commit**

```bash
git add flake.nix
git commit -m "feat: add colima, kubectl, and docker credential helpers to work host"
```

---

### Task 2: Colima VM template, wired through home-manager

Creates the template file and the module that installs it. The template alone is not testable, so it and its wiring are one task.

**Files:**
- Create: `colima-template.yaml`
- Create: `colima.nix`
- Modify: `flake.nix:467` (`home-manager.extraSpecialArgs`)
- Modify: `flake.nix:470-477` (home-manager `imports`)

**Interfaces:**
- Consumes: `colima` from Task 1.
- Produces: an `isWork`-gated home-manager module at `./colima.nix` taking `{ pkgs, lib, isWork, ... }`, whose body is a single `lib.mkIf isWork { ... }`. Task 3 adds `home.activation.dockerConfigForColima` **inside that same `mkIf` block**.

- [ ] **Step 1: Write the failing check**

```bash
nix eval --raw '.#darwinConfigurations."SRX-US-DWVKDYXQHV".config.home-manager.users."bryan.thode".home.file.".colima/_templates/default.yaml".source'
```

- [ ] **Step 2: Run it to verify it fails**

Expected: an error that the attribute `".colima/_templates/default.yaml"` is missing.

- [ ] **Step 3: Generate the complete template as a starting point**

Do not hand-write this file. Generate Colima's own full 288-line default, comments included, so no field is accidentally omitted:

```bash
nix shell nixpkgs#colima --command colima template --print   # prints the path
cp "$(nix shell nixpkgs#colima --command colima template --print)" colima-template.yaml
wc -l colima-template.yaml   # expect 288
```

If `~/.colima/_templates/default.yaml` does not exist yet, running `colima template --print` creates it populated with defaults.

- [ ] **Step 4: Patch exactly six fields**

Each of these patterns matches exactly once at the start of a line — verified. Apply in place:

```bash
sed -i '' \
  -e 's/^cpu: 2$/cpu: 6/' \
  -e 's/^memory: 2$/memory: 8/' \
  -e 's/^vmType: qemu$/vmType: vz/' \
  -e 's/^mountType: sshfs$/mountType: virtiofs/' \
  -e 's/^rosetta: false$/rosetta: true/' \
  colima-template.yaml
```

`disk: 100` and `mounts: []` are already Colima's defaults and are the values the spec wants, so they need no edit — leave them. `mounts: []` is what makes `$HOME` mount **writable**, which is what lets `forge`'s `./localstack-init` bind mount work.

- [ ] **Step 5: Verify the patch took**

```bash
grep -nE '^(cpu|memory|disk|vmType|mountType|rosetta|mounts):' colima-template.yaml
```

Expected, exactly these seven lines and values:

```
cpu: 6
disk: 100
memory: 8
vmType: vz
mountType: virtiofs
rosetta: true
mounts: []
```

`rosetta: true` requires `vmType: vz`; if `vmType` is still `qemu`, Rosetta is silently ignored, so both must be correct.

- [ ] **Step 6: Create `colima.nix`**

```nix
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
}
```

- [ ] **Step 7: Thread `isWork` to home-manager**

`flake.nix:467` currently reads:

```nix
                home-manager.extraSpecialArgs = { inherit helix-steel vim-hx; };
```

Change to:

```nix
                home-manager.extraSpecialArgs = { inherit helix-steel vim-hx isWork; };
```

`isWork` is a `mkHost` parameter and is in scope at this point.

- [ ] **Step 8: Import the module**

Append `./colima.nix` to the home-manager `imports` list at `flake.nix:470-477`, so it reads:

```nix
                  imports = [
                    ./zed.nix
                    ./zellij.nix
                    ./git.nix
                    ./helix.nix
                    ./spacemacs.nix
                    ./herdr.nix
                    ./colima.nix
                  ];
```

- [ ] **Step 9: Run the check to verify it passes**

```bash
nix eval --raw '.#darwinConfigurations."SRX-US-DWVKDYXQHV".config.home-manager.users."bryan.thode".home.file.".colima/_templates/default.yaml".source'
```

Expected: a `/nix/store/...-colima-template.yaml` path. Then confirm the store copy carries the patched values:

```bash
grep -E '^(cpu|memory|vmType|mountType|rosetta):' \
  "$(nix eval --raw '.#darwinConfigurations."SRX-US-DWVKDYXQHV".config.home-manager.users."bryan.thode".home.file.".colima/_templates/default.yaml".source')"
```

- [ ] **Step 10: Confirm `air` did not gain the file**

```bash
nix eval --raw '.#darwinConfigurations."air".config.home-manager.users."bthode".home.file.".colima/_templates/default.yaml".source'
```

Expected: an error about a missing attribute. That error **is** the passing result — it proves `lib.mkIf isWork` gated correctly.

- [ ] **Step 11: Commit**

```bash
git add colima.nix colima-template.yaml flake.nix
git commit -m "feat: add nix-managed colima VM template for work host"
```

---

### Task 3: Repair `~/.docker/config.json` via activation

Fixes the dead `credsStore`, wires the ECR helper, and clears the stale Docker Desktop context.

**Files:**
- Modify: `colima.nix` (add `home.activation` inside the existing `lib.mkIf isWork` block)

**Interfaces:**
- Consumes: the `lib.mkIf isWork` block from Task 2; `docker-credential-osxkeychain` and `docker-credential-ecr-login` from Task 1.
- Produces: `home.activation.dockerConfigForColima`. Nothing later consumes it.

- [ ] **Step 1: Write the failing check**

```bash
jq '{credsStore, credHelpers, currentContext, plugins: (.plugins | type), features: (.features | type)}' ~/.docker/config.json
```

- [ ] **Step 2: Run it to verify it fails**

Expected, the broken state: `credsStore` is `"desktop"`, `credHelpers` is `null`, `currentContext` is `"desktop-linux"`, and `plugins`/`features` are `"object"`. `docker-credential-desktop` no longer exists, so every `docker login` fails.

- [ ] **Step 3: Add the activation entry**

Insert into the `lib.mkIf isWork { ... }` body in `colima.nix`, after the `home.file` line:

```nix
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
```

Notes for the implementer, each one load-bearing:

- The `.tmp` file sits beside the target rather than in `$TMPDIR`, so `mv` is a same-filesystem atomic rename and the script needs no `mktemp` on the activation `PATH`.
- `del(.currentContext)` is conditional on the value being `desktop-linux`. Unconditional deletion would clobber a working `colima` context on later rebuilds. Verified: with `contexts/` purged by Task 4 and this value left stale, `docker ps` fails with `context not found` — strictly worse than the current error.
- `credsStore = "osxkeychain"` replaces the dead `"desktop"`. `credHelpers` overrides `credsStore` per-registry, so ECR uses `ecr-login` while everything else uses the macOS Keychain.
- This block uses `pkgs`, which is why `colima.nix` takes `pkgs` in its argument set.

- [ ] **Step 4: Verify the filter is correct and idempotent before switching**

Test against a copy, so a bad filter cannot damage the real file:

```bash
mkdir -p /tmp/dockercfgtest && cp ~/.docker/config.json /tmp/dockercfgtest/
FILTER='.credsStore = "osxkeychain"
  | .credHelpers = ((.credHelpers // {}) + {
      "467554678334.dkr.ecr.us-west-2.amazonaws.com": "ecr-login",
      "600461924372.dkr.ecr.us-west-1.amazonaws.com": "ecr-login"
    })
  | del(.plugins, .features)
  | if .currentContext == "desktop-linux" then del(.currentContext) else . end'
jq "$FILTER" /tmp/dockercfgtest/config.json > /tmp/dockercfgtest/o1.json
jq "$FILTER" /tmp/dockercfgtest/o1.json > /tmp/dockercfgtest/o2.json
diff /tmp/dockercfgtest/o1.json /tmp/dockercfgtest/o2.json && echo "IDEMPOTENT: PASS"
printf '{"currentContext":"colima","auths":{"x":{"auth":"abc"}}}' | jq "$FILTER"
```

Expected: `IDEMPOTENT: PASS`; `o1.json` has `credsStore: "osxkeychain"`, both `credHelpers` entries, no `plugins`, no `features`, no `currentContext`; and the final line preserves `currentContext: "colima"` and `auths` untouched.

- [ ] **Step 5: Verify it evaluates**

```bash
nix eval --raw '.#darwinConfigurations."SRX-US-DWVKDYXQHV".config.home-manager.users."bryan.thode".home.activation.dockerConfigForColima.data' | head -20
```

Expected: the activation script text, with `${pkgs.jq}` resolved to a `/nix/store/...` path. The real file is not modified until Task 5 runs the switch.

- [ ] **Step 6: Commit**

```bash
git add colima.nix
git commit -m "feat: repair docker config.json for colima and ECR via activation"
```

---

### Task 4: One-shot Docker Desktop purge script

**Files:**
- Create: `scripts/purge-docker-desktop.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: an executable script. Task 5 runs it. It is intentionally *not* an activation script — it is a destructive one-per-machine operation, not a per-rebuild one.

- [ ] **Step 1: Write the failing check**

```bash
ls -la /usr/local/bin/kubectl /usr/local/bin/docker-credential-ecr-login 2>&1
ls /Library/LaunchDaemons/ | grep -i docker
du -sh ~/Library/Containers/com.docker.docker 2>/dev/null
command -v kubectl || echo "kubectl NOT RESOLVABLE"
```

- [ ] **Step 2: Run it to verify it fails**

Expected: both symlinks present and dangling (pointing into the absent `/Applications/Docker.app`), `com.docker.socket.plist` and `com.docker.vmnetd.plist` both listed, roughly `21G` reported, and `kubectl` either unresolvable or resolving to the dead `/usr/local/bin/kubectl`.

- [ ] **Step 3: Write the script**

```bash
#!/usr/bin/env bash
# One-shot removal of Docker Desktop leftovers.
#
# Docker Desktop was uninstalled by hand; this removes what the drag-to-trash
# does not: root-owned launch daemons, the privileged helper, dangling
# /usr/local/bin symlinks that shadow Nix binaries, and the stranded VM disk.
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
  /Library/PrivilegedHelperTools/com.docker.vmnetd
do
  if [ -e "$p" ]; then
    echo "    removing $p"
    sudo rm -rf "$p"
  else
    echo "    $p absent (skip)"
  fi
done

echo "--> 3/5 removing dangling /usr/local/bin symlinks"
# /usr/local/bin is PATH position 2, ahead of the Nix paths, so these shadow
# Nix-provided kubectl and credential helpers. Removal is required, not cosmetic.
for name in docker docker-compose docker-credential-desktop \
            docker-credential-ecr-login docker-credential-osxkeychain \
            kubectl kubectl.docker
do
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
  "$HOME/Library/Preferences/com.electron.dockerdesktop.plist"
do
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
            .token_seed.lock
do
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
```

- [ ] **Step 4: Make it executable and check syntax**

```bash
chmod +x scripts/purge-docker-desktop.sh
bash -n scripts/purge-docker-desktop.sh && echo "SYNTAX: PASS"
```

Expected: `SYNTAX: PASS`. Do **not** run the script yet — it runs once, in Task 5, in the correct order.

- [ ] **Step 5: Prove the symlink guard cannot delete a live binary**

Test the guard's logic in isolation, without touching `/usr/local/bin`:

```bash
d=$(mktemp -d); : > "$d/real"; ln -s "$d/real" "$d/live"; ln -s "$d/gone" "$d/dead"
for n in live dead; do
  p="$d/$n"
  if [ -L "$p" ] && [ ! -e "$p" ]; then echo "$n -> WOULD REMOVE"; else echo "$n -> would keep"; fi
done
```

Expected exactly: `live -> would keep`, `dead -> WOULD REMOVE`.

- [ ] **Step 6: Commit**

```bash
git add scripts/purge-docker-desktop.sh
git commit -m "feat: add idempotent docker desktop purge script"
```

---

### Task 5: Apply and verify end to end

Nothing in Tasks 1-4 has touched the running system. This task does, in the one order that works.

**Files:** none modified.

**Interfaces:**
- Consumes: everything from Tasks 1-4.
- Produces: a working Colima runtime.

- [ ] **Step 1: Switch the system**

```bash
sudo nix run nix-darwin --extra-experimental-features "nix-command flakes" -- switch --flake ~/nix
```

The repo's `nix-switch` alias runs exactly this. Expected: the switch reports activating `dockerConfigForColima`. `~/.colima/_templates/default.yaml` already exists on this machine, so home-manager will move it to `default.yaml.backup` — that is `backupFileExtension = "backup"` working as configured, not an error.

- [ ] **Step 2: Verify the config merge landed**

```bash
jq '{credsStore, credHelpers, currentContext}' ~/.docker/config.json
```

Expected: `credsStore` is `"osxkeychain"`, both ECR registries map to `"ecr-login"`, and `currentContext` is absent.

- [ ] **Step 3: Run the purge**

```bash
~/nix/scripts/purge-docker-desktop.sh
```

Expected: every step reports removals rather than skips. Then confirm the space came back:

```bash
df -h /
```

Expected: available space up by roughly 21 GB from the pre-purge figure.

- [ ] **Step 4: Verify the PATH shadowing is gone**

This is the check that proves the purge mattered:

```bash
command -v kubectl
kubectl version --client
command -v docker-credential-ecr-login
command -v docker-credential-osxkeychain
```

Expected: `kubectl` resolves under `/run/current-system/sw/bin` or `~/.nix-profile/bin`, **not** `/usr/local/bin`; `kubectl version --client` prints a version; both credential helpers resolve into Nix paths.

- [ ] **Step 5: Start the VM**

```bash
colima start
colima status
```

Expected: first start downloads a disk image and takes several minutes. `colima status` reports running, and names `vz` as the runtime.

- [ ] **Step 6: Verify the engine and the Docker context**

```bash
docker context ls
docker version
docker run --rm public.ecr.aws/docker/library/alpine echo ok
```

Expected: `colima` is the current context, the client reports a Linux **Server** section (which never appeared under the broken setup), and the container prints `ok`.

- [ ] **Step 7: Verify Rosetta is actually active**

```bash
docker run --rm --platform linux/amd64 public.ecr.aws/docker/library/alpine uname -m
```

Expected: `x86_64`. If this prints `aarch64`, the platform flag was ignored; if it is very slow, Rosetta fell back to qemu binfmt — recheck that `vmType: vz` and `rosetta: true` both reached `~/.colima/default/colima.yaml`.

- [ ] **Step 8: Verify ECR auth with no manual login**

With valid AWS credentials for the region, pull any image your account can read from `467554678334.dkr.ecr.us-west-2.amazonaws.com`, without running `docker login` or `aws ecr get-login-password` first. Expected: the pull succeeds, proving `credHelpers` invoked `docker-credential-ecr-login`. An auth error here means Step 4 failed or AWS credentials are stale — check `aws sts get-caller-identity` before suspecting the Nix config.

- [ ] **Step 9: Verify Compose, bind mounts, and a local image build**

```bash
cd ~/Code/forge
docker compose -f docker-compose.faketime.yml build   # recreates postgres-faketime:16
docker compose up -d
docker compose ps
docker compose down
```

Expected: the `postgres-faketime:16` image rebuilds (it was stranded in the deleted Docker Desktop VM), containers reach a running state, and the `./localstack-init` bind mount resolves — which is what proves `$HOME` is mounted writable in the VM.

- [ ] **Step 10: Verify the template survives a VM restart**

```bash
colima stop && colima start
docker run --rm public.ecr.aws/docker/library/alpine echo ok
```

Expected: `ok`. This confirms the instance config persisted rather than depending on first-run state.

- [ ] **Step 11: Verify the purge script is safely re-runnable**

```bash
~/nix/scripts/purge-docker-desktop.sh
```

Expected: every line reports `absent (skip)` or `resolves; LEAVING ALONE`, and nothing is removed. Critically, `~/.docker/config.json` must still be intact afterwards:

```bash
jq '{credsStore, credHelpers}' ~/.docker/config.json
```

- [ ] **Step 12: Commit and open the PR**

```bash
git add -A
git commit -m "docs: record colima migration verification" --allow-empty
gh pr create --title "Migrate from Docker Desktop to Colima" \
  --body "Replaces the uninstalled Docker Desktop with Colima on the work host.

Adds colima, kubectl, and the ECR/osxkeychain credential helpers as work-only
packages; a nix-managed Colima VM template (vz + Rosetta, 6 CPU / 8 GB); an
idempotent activation merge repairing ~/.docker/config.json; and a one-shot
purge script for the Docker Desktop leftovers.

Notably fixes three things broken by the Docker Desktop removal: kubectl, ECR
credential lookup, and docker login. Reclaims 21 GB. air is unchanged.

Spec: docs/superpowers/specs/2026-09-02-colima-migration-design.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

---

## Rollback

If Colima proves unworkable, `git checkout master && nix-switch` restores the previous generation's packages. Note what this does **not** undo: the Task 4 purge is irreversible, and the old Docker Desktop VM images are already unrecoverable regardless. That is not a new risk introduced by this plan — those images became unreachable the moment the application was deleted.

## Deferred

Recorded in the spec's out-of-scope section, not implemented here:

- `forge/docker-compose.yml` pulling `localstack/localstack:4.14` from Docker Hub rather than `public.ecr.aws/localstack/localstack`. Different repo; it is the rate-limit issue the team raised.
- `macos-apps-fix.nix` is absent from the home-manager `imports` list. Pre-existing and unrelated.
- Adding Colima to `air`, which would be a one-line change to `colima.nix`'s gate plus the package list.
