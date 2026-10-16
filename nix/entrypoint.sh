#!/usr/bin/env bash
set -euo pipefail

# Add the image to the shared store without replacing existing registrations.
nix_vol="/var/nix-store"
@initStore@ /nix "$nix_vol" "${BOTILLE_IMAGE_CLOSURE:?}" "${BOTILLE_IMAGE_REGISTRATION:?}"
mount --bind "$nix_vol/nix" /nix

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
