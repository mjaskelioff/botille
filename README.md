# 🤖⛓️ Botille

**Bot** + Bas**tille** — a prison for your AI agent.

Run coding agents inside a sandboxed, LAN-isolated rootless Podman container. Everything defined in a single Nix flake — nothing to install. See [DESIGN.md](DESIGN.md) for architecture details.

## 📋 Prerequisites

- [Nix](https://nixos.org/) (with flakes enabled)
- Rootless Podman host support — on Linux the Podman binary itself is provided by Nix, but your host must support rootless containers (user namespaces enabled, `/etc/subuid` + `/etc/subgid` configured). On NixOS, `virtualisation.podman.enable = true` handles this.
- Supported platforms: `x86_64-linux`, `aarch64-linux`; `aarch64-darwin` with limitations (see [macOS](#-macos))

## 🔒 What it does

- 📦 Builds a reproducible OCI container image with Claude Code, Gemini CLI, GitHub Copilot CLI, OpenCode, Pi, Nix, git, and common dev tools
- 🌐 Blocks all LAN/private network access via iptables OCI hooks — only public internet allowed
- 🔑 Persists credentials and Nix store across runs via named Podman volumes
- 🧑 Runs rootless — no daemon, no root, your UID mapped into the container

## 🚀 Usage

```sh
# Drop into a containerized shell with claude on $PATH
nix run 'github:delirium-systems/botille'

# Pass a command to run inside the container (replaces default /bin/bash)
nix run 'github:delirium-systems/botille' -- claude

# Allow access to a service on the host (e.g. llama.cpp, ollama)
# The host service must bind to 127.0.0.1, not 0.0.0.0
# Inside the container, find the host IP with: ip route show default | awk '{print $3}'
nix run 'github:delirium-systems/botille' -- --host-port 8080
nix run 'github:delirium-systems/botille' -- --host-port 8080 --host-port 11434 claude

# Disable LAN restrictions (allow access to private/LAN IP ranges)
nix run 'github:delirium-systems/botille' -- --allow-lan
nix run 'github:delirium-systems/botille' -- --allow-lan claude

# Enter the project's direnv dev shell before running the command
nix run 'github:delirium-systems/botille' -- --devshell claude
nix run 'github:delirium-systems/botille' -- --devshell

# Expose ports to access web UIs from the host (e.g. opencode)
nix run 'github:delirium-systems/botille' -- --port 3000 opencode
nix run 'github:delirium-systems/botille' -- -p 8080:3000 -p 9090:9090

# Share the host's global Claude Code config with the container
nix run 'github:delirium-systems/botille' -- --share-claude claude
```

Your current directory is mounted at `/work` inside the container. File changes persist on the host; credentials and installed packages persist in Podman volumes.

Pre-built binaries are available from the `delirium-systems` cachix cache — the flake configures this automatically when `accept-flake-config = true` is set in your Nix config.

### Shell alias

```sh
alias botille="nix run 'github:delirium-systems/botille' --"
```

Then: `botille`, `botille claude`, `botille --host-port 8080`, `botille --allow-lan`, `botille --devshell claude`, `botille --port 3000 opencode`, `botille --share-claude claude`.

### Sharing your host Claude config

`--share-claude` mounts the host's global Claude Code configuration into the container's config directory (`CLAUDE_CONFIG_DIR=/home/user/.config/claude`): `~/.claude/CLAUDE.md` and `~/.claude/skills` read-only, and the current project's state directory (`~/.claude/projects/<munged path>` — memory, session transcripts) read-write, so container sessions read and update the same project memory as host sessions.  Only these three paths are shared; host credentials, settings, and other projects' transcripts stay outside the container.

Inside the container, `claude-yolo` is a shell alias for `claude --dangerously-skip-permissions` — it runs Claude Code with no permission prompts.

### API keys

Authenticate interactively inside the container on first run — credentials persist in the `botille-home` volume. Alternatively, pass keys via environment variables by editing the launcher or using `podman run -e` directly.

### Customisation

Create a wrapper `flake.nix` to customise the container without forking. `lib.mkApp` accepts two module lists:

- **`extraHomeManagerModules`** — home-manager config (git identity, extra packages, shell aliases, etc.)
- **`extraContainerModules`** — podman run flags (volumes, ports, environment, DNS, capabilities, etc.; see `nix/container-options.nix` for all options)

```nix
{
  inputs.botille.url = "github:delirium-systems/botille";

  outputs = { self, botille }: {
    apps.x86_64-linux.default = botille.lib.mkApp {
      system = "x86_64-linux";
      extraHomeManagerModules = [
        {
          programs.git = {
            userEmail = "you@example.com";
            userName  = "Your Name";
          };
        }
      ];
      extraContainerModules = [
        {
          volumes = [ "/tmp/claude-dir:/home/user/.config/claude/:Z" ];
          environment.MY_VAR = "hello";
          dns = lib.mkForce [ "8.8.8.8" ];
        }
      ];
    };
  };
}
```

Then `nix run .` to use your customised container. Modules merge with standard NixOS semantics (lists concatenate, attrsets merge by key). Use `lib.mkForce` to replace defaults instead of merging. Runtime CLI flags (`-v`, `-p`) still work and append after declarative ones.

> **Note:** customised images are not in the cachix cache and will be built locally on first use.

## 🍎 macOS

On macOS, Podman runs Linux containers inside a lightweight VM (`podman machine`).  The container image, and everything in it, is exactly the same Linux image; only the launcher runs natively on the Mac.  Setup is as follows:

1. Install Podman and start a machine.  The launcher uses the host's `podman` (the client must match the machine's server version), so Nix does not provide it on macOS:

   ```sh
   brew install podman
   podman machine init
   podman machine start
   ```

2. Let Nix substitute the image.  The image is a Linux derivation that a Mac cannot build, so it must come from the binary cache.  Either add yourself to `trusted-users` in `/etc/nix/nix.conf` (then restart the nix daemon) and run with `--accept-flake-config`, or add the substituters and keys from `nix/caches.nix` to `/etc/nix/nix.conf` directly.

3. Run botille from a project directory under `/Users` — the podman machine only shares `/Users`, `/private`, `/tmp`, `/var/folders`, and `/Volumes` with the VM.

   ```sh
   nix run --accept-flake-config 'github:delirium-systems/botille'
   ```

### macOS limitations

- **No LAN blocking.**  The firewall is enforced by OCI hooks that run on the container host with Nix-store binaries; on macOS the container host is the podman machine VM, which cannot see the Mac's Nix store, and the remote Podman client has no `--hooks-dir`.  The launcher prints a warning: the container can reach your LAN.  The rest of the sandbox (rootless container inside a VM, only `$PWD` bind-mounted) still applies.
- **`--host-port` has no effect.**  There is no firewall to open, and pasta's gateway mapping points at the VM, not the Mac.  Services running on the Mac are reachable from the container at `host.containers.internal`.
- **Images missing from the cache cannot be built locally.**  A Mac cannot build Linux derivations, and customised `mkApp` images are never in the cache.  `scripts/mac-build-image.sh` builds the image inside the podman machine and prints the (sudo) command that imports it into the host store.

## ⚙️ How it works

1. **Launcher** checks if the current container image is already loaded in Podman; reloads only when the Nix store path changes
2. **OCI hooks** apply iptables rules in two stages: REJECT rules blocking RFC1918, CGNAT, and link-local ranges at `createContainer` (before the process starts), then an ACCEPT rule for the container's own IP at `poststart` (so pasta can forward exposed ports). `CAP_NET_ADMIN`/`CAP_NET_RAW` are dropped so rules are immutable from inside
3. **Entrypoint** copies the image's Nix store to a persistent volume (first run only), registers store paths in the Nix DB, pins a GC root, and runs home-manager activation
4. **Container starts** with your `$PWD` at `/work`, tools on `$PATH`, DNS forced to 1.1.1.1/1.0.0.1

### Volumes

| Mount | Podman volume | Purpose |
|---|---|---|
| `/work` | bind: host `$PWD` | Project files (read-write) |
| `/home/user` | `botille-home` | Credentials, configs, shell history |
| `/var/nix-store` | `botille-nix` | Nix store (persists `nix shell`/`nix-env` installs) |

Reset all state: `podman volume rm botille-home botille-nix`

## 🛡️ Security

The primary security boundary is the **rootless Podman container**: the agent runs as an unprivileged user with no host network access to LAN/private ranges, and only the working directory is bind-mounted.
`--host-port PORT` opens a surgical exception for a single TCP port on the host — the host service **must** bind to `127.0.0.1` to prevent LAN exposure.
`--allow-lan` disables the network firewall entirely for that run — use only when needed.

Claude Code's permission rules (`~/.config/claude/settings.json`) provide a secondary, **advisory** layer. `Read` denies for credential paths (`.ssh`, `.aws`, `.gnupg`, etc.) are enforced by the Read tool. `Bash` deny rules match on literal argument strings only — they do not survive shell expansion or variable indirection, so they prevent accidental access but are not a hard boundary.

**Do not rely on the permission rules to protect secrets.** Keep sensitive files out of the bind-mounted working directory, and treat anything inside the container as potentially visible to the agent.

See [DESIGN.md](DESIGN.md) for the full threat model.

## 🔧 Troubleshooting

- **First run is slow** — Nix store is copied to the persistent volume. Subsequent runs reuse it.
- **`podman load` fails with `copy_file_range: is a directory`** — the image already exists. Run `podman rmi botille:latest` then retry. The launcher handles this automatically.
- **Reset everything** — `podman volume rm botille-home botille-nix` removes all persistent state.
