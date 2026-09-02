# Docker Desktop → Colima Migration

Design doc. Host: `SRX-US-DWVKDYXQHV` (work, `isWork = true`), aarch64-darwin,
12 cores / 24 GB. Personal host `air` is deliberately untouched.

## Motivation

The company is not licensed for Docker Desktop and must stop using the
application. The Docker Hub *registry* is not banned, but pulling common base
images from it hits rate limits at scale; the team's guidance is to reference
`public.ecr.aws/docker/library/...` explicitly instead.

Colima replaces the application, not the toolchain: it is Lima plus a
preconfigured Linux VM plus Docker Engine inside that VM, plus socket forwarding
and a Docker context. Same engine, same CLI, same images, same Compose files.

Docker Desktop has already been dragged to the trash. `/Applications/Docker.app`
is gone, but its configuration, its root-owned launch daemons, its `/usr/local/bin`
symlinks, and 21 GB of VM disk remain.

## Current state (verified, not assumed)

Docker Desktop was never declared in `flake.nix` — no `docker-desktop` cask. It
was installed out of band, so there is nothing to *remove* from the Nix config.
`pkgs.rancher` on the work package list is the Rancher **Server CLI**, unrelated
to Rancher Desktop; it is not a conflict and stays.

`pkgs.docker` (client 29.6.1) and `docker-compose` are already declared in the
shared package list, and both `docker compose` and `docker buildx` resolve today.
Verified: `pkgs.docker` on darwin ships **only** the `docker` client binary — no
`dockerd`, no `containerd`, no `runc`. That is inherent to macOS, where the
engine is Linux-only and always needs a VM behind it.

Leftovers, and why each matters:

| Artifact | State | Consequence |
| --- | --- | --- |
| `~/.docker/config.json` | `credsStore: "desktop"`, `currentContext: "desktop-linux"` | Every `docker login` fails; CLI points at a socket that does not exist |
| `~/.docker/cli-plugins/*` | 16 dangling symlinks into `/Applications/Docker.app` | Dead entries shadowing nothing today, but noise |
| `/usr/local/bin/docker-credential-ecr-login` | dangling | **ECR auth broken** |
| `/usr/local/bin/kubectl`, `kubectl.docker` | dangling | **`kubectl` broken** |
| `/usr/local/bin/docker`, `docker-compose`, `docker-credential-desktop`, `docker-credential-osxkeychain` | dangling | Misleading clutter; do **not** shadow Nix (see PATH note) |
| `/Library/LaunchDaemons/com.docker.{socket,vmnetd}.plist` | present, root-owned | Dead daemons still load at boot |
| `/Library/PrivilegedHelperTools/com.docker.vmnetd` | present, root-owned | Orphaned privileged helper |
| `~/Library/Containers/com.docker.docker` | 21 GB | Stranded VM disk |
| `~/Library/Group Containers/group.com.docker` | 132 KB | Orphaned |
| `~/Library/Application Support/Docker Desktop` | 118 MB | Orphaned |
| `~/Library/Preferences/com.electron.dockerdesktop.plist` | present | Orphaned |

**PATH note.** `/usr/local/bin` is at position 2 in `PATH`, ahead of
`~/.nix-profile/bin` (5) and `/run/current-system/sw/bin` (17). An earlier draft
of this design claimed the dangling symlinks there *shadow* Nix packages. That is
**false**, and was verified false: PATH lookup requires an executable file, and a
broken symlink fails that test, so the lookup skips it and continues. A dangling
`/usr/local/bin/kubectl` does not prevent a later `/run/current-system/sw/bin/kubectl`
from resolving and running.

The consequences of the correction:

- `kubectl` and the credential helpers are fixed by declaring the packages, not
  by the purge. There is no ordering dependency between the two.
- Removing the dangling symlinks is **cleanup, not correctness**. It is still
  worth doing: they are misleading clutter, and if anything ever recreated
  `/Applications/Docker.app` they would spring back to life pointing at
  unlicensed binaries.
- The one genuinely broken-until-fixed item in `/usr/local/bin` is nothing; the
  real breakage is `credsStore: "desktop"` in `config.json`, which component 2
  repairs.

**Images in the old VM are unrecoverable.** Recovering them would require running
Docker Desktop, which is gone. Everything needed is re-derivable: `forge` pulls
`localstack/localstack:4.14` from a registry and builds `postgres-faketime:16`
locally from `docker-compose.faketime.yml`.

## Decisions

| Decision | Choice | Reasoning |
| --- | --- | --- |
| VM configuration | Nix-managed Colima template | VM shape lives in git and survives a new machine |
| Autostart | Manual `colima start` | Keeps 8 GB of 24 GB free when not building; fast login |
| Cleanup scope | Full purge, including root-owned artifacts | Reclaims 21 GB and removes dead root launch daemons |
| Collateral fixes | ECR helper, osxkeychain helper, `kubectl` | All three broke with Docker Desktop; same removal, same fix |
| Host scope | Work host only | `air` is personal, unrestricted, and has never run a container |
| `docker`/`docker-compose` placement | Unchanged, stays shared | Leaves `air` untouched on a machine not available to test |

`pkgs.colima` 0.10.3 supports `aarch64-darwin` and self-wraps `lima-full` 2.1.4,
`qemu` 11.0.1, and `krunkit` 1.3.2. No Homebrew involvement.

### Rejected: fully declarative `~/.docker/config.json`

A `home.file.".docker/config.json"` entry is a read-only symlink into the Nix
store. Colima's `autoActivate: true` writes `currentContext` on start, and
`docker login` writes `auths`; both would fail. This is the same class of trap
that produced the current broken `credsStore: "desktop"` state, inverted. The
design merges into the file instead, keeping it writable.

## Components

### 1. `flake.nix`

Add to the `lib.optionals isWork` package list, alphabetically:
`amazon-ecr-credential-helper`, `colima`, `docker-credential-helpers`, `kubectl`.

`docker` and `docker-compose` stay in the shared list, unchanged.

Thread `isWork` through to home-manager so the new module can gate itself:

```nix
home-manager.extraSpecialArgs = { inherit helix-steel vim-hx isWork; };
```

Add `./colima.nix` to the home-manager `imports` list.

The two credential helper binaries (`docker-credential-osxkeychain`,
`docker-credential-ecr-login`) must be on `PATH` for the Docker CLI to invoke
them. As `environment.systemPackages` they land in `/run/current-system/sw/bin`,
which is on `PATH`. Per the PATH note above, the dangling `/usr/local/bin`
entries of the same name do not interfere, so this component stands alone and
does not depend on component 3.

### 2. `colima.nix` and `colima-template.yaml`

A home-manager module, entirely wrapped in `lib.mkIf isWork`, with two
responsibilities. It follows the existing one-file-per-tool convention and takes
`isWork` from `extraSpecialArgs`.

**The VM template.** Written as
`home.file.".colima/_templates/default.yaml".source = ./colima-template.yaml`,
matching the sidecar-config pattern in `zellij.nix` and `herdr.nix`. Colima reads
this template to stamp out `~/.colima/default/colima.yaml` when creating an
instance; it never writes to the template, so a read-only store symlink is safe.
Path verified via `colima template --print`.

Values that differ from Colima's on-disk template defaults:

| Field | Value | Why |
| --- | --- | --- |
| `cpu` | `6` | Of 12 cores |
| `memory` | `8` | Of 24 GB |
| `vmType` | `vz` | Template default is `qemu`; `vz` is Apple Virtualization and is required for Rosetta |
| `mountType` | `virtiofs` | Template default is `sshfs`; virtiofs is substantially faster |
| `rosetta` | `true` | Fast amd64 emulation for ECR images built `linux/amd64` |
| `disk` | `100` | Colima's default, stated explicitly |
| `mounts` | `[]` | Colima's default, meaning `$HOME` mounted **writable** |

Colima's template file defaults genuinely diverge from what `colima start --help`
advertises as flag defaults (`qemu`/`sshfs` on disk versus `vz`/`virtiofs` in
help text). The template is what governs instance creation, so these must be set
explicitly rather than relied upon.

`mounts: []` is retained deliberately. Colima's own template comment states
"Colima default behaviour: `$HOME` is mounted as writable," which is what makes
`forge`'s `./localstack-init:/etc/localstack/init/ready.d` bind mount work with
no additional configuration, since `~/Code/forge` lives under `$HOME`.

**The Docker config merge.** A `home.activation` entry using
`lib.hm.dag.entryAfter [ "writeBoundary" ]` and `${pkgs.jq}/bin/jq` — the
activation-script pattern already present in `macos-apps-fix.nix`. Idempotent, so
it is safe on every rebuild. It:

- sets `credsStore` to `osxkeychain`, replacing the dead `desktop` value
- sets `credHelpers` to `ecr-login` for `467554678334.dkr.ecr.us-west-2.amazonaws.com`
  and `600461924372.dkr.ecr.us-west-1.amazonaws.com`
- removes the orphaned Docker Desktop `plugins` and `features` hook blocks
- leaves `auths` untouched, since `docker login` owns it
- deletes `currentContext` **only** when it still equals `desktop-linux`,
  leaving any real value (such as `colima`) alone
- creates `~/.docker/config.json` if absent

The `currentContext` handling is not cosmetic. Verified: once component 3 deletes
`~/.docker/contexts`, a `currentContext` of `desktop-linux` makes `docker ps` fail
with `context not found` — a harder failure than today's clean "cannot connect to
the daemon". Clearing the stale value lets the CLI fall back to `default` and
removes any ordering dependency on Colima's `autoActivate` repairing it.

### 3. `scripts/purge-docker-desktop.sh`

A one-shot, idempotent, manually run script. Not an activation script: it is a
destructive host operation that should run once per machine, not on every
rebuild. Committed rather than pasted into the terminal so it is reusable and
reviewable.

Order of operations:

1. `launchctl bootout system/com.docker.vmnetd` and `system/com.docker.socket`,
   tolerating absence.
2. Delete `/Library/LaunchDaemons/com.docker.socket.plist`,
   `/Library/LaunchDaemons/com.docker.vmnetd.plist`, and
   `/Library/PrivilegedHelperTools/com.docker.vmnetd`.
3. Delete the seven `/usr/local/bin` symlinks — `docker`, `docker-compose`,
   `docker-credential-desktop`, `docker-credential-ecr-login`,
   `docker-credential-osxkeychain`, `kubectl`, `kubectl.docker` — each guarded by
   a broken-symlink test (`[ -L "$p" ] && [ ! -e "$p" ]`) so the script can only
   ever remove a *dangling* link and never a live binary.
4. `rm -rf ~/Library/Containers/com.docker.docker` (21 GB),
   `~/Library/Group Containers/group.com.docker`,
   `~/Library/Application Support/Docker Desktop`, and
   `~/Library/Preferences/com.electron.dockerdesktop.plist`.
5. Remove the Docker Desktop-specific contents of `~/.docker` — `cli-plugins`,
   `bin`, `desktop-build`, `docker-next`, `gordon`, `models`, `modules`,
   `mutagen`, `sandboxes`, `run`, `contexts`, `daemon.json` — while leaving
   `config.json` in place for component 2's merge to repair.

Steps 1–3 need `sudo`; steps 4–5 do not. The script requires `sudo` up front and
reports what it removed and what it skipped as already-absent.

## Verification

Ordered, each step gating the next:

1. `nix-switch`, then `nix-apply`.
2. `scripts/purge-docker-desktop.sh`, then confirm `df -h /` reflects roughly
   21 GB reclaimed.
3. `command -v kubectl` resolves into `/run/current-system/sw/bin` and
   `kubectl version --client` succeeds. Expected to pass *before* the purge as
   well, since dangling links do not shadow; checked here to confirm the
   package declaration is what fixed it.
4. `colima start`. Then `colima status` reports running, and
   `docker context ls` shows `colima` as current.
5. `docker run --rm public.ecr.aws/docker/library/alpine echo ok` — engine and
   registry reachable.
6. `docker run --rm --platform linux/amd64 public.ecr.aws/docker/library/alpine uname -m`
   prints `x86_64` — proves Rosetta is active.
7. `docker pull` from `467554678334.dkr.ecr.us-west-2.amazonaws.com` with no
   manual `docker login`, against valid AWS credentials — proves `credHelpers`.
8. In `~/Code/forge`: `docker compose -f docker-compose.faketime.yml build` to
   re-create `postgres-faketime:16`, then `docker compose up` — proves bind
   mounts, port forwarding, and Compose end to end.
9. `colima stop`, `colima start`, and re-run step 5 — proves the template
   survives an instance restart.

## Out of scope

Flagged, not addressed here:

- `forge/docker-compose.yml` references `localstack/localstack:4.14` on Docker
  Hub even though `public.ecr.aws/localstack/localstack` exists and is used
  elsewhere in the codebase. That is a change to the `forge` repo, and it is the
  rate-limit issue the team raised.
- A Docker Engine `registry-mirrors` setting cannot solve the rate-limit problem
  generally. `public.ecr.aws/docker/library` is not a pull-through Docker Hub
  mirror, so image references must name it explicitly.
- `macos-apps-fix.nix` exists in the repo but is absent from the home-manager
  `imports` list. Unrelated to this work; noted only because this design cites it
  as a pattern reference.
- `air` gets no changes. It keeps a Docker client with no engine, which is the
  status quo. Adding `colima` there later is a one-line change.
