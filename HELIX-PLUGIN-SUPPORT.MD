# Helix Plugin Support (Steel fork)

## Status

Plugin support is not yet in upstream Helix. PR [#8675](https://github.com/helix-editor/helix/pull/8675) ("Add Steel as an optional plugin system") is open and draft as of July 2026, blocking on a separate event-system PR (#8021). This configuration tracks the custom fork by the PR author ([mattwparas/helix](https://github.com/mattwparas/helix), branch `steel-event-system`) which is the only way to run plugins today.

## What was set up

Two new flake inputs in `flake.nix`:

- **`helix-steel`** — `github:mattwparas/helix/steel-event-system` (`flake = false`): the Steel-enabled Helix fork
- **`vim-hx`** — `github:mattwparas/vim.hx` (`flake = false`): a Vim-keybinding plugin written in Steel/Scheme

Both are passed to home-manager modules via `home-manager.extraSpecialArgs`.

`helix.nix` was rewritten to:

1. Build the steel fork from source using `rustPlatform.buildRustPackage` (a fresh call, not `overrideAttrs` — see issues below)
2. Override `pkgs.helix`'s `helix-unwrapped` with the steel build so tree-sitter grammars still get wrapped correctly
3. Symlink all vim.hx `.scm` files into `~/.local/share/steel/cogs/vim-hx/` (Steel's hardcoded module root)
4. Write `~/.config/helix/init.scm` via `home.file` to load and activate the plugin at startup

## Issues worked around

### `overrideAttrs` can't reach the vendor derivation

`buildRustPackage` creates a `fetchCargoVendor` sub-derivation internally before `overrideAttrs` runs. Overriding `cargoHash` via `overrideAttrs` on `pkgs.helix-unwrapped` has no effect — the vendor drv is already fixed to the upstream Cargo.lock hash. A fresh `rustPlatform.buildRustPackage` call was required.

### `cargoHash` / `fetchCargoVendor` gets 403s from crates.io in the nix sandbox

Using `cargoHash = ""` to trigger a hash-mismatch error failed because `fetchCargoVendor` (the Python-based crate downloader) hit HTTP 403 rate-limit responses from crates.io inside the build sandbox on macOS (macOS does not support Linux-style network sandboxing, but the 403 is a crates.io policy, not a sandbox block).

**Workaround:** ran `cargo vendor` manually against the steel fork's source (already fetched into `/nix/store`), then computed the hash with `nix hash path`. Switched from `cargoHash` to `cargoLock` with `outputHashes` for the git dependencies, which uses `builtins.fetchGit` instead of the crates.io downloader and avoids the issue entirely.

### Steel's module resolver ignores `add-to-load-path!` on startup

`init.scm` is evaluated before the load path override takes effect for `require`. Placing the plugin files in `~/.config/helix/lib/` and calling `(add-to-load-path! ...)` first did not work. Steel resolves `require` paths from its hardcoded default: `~/.local/share/steel/cogs/`. Moving the symlinks there fixed it.

### Tree-sitter grammars: `.so` vs `.dylib` on macOS

The `helix-steel` binary expects grammar files with a `.dylib` extension on macOS (hardcoded in `helix-loader/src/grammar.rs`), but the `nixpkgs` `helix` wrapper builds all grammars as `.so` files — even on Darwin. This causes `Tree-sitter parser: None` for every language and no syntax highlighting regardless of theme. The issue is tracked upstream as helix PR [#14982](https://github.com/helix-editor/helix/pull/14982).

**Symptom:** `hx --health <lang>` shows `Tree-sitter parser: None` alongside `Highlight queries: ✓`.

**Fix:** `helix.nix` creates a `grammarsDylib` derivation that builds a directory of `.dylib` symlinks pointing at the existing `.so` files, then mounts it at `~/.config/helix/runtime/grammars` — the first path in Helix's runtime search order:

```nix
helixRuntime = pkgs.helix.runtime;
grammarsDylib = pkgs.runCommand "helix-grammars-dylib" { } ''
  mkdir -p $out
  for f in ${helixRuntime}/grammars/*.so; do
    name=$(basename "$f" .so)
    ln -s "$f" "$out/$name.dylib"
  done
'';
# in home.file:
".config/helix/runtime/grammars".source = grammarsDylib;
```

## Relevant files

| File | What changed |
|---|---|
| `flake.nix` | Added `helix-steel` and `vim-hx` inputs; added `home-manager.extraSpecialArgs` |
| `helix.nix` | Full rewrite: custom `buildRustPackage`, `pkgs.helix.override`, `home.file` for plugin and init.scm |
| `flake.lock` | Two new locked inputs |

## Switching back to mainline once PR #8675 merges

1. Remove the `helix-steel` and `vim-hx` inputs from `flake.nix`
2. Remove them from the `outputs` destructure and `home-manager.extraSpecialArgs`
3. Restore `helix.nix` to its original form (re-add `package = pkgs.helix` or just drop the `package` line entirely since that is the default)
4. The `init.scm` and `cogs/vim-hx/` files can stay or be removed — once upstream ships Steel, the `forge` package manager will handle plugin installs properly and the manual symlinks can go away
5. Run `nix-switch`

The `vim.hx` plugin itself should be compatible with the upstream Steel implementation — it is pure Scheme and has no fork-specific dependencies.
