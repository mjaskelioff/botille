# Home-manager configuration baked into the Botille container image.
# This module is loaded as the base configuration; callers can append
# extraHomeManagerModules via mkBotille / lib.mkApp to override anything here.
{
  lib,
  pkgs,
  ...
}:
let
  # Base Claude settings managed declaratively by Nix.
  # Keys defined here take priority over runtime values (deep merge).
  # Runtime-added keys (mcpServers, enabledPlugins, etc.) are preserved.
  claudeSettings = builtins.toJSON {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    # model = "claude-opus-4-7";
    # effortLevel = "high";
    teammateMode = "auto";
    env = {
      # CLAUDE_CODE_EFFORT_LEVEL = "max";
      CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "true";
    };
    mcpServers = {
      serena = {
        command = "serena";
        args = [
          "start-mcp-server"
          "--project-from-cwd"
        ];
      };
    };
    enabledPlugins = {
      "hls@claude-hls" = true;
    };
    projects = {
      "/work" = {
        allowedTools = [ ];
        hasTrustDialogAccepted = true;
        hasCompletedOnboarding = true;
        hasTrustDialogHooksAccepted = true;
      };
    };
    permissions = {
      deny = [
        "Bash(* /home/user/.ssh*)"
        "Bash(* /home/user/.config/gnupg*)"
        "Bash(* /home/user/.aws*)"
        "Bash(* /home/user/.netrc*)"
        "Bash(* /home/user/.git-credentials*)"
        "Bash(* /home/user/.config/gh*)"
        "Bash(* /home/user/.config/claude/.credentials*)"
        "Bash(* /home/user/.config/git/credentials*)"
        "Bash(* /home/user/.config/pi/auth.json*)"
        "Read(/home/user/.config/claude/.credentials*)"
        "Read(/home/user/.ssh/**)"
        "Read(/home/user/.config/gnupg/**)"
        "Read(/home/user/.netrc)"
        "Read(/home/user/.aws/**)"
        "Read(/home/user/.config/gh/**)"
        "Read(/home/user/.config/git/credentials)"
        "Read(/home/user/.git-credentials)"
        "Read(/home/user/.config/pi/auth.json)"
      ];
      allow = [
        "Bash(*#*)"
        "Bash(*$(*)*)"
        "Edit(/tmp/**)"
        "Edit(/work/**)"
        "Read(/home/user/**)"
        "Read(/nix/**)"
        "Read(/tmp/**)"
        "Read(/work/**)"
        "WebFetch"
        "WebSearch"
        "Bash(alejandra:*)"
        "Bash(awk:*)"
        "Bash(b2sum:*)"
        "Bash(base64:*)"
        "Bash(basename:*)"
        "Bash(black:*)"
        "Bash(bun:*)"
        "Bash(bundle:*)"
        "Bash(cabal:*)"
        "Bash(cachix:*)"
        "Bash(cargo:*)"
        "Bash(cd:*)"
        "Bash(cat:*)"
        "Bash(chmod:*)"
        "Bash(chown:*)"
        "Bash(column:*)"
        "Bash(cp:*)"
        "Bash(curl:*)"
        "Bash(cut:*)"
        "Bash(date:*)"
        "Bash(deadnix:*)"
        "Bash(deno:*)"
        "Bash(df:*)"
        "Bash(diff:*)"
        "Bash(dig:*)"
        "Bash(dirname:*)"
        "Bash(du:*)"
        "Bash(env:*)"
        "Bash(fd:*)"
        "Bash(file:*)"
        "Bash(find:*)"
        "Bash(flake-checker:*)"
        "Bash(free:*)"
        "Bash(gem:*)"
        "Bash(gh:*)"
        "Bash(ghc:*)"
        "Bash(ghci:*)"
        "Bash(git:*)"
        "Bash(go:*)"
        "Bash(gofmt:*)"
        "Bash(gradle:*)"
        "Bash(grep:*)"
        "Bash(gunzip:*)"
        "Bash(gzip:*)"
        "Bash(head:*)"
        "Bash(hlint:*)"
        "Bash(home-manager:*)"
        "Bash(host:*)"
        "Bash(id:*)"
        "Bash(ionice:*)"
        "Bash(java:*)"
        "Bash(jless:*)"
        "Bash(jq:*)"
        "Bash(kotlin:*)"
        "Bash(less:*)"
        "Bash(ls:*)"
        "Bash(lsof:*)"
        "Bash(lua:*)"
        "Bash(luarocks:*)"
        "Bash(make:*)"
        "Bash(md5sum:*)"
        "Bash(mkdir:*)"
        "Bash(mktemp:*)"
        "Bash(more:*)"
        "Bash(mv:*)"
        "Bash(mvn:*)"
        "Bash(mypy:*)"
        "Bash(nc:*)"
        "Bash(nice:*)"
        "Bash(nix:*)"
        "Bash(nix-build:*)"
        "Bash(nix-env:*)"
        "Bash(nix-instantiate:*)"
        "Bash(nix-output-monitor:*)"
        "Bash(nix-prefetch-git:*)"
        "Bash(nix-prefetch-url:*)"
        "Bash(nix-shell:*)"
        "Bash(nix-store:*)"
        "Bash(nixfmt:*)"
        "Bash(nixos-rebuild:*)"
        "Bash(node:*)"
        "Bash(nom:*)"
        "Bash(npm:*)"
        "Bash(npx:*)"
        "Bash(nslookup:*)"
        "Bash(nvd:*)"
        "Bash(objdump:*)"
        "Bash(od:*)"
        "Bash(openssl:*)"
        "Bash(paste:*)"
        "Bash(ping:*)"
        "Bash(pip:*)"
        "Bash(pip3:*)"
        "Bash(pkg-config:*)"
        "Bash(pnpm:*)"
        "Bash(podman:*)"
        "Bash(poetry:*)"
        "Bash(printf:*)"
        "Bash(ps:*)"
        "Bash(psql:*)"
        "Bash(pytest:*)"
        "Bash(python:*)"
        "Bash(python3:*)"
        "Bash(readelf:*)"
        "Bash(realpath:*)"
        "Bash(rg:*)"
        "Bash(ruby:*)"
        "Bash(ruff:*)"
        "Bash(runghc:*)"
        "Bash(rustc:*)"
        "Bash(rustfmt:*)"
        "Bash(rustup:*)"
        "Bash(sed:*)"
        "Bash(sha256sum:*)"
        "Bash(sha512sum:*)"
        "Bash(sort:*)"
        "Bash(sqlite3:*)"
        "Bash(ss:*)"
        "Bash(stack:*)"
        "Bash(stat:*)"
        "Bash(statix:*)"
        "Bash(strace:*)"
        "Bash(strings:*)"
        "Bash(tail:*)"
        "Bash(tar:*)"
        "Bash(tee:*)"
        "Bash(timeout:*)"
        "Bash(touch:*)"
        "Bash(tr:*)"
        "Bash(traceroute:*)"
        "Bash(tree:*)"
        "Bash(tsc:*)"
        "Bash(uname:*)"
        "Bash(uniq:*)"
        "Bash(unzip:*)"
        "Bash(uv:*)"
        "Bash(watch:*)"
        "Bash(wc:*)"
        "Bash(wget:*)"
        "Bash(which:*)"
        "Bash(xargs:*)"
        "Bash(xxd:*)"
        "Bash(xz:*)"
        "Bash(yarn:*)"
        "Bash(yq:*)"
        "Bash(zip:*)"
        "Bash(zstd:*)"
      ];
    };
  };
in
{
  home = {
    username = "user";
    homeDirectory = "/home/user";
    stateVersion = "25.11";
    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
    };
  };

  # No systemd in container
  systemd.user.startServices = false;

  xdg.enable = true;

  # Serena config — written as a regular file (not a symlink) because serena
  # may need to write to it at runtime (e.g. adding project entries).
  home.activation.serenaConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cfg="$SERENA_HOME/serena_config.yml"
    mkdir -p "$(dirname "$cfg")"
    cat > "$cfg" << 'YAML'
    # Serena global config: disable tools that duplicate the host editor's
    # built-in capabilities.
    gui_log_window: false
    web_dashboard: false
    web_dashboard_open_on_launch: false
    projects: []
    excluded_tools:
      # Redundant with the host editor's built-in tools
      - read_file
      - create_text_file
      - list_dir
      - find_file
      - search_for_pattern
      - replace_content
      - execute_shell_command
      # Memory (no sandbox persistence for global memories)
      - write_memory
      - read_memory
      - list_memories
      - edit_memory
      - rename_memory
      - delete_memory
      # Management (not needed in sandbox)
      - initial_instructions
      - prepare_for_new_conversation
      - switch_modes
      - get_current_config
    YAML
  '';

  # Claude settings are written as a regular file (not a symlink) so that
  # Claude Code can modify it at runtime (e.g. to add MCP servers).
  # On home-manager activation, the existing file is deep-merged with the
  # Nix-managed base — Nix keys win, runtime-added keys are preserved.
  # The lock is shared with the entrypoint's project-entry merge so a
  # concurrently launching container cannot discard this write, nor the
  # other way around.
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings="$HOME/.config/claude/settings.json"
    base=${lib.escapeShellArg claudeSettings}
    mkdir -p "$(dirname "$settings")"
    (
      ${pkgs.util-linux}/bin/flock 9
      if [ -L "$settings" ]; then
        # First run after migration: replace the home-manager symlink
        rm "$settings"
        echo "$base" | ${pkgs.jq}/bin/jq . > "$settings"
      elif [ -f "$settings" ]; then
        # Merge: existing file is the base, Nix-managed keys win via deep
        # merge.  A malformed existing file (interrupted write) must not
        # fail activation, which would keep every container from starting,
        # so fall back to the Nix-managed base.
        if ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$settings" <(echo "$base") > "$settings.tmp"; then
          mv "$settings.tmp" "$settings"
        else
          rm -f "$settings.tmp"
          echo "claudeSettings: $settings is not valid JSON; resetting to the Nix-managed base" >&2
          echo "$base" | ${pkgs.jq}/bin/jq . > "$settings"
        fi
      else
        echo "$base" | ${pkgs.jq}/bin/jq . > "$settings"
      fi
    ) 9>"$settings.lock"
  '';

  programs = {
    bash = {
      enable = true;
    };

    starship = {
      enable = true;
      enableBashIntegration = true;
      settings = {
        add_newline = false;
        format = "[botille](bold blue) $directory$git_branch$git_status$cmd_duration$status$character";

        character = {
          success_symbol = "[❯](bold purple)";
          error_symbol = "[❯](bold red)";
        };

        directory = {
          style = "bold cyan";
          truncate_to_repo = false;
          truncation_length = 0;
          fish_style_pwd_dir_length = 0;
        };

        git_branch = {
          format = "[$symbol$branch(:$remote_branch)]($style) ";
          symbol = "⎇ ";
          style = "bold purple";
        };

        git_status.style = "bold red";

        status.disabled = false;

        cmd_duration.min_time = 3000;
      };
    };

    direnv.enable = true;
    direnv.nix-direnv.enable = true;

    delta = {
      enable = true;
      enableGitIntegration = true;
      options = {
        line-numbers = true;
        hunk-header-decoration-style = "";
      };
    };

    git = {
      enable = true;

      lfs.enable = true;

      settings = {
        alias = {
          hist = ''log --pretty=format:"%C(dim yellow)%h %C(dim white)%ad %C(bold cyan)|%C(auto) %s %C(white)- %an%C(auto)%d%C(reset)" --graph --date=local'';
          list-changed-files = "show --pretty= --name-only";
          list-gone-branches = "! git branch -vv | grep ': gone]' | awk '{print $1}'";
          pushfwl = "push --force-with-lease";
        };
        core.commentchar = ";";
        pull.rebase = true;
        push = {
          autoSetupRemote = true;
          followTags = true;
        };
        fetch = {
          prune = true;
          pruneTags = true;
          all = true;
        };
        help.autocorrect = "prompt";
        rebase = {
          autoStash = true;
          updateRefs = true;
        };
        http.postBuffer = 1048576000;
        credential.helper = "store";
        merge = {
          conflictStyle = "zdiff3";
          tool = "nvim";
        };
        mergetool = {
          prompt = false;
          keepBackup = false;
          nvim.cmd = ''nvim -d -c "wincmd l" -c "norm gg]c" "$LOCAL" "$MERGED" "$REMOTE"'';
        };
        status.submoduleSummary = true;
        diff = {
          tool = "nvim";
          algorithm = "histogram";
          mnemonicPrefix = true;
          renames = true;
        };
        init.defaultBranch = "master";
        advice = {
          detachedHead = false;
          skippedCherryPicks = false;
        };
        rerere = {
          enabled = true;
          autoUpdate = true;
        };
        branch.sort = "-committerdate";
        tag.sort = "version:refname";
        commit.verbose = true;
      };
    };
  };
}
