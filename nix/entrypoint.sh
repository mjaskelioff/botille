#!/usr/bin/env bash
set -euo pipefail

# Set up writable /nix by copying the image's store into a persistent
# volume on first run (or when the image changes), then bind-mounting
# the volume over /nix.
#
# cp --reflink=auto clones the tree instantly on CoW filesystems
# (btrfs, xfs); falls back to a regular copy on ext4 etc.  This
# replaces fuse-overlayfs, which caused CPU saturation when Nix wrote
# large file trees (e.g. a nixpkgs source) through FUSE — and also
# required working around SQLite locking issues on overlayfs.
nix_vol="/var/nix-store"
nix_data="$nix_vol/nix"
nix_marker="$nix_vol/.botille-image"
needs_init=false
if ! [ -f "$nix_marker" ] || [ "$(<"$nix_marker")" != "@imageClosureInfo@" ]; then
  needs_init=true
elif ! [ -d "$nix_data/store/$(basename @imageClosureInfo@)" ]; then
  # Marker matches but gc has removed image paths — repair.
  echo "Repairing Nix store (gc damage detected)…" >&2
  needs_init=true
fi

if [ "$needs_init" = true ]; then
  if [ -d "$nix_data/store" ]; then
    echo "Updating Nix store (preserving existing paths)…" >&2
    # Non-destructive merge: copy new image paths alongside old
    # ones so running containers keep their PATH entries working.
    # Only chmod the two directories we actually write into —
    # the store dir (new top-level entries) and the DB (wiped).
    # A recursive chmod of the entire store is very expensive.
    chmod u+w "$nix_data/store" 2>/dev/null || true
    for p in /nix/store/*; do
      [ -e "$nix_data/store/${p##*/}" ] || cp --reflink=auto -a "$p" "$nix_data/store/"
    done
    # Reset the registration DB from the new closure.
    # nix-store --load-db is not idempotent (UNIQUE constraint),
    # so we wipe the DB and reload cleanly.  Old paths keep their
    # files on disk — running containers still resolve them via
    # PATH.  nix-store --gc reclaims orphans when appropriate.
    chmod -R u+w "$nix_data/var/nix/db" 2>/dev/null || true
    rm -rf "$nix_data/var/nix/db"
  else
    echo "Initialising Nix store (first run)…" >&2
    cp --reflink=auto -a /nix "$nix_vol/"
  fi
  mount --bind "$nix_data" /nix
  mkdir -p /nix/var/nix/gcroots /nix/var/nix/db
  # The marker is written only after --load-db succeeds, so a
  # crash here causes a clean re-init on next run.
  nix-store --load-db < @imageClosureInfo@/registration
  # closureInfo doesn't list itself in its own registration, so the
  # GC root pointing to it would be dangling.  Load a second
  # registration that covers imageClosureInfo so gc honours the root.
  nix-store --load-db < @closureInfoReg@/registration
  printf '%s' "@imageClosureInfo@" > "$nix_marker"
else
  mount --bind "$nix_data" /nix
fi

# Protect image store paths from garbage collection.
# imageClosureInfo references the entire image closure, so this
# single GC root transitively keeps all image packages alive.
ln -sfn @imageClosureInfo@ /nix/var/nix/gcroots/botille-image

# Write a recovery helper to a stable location (on the volume,
# outside the nix store).  If the shell environment becomes
# unusable after an update, run: source /var/nix-store/botille-reload
cat > "$nix_vol/botille-reload" << 'RELOAD'
_p=""; for _d in /nix/store/*/bin; do [ -d "$_d" ] && _p="$_p:$_d"; done
export PATH="${_p#:}"; unset _p _d
unset BASH_COMPLETION_VERSINFO
[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc"
echo "Shell environment reloaded." >&2
RELOAD

# --- Migrate Claude config from the pre-.claude layout ---
# The image previously set CLAUDE_CONFIG_DIR=~/.config/claude; existing
# botille-home volumes hold live credentials there.  Move (not symlink:
# the agent-config installer refuses destinations under symlinked
# parents) before home-manager activation and before any agent starts.
if ! [ -e "@home@/.claude" ] && [ -d "@home@/.config/claude" ]; then
  mv "@home@/.config/claude" "@home@/.claude"
fi

# --- Activate home-manager (only when configuration changed) ---
mkdir -p "@home@/.local/state/nix/profiles"
hm_marker="@home@/.local/state/botille/hm-generation"
hm_generation="@hmActivation@"
if ! [ -f "$hm_marker" ] || [ "$(<"$hm_marker")" != "$hm_generation" ]; then
  # Clear new-format profiles that are incompatible with nix-env.
  # HM's installPackages uses nix-env; if the agent ran `nix profile install`
  # the default profile is converted to new-format and activation fails.
  prof="@home@/.local/state/nix/profiles/profile"
  if [ -e "$prof/manifest.json" ]; then
    rm -f "$prof" "$prof"-*-link
  fi
  "$hm_generation/activate" >&2
  mkdir -p "$(dirname "$hm_marker")"
  printf '%s' "$hm_generation" > "$hm_marker"
fi

# --- Preserve Claude's existing onboarding defaults at each project path ---
workdir="${BOTILLE_WORKDIR:-/work}"
claude_settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
if [ -f "$claude_settings" ]; then
  # Concurrent launches must not discard one another's project entries.
  # home-manager's claudeSettings activation takes the same lock.
  (
    flock 9
    settings_tmp=$(mktemp "$claude_settings.XXXXXX")
    trap 'rm -f "$settings_tmp"' EXIT
    # A malformed settings.json (interrupted write) must not abort the
    # entrypoint: skip the merge and keep the container usable.
    if jq --arg project "$workdir" '
      .projects[$project] = ({
        allowedTools: [],
        hasTrustDialogAccepted: true,
        hasCompletedOnboarding: true,
        hasTrustDialogHooksAccepted: true
      } * (.projects[$project] // {}))
    ' "$claude_settings" > "$settings_tmp"; then
      mv "$settings_tmp" "$claude_settings"
    else
      echo "botille: $claude_settings is not valid JSON; skipping onboarding merge" >&2
    fi
  ) 9>"$claude_settings.lock"
fi

# --- Ensure directories exist (tool-specific, not managed by home-manager) ---
mkdir -p "$workdir" \
  "@home@/.local/state/bash" \
  "@home@/.local/state/python" \
  "@home@/.local/state/node" \
  "@home@/.cache/python" \
  "@home@/.config/ripgrep" \
  "@home@/.config/npm" \
  "@home@/.cache/npm" \
  "@home@/.config/wget" \
  "@home@/.local/state/gemini" \
  "@home@/.local/state/botille"

# --- Opt-in: enter direnv dev shell before running the command ---
if [ "${BOTILLE_DEVSHELL:-}" = "1" ] && [ -f "$workdir/.envrc" ]; then
  direnv allow "$workdir"
  set -- direnv exec "$workdir" "$@"
fi

# SYS_ADMIN is needed for the startup bind mount, not for the command.
# Bubblewrap refuses to run with inherited capabilities in a non-setuid
# process.  Clearing this capability also prevents agents from retaining
# the entrypoint's mount privileges; other configured capabilities remain
# in the ambient set on purpose (the workload asked for them), at the cost
# of re-breaking bubblewrap sandboxes; see the capabilities option in
# nix/container-options.nix.
exec setpriv --inh-caps=-sys_admin --ambient-caps=-sys_admin "$@"
