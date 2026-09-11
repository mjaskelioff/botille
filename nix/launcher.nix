{
  pkgs,
  container,
  hooksDir,
  podmanFlags,
  hostPorts ? [ ],
  allowLan ? false,
}:
let
  inherit (pkgs.lib) optionals optionalString;
  isDarwin = pkgs.stdenv.isDarwin;
  staticFlags = builtins.concatStringsSep " \\\n      " podmanFlags;
  hostPortsInit = builtins.concatStringsSep " " (map toString hostPorts);
  allowLanInit = if allowLan then "true" else "false";
  # On Darwin the hooks are skipped entirely: podman-remote has no
  # --hooks-dir, and the hook scripts live in the Mac's Nix store, which
  # the podman machine VM cannot see.
  hooksFlag = optionalString (hooksDir != null) ''--hooks-dir "${hooksDir}"'';
in
pkgs.writeShellApplication {
  name = "botille-run";
  # On Darwin, podman must come from the host: the client has to match the
  # podman machine's server version, and the machine is managed outside Nix.
  runtimeInputs = optionals (!isDarwin) [ pkgs.podman ];
  text = ''
    ${optionalString isDarwin ''
      if ! command -v podman >/dev/null 2>&1; then
        echo "botille: podman not found — install it (e.g. brew install podman), then: podman machine init && podman machine start" >&2
        exit 1
      fi
      machine_state=$(podman machine inspect --format '{{.State}}' 2>/dev/null || true)
      if [ "$machine_state" != "running" ]; then
        echo "botille: no running podman machine (state: ''${machine_state:-none})" >&2
        echo "botille: run: podman machine start (or podman machine init first)" >&2
        exit 1
      fi
      case "$PWD" in
        /Users/* | /private/* | /tmp/* | /var/folders/* | /Volumes/*) ;;
        *)
          echo "botille: warning: $PWD is outside the podman machine's default shared directories (/Users, /private, /tmp, /var/folders, /Volumes); the /work mount may appear empty" >&2
          ;;
      esac
    ''}
    image="botille:latest"
    marker_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/botille"
    marker_file="$marker_dir/loaded-image"
    nix_store_path="${container}"

    # Only check podman when the marker file is missing or stale —
    # avoids a ~1-2s podman image exists call on the hot path.
    if ! [ -f "$marker_file" ] || [ "$(<"$marker_file")" != "$nix_store_path" ]; then
      echo "botille: loading image from $nix_store_path" >&2
      podman rmi "$image" 2>/dev/null || true
      podman load < "$nix_store_path"
      mkdir -p "$marker_dir"
      printf '%s' "$nix_store_path" > "$marker_file"
      echo "botille: image loaded" >&2
    else
      echo "botille: image up to date" >&2
    fi

    tty_flag=""
    if [ -t 0 ]; then
      tty_flag="-it"
    fi
    # Forward host terminal identity so CLI tools (claude, delta, etc.)
    # can detect the real emulator and enable full colour/highlighting.
    term_env=""
    for _var in \
      TERM_PROGRAM TERM_PROGRAM_VERSION \
      KITTY_WINDOW_ID KITTY_PID \
      ALACRITTY_LOG ALACRITTY_SOCKET \
      WT_SESSION \
      KONSOLE_VERSION \
      GNOME_TERMINAL_SERVICE \
      VTE_VERSION \
      XTERM_VERSION \
      TERMINATOR_UUID \
      TILIX_ID \
    ; do
      eval "_val=\''${!_var:-}"
      if [ -n "$_val" ]; then
        term_env="$term_env -e $_var=$_val"
      fi
    done

    # Forward host timezone
    tz_env=""
    if [ -n "''${TZ:-}" ]; then
      tz_env="-e TZ=$TZ"
    fi
    tz_mount=""
    ${
      if isDarwin then
        # Bind sources resolve inside the podman machine VM, so mounting
        # /etc/localtime would pick up the VM's clock; derive TZ from the
        # Mac's /etc/localtime symlink instead.
        ''
          if [ -z "$tz_env" ]; then
            _lt=$(readlink /etc/localtime 2>/dev/null || true)
            case "$_lt" in
              *zoneinfo/*) tz_env="-e TZ=''${_lt#*zoneinfo/}" ;;
            esac
          fi
        ''
      else
        ''
          if [ -f /etc/localtime ]; then
            tz_mount="-v /etc/localtime:/etc/localtime:ro"
          fi
        ''
    }

    # Runtime flags — these layer on top of the declarative config
    allow_lan=${allowLanInit}
    devshell=false
    share_claude=false
    port_flags=()
    host_ports=(${hostPortsInit})
    volume_flags=()
    container_args=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --allow-lan)
          allow_lan=true
          shift
          ;;
        --devshell)
          devshell=true
          shift
          ;;
        --share-claude)
          share_claude=true
          shift
          ;;
        -p|--port)
          if [ $# -lt 2 ]; then
            echo "botille: $1 requires an argument (e.g. --port 3000)" >&2
            exit 1
          fi
          port_flags+=("-p" "$2")
          shift 2
          ;;
        --port=*)
          port_flags+=("-p" "''${1#--port=}")
          shift
          ;;
        -v|--volume)
          if [ $# -lt 2 ]; then
            echo "botille: $1 requires an argument (e.g. -v /host/path:/container/path)" >&2
            exit 1
          fi
          volume_flags+=("-v" "$2")
          shift 2
          ;;
        --volume=*)
          volume_flags+=("-v" "''${1#--volume=}")
          shift
          ;;
        --host-port)
          if [ $# -lt 2 ]; then
            echo "botille: $1 requires a port number (e.g. --host-port 8080)" >&2
            exit 1
          fi
          if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ] || [ "$2" -gt 65535 ]; then
            echo "botille: invalid port: $2 (must be 1-65535)" >&2
            exit 1
          fi
          host_ports+=("$2")
          shift 2
          ;;
        --host-port=*)
          _hp="''${1#--host-port=}"
          if ! [[ "$_hp" =~ ^[0-9]+$ ]] || [ "$_hp" -lt 1 ] || [ "$_hp" -gt 65535 ]; then
            echo "botille: invalid port: $_hp (must be 1-65535)" >&2
            exit 1
          fi
          host_ports+=("$_hp")
          shift
          ;;
        *)
          container_args+=("$1")
          shift
          ;;
      esac
    done
    ${
      if isDarwin then
        ''
          lan_annotation=""
          host_port_annotation=""
          if [ "$allow_lan" != true ]; then
            echo "botille: warning: LAN blocking is unavailable on macOS (the firewall hooks are Linux-only); the container can reach your LAN" >&2
          fi
          if [ ''${#host_ports[@]} -gt 0 ]; then
            echo "botille: note: --host-port has no effect on macOS; services on the Mac are reachable at host.containers.internal" >&2
          fi
        ''
      else
        ''
          lan_annotation="--annotation io.botille.block-lan=true"
          if [ "$allow_lan" = true ]; then
            lan_annotation=""
          fi
          host_port_annotation=""
          if [ ''${#host_ports[@]} -gt 0 ]; then
            host_port_list=$(IFS=,; echo "''${host_ports[*]}")
            host_port_annotation="--annotation io.botille.allow-host-tcp=$host_port_list"
          fi
        ''
    }
    devshell_env=""
    if [ "$devshell" = true ]; then
      devshell_env="-e BOTILLE_DEVSHELL=1"
    fi

    # --share-claude: expose the host's global Claude Code config inside the
    # container.  The image sets CLAUDE_CONFIG_DIR=/home/user/.config/claude,
    # so mounts target that directory, not ~/.claude.  Global instructions and
    # skills are read-only; the per-project state (memory, transcripts) is
    # read-write so container sessions persist to the host.  Claude Code keys
    # project state by the working directory with every non-alphanumeric
    # character replaced by "-"; inside the container the project is always
    # /work, hence the fixed "-work" destination.
    if [ "$share_claude" = true ]; then
      _host_claude="$HOME/.claude"
      _cfg=/home/user/.config/claude
      if [ -f "$_host_claude/CLAUDE.md" ]; then
        volume_flags+=("-v" "$_host_claude/CLAUDE.md:$_cfg/CLAUDE.md:ro")
      fi
      if [ -d "$_host_claude/skills" ]; then
        volume_flags+=("-v" "$_host_claude/skills:$_cfg/skills:ro")
      fi
      _proj="$_host_claude/projects/''${PWD//[^a-zA-Z0-9]/-}"
      mkdir -p "$_proj"
      volume_flags+=("-v" "$_proj:$_cfg/projects/-work")
    fi

    cidfile=$(mktemp -u "/tmp/botille-cid.XXXXXX")
    cleanup() {
      if [ -f "$cidfile" ]; then
        ( podman rm "$(cat "$cidfile")" >/dev/null 2>&1; rm -f "$cidfile" ) &
        disown
      fi
    }
    trap cleanup EXIT

    echo "botille: starting container" >&2
    # shellcheck disable=SC2086
    podman ${hooksFlag} run \
      ${staticFlags} \
      $tty_flag \
      $lan_annotation \
      $host_port_annotation \
      $term_env \
      $devshell_env \
      $tz_env \
      $tz_mount \
      "''${port_flags[@]}" \
      "''${volume_flags[@]}" \
      --detach-keys="" \
      --cidfile "$cidfile" \
      -v "$PWD:/work" \
      "$image" "''${container_args[@]}"
  '';
}
