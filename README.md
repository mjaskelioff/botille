# 🤖⛓️ Botille

**Bot** + Bas**tille** — a prison for your AI agent.

Run coding agents inside a rootless Podman container.  Linux blocks LAN access by default; macOS currently allows LAN access.  The image and launcher are defined in a Nix flake.  See [DESIGN.md](DESIGN.md) for architecture details.

## 📋 Prerequisites

- [Nix](https://nixos.org/) (with flakes enabled)
- Rootless Podman host support — on Linux the Podman binary itself is provided by Nix, but your host must support rootless containers (user namespaces enabled, `/etc/subuid` + `/etc/subgid` configured). On NixOS, `virtualisation.podman.enable = true` handles this.
- Supported platforms: `x86_64-linux`, `aarch64-linux`; `aarch64-darwin` with limitations (see [macOS](#-macos))

## 🔒 What it does

- 📦 Builds a reproducible OCI container image with Claude Code, Codex CLI, Gemini CLI, GitHub Copilot CLI, OpenCode, Pi, Nix, git, and common dev tools
- 🌐 On Linux, blocks LAN/private network access via iptables OCI hooks; macOS has no LAN blocking
- 🔑 Persists credentials and Nix store across runs via named Podman volumes
- 🧑 Runs rootless — no daemon, no root, your UID mapped into the container

## 🚀 Usage

```sh
# Drop into a containerized shell with claude on $PATH
nix run 'github:mjaskelioff/botille'

# Pass a command to run inside the container (replaces default /bin/bash)
nix run 'github:mjaskelioff/botille' -- claude

# Run Codex
nix run 'github:mjaskelioff/botille' -- codex

# Allow access to a service on the host (e.g. llama.cpp, ollama)
# The host service must bind to 127.0.0.1, not 0.0.0.0
# Inside the container, find the host IP with: ip route show default | awk '{print $3}'
nix run 'github:mjaskelioff/botille' -- --host-port 8080
nix run 'github:mjaskelioff/botille' -- --host-port 8080 --host-port 11434 claude

# Disable LAN restrictions (allow access to private/LAN IP ranges)
nix run 'github:mjaskelioff/botille' -- --allow-lan
nix run 'github:mjaskelioff/botille' -- --allow-lan claude

# Enter the project's direnv dev shell before running the command
nix run 'github:mjaskelioff/botille' -- --devshell claude
nix run 'github:mjaskelioff/botille' -- --devshell

# Expose ports to access web UIs from the host (e.g. opencode)
nix run 'github:mjaskelioff/botille' -- --port 3000 opencode
nix run 'github:mjaskelioff/botille' -- -p 8080:3000 -p 9090:9090

# Share the host's global Claude Code config with the container
nix run 'github:mjaskelioff/botille' -- --share-claude claude

# Share only the current project's Claude memory and transcripts
nix run 'github:mjaskelioff/botille' -- --share-memory claude
```

Your current directory is mounted at `/work/<name>-<hash>` inside the container.  The name comes from the directory basename, and the hash comes from its physical absolute host path.  Repeated launches and symlink aliases use the same container path; directories with the same name at different host paths use different container paths.  File changes persist on the host.  Credentials and installed packages persist in Podman volumes.

Put Botille options before the container command.  Once the command starts, its arguments pass through unchanged: `botille --port 3000:3000 codex -p review` publishes a port and selects the Codex profile named `review`.  An explicit `--` also ends Botille option parsing.

Moving or renaming a host directory gives it a new container path.  Saved sessions from the previous `/work` layout remain in the home volume, but do not automatically become sessions for the new path.  No existing transcripts are rewritten or reassigned to a project.

The flake reads the `mjaskelioff-botille` cache and upstream binary caches when `accept-flake-config = true` is set in your Nix config.  A fork-specific image must also be built and cached, or built inside the Podman VM on macOS.  Selecting a GitHub fork does not select a different binary cache.  This fork is based on [delirium-systems/botille](https://github.com/delirium-systems/botille).

### Shell alias

```sh
alias botille="nix run 'github:mjaskelioff/botille' --"
```

Then: `botille`, `botille claude`, `botille codex`, `botille --host-port 8080`, `botille --allow-lan`, `botille --devshell claude`, `botille --port 3000 opencode`, `botille --share-claude claude`, `botille --share-memory claude`.

### Sharing your host Claude config

`--share-claude` mounts the host's global Claude Code configuration into the container's config directory (`CLAUDE_CONFIG_DIR=/home/user/.claude`): `~/.claude/CLAUDE.md` and `~/.claude/skills` read-only, and the current project's state directory (`~/.claude/projects/<munged path>` — memory, session transcripts) read-write, so container sessions read and update the same project memory as host sessions.  Only these three paths are shared; host credentials, settings, and other projects' transcripts stay outside the container.

`--share-memory` performs only the project-state mount, and `--share-claude` implies it.  Use `--share-memory` when the container home has its own agent configuration installed (for example an agent-config clone): the full `--share-claude` mounts would shadow the installed instructions and skills at the same paths, while the memory mount coexists with them.

Inside the container, `claude-yolo` is a shell alias for `claude --dangerously-skip-permissions` — it runs Claude Code with no permission prompts.

### Codex

Authenticate once from a project directory:

```sh
botille codex -c 'cli_auth_credentials_store="file"' login --device-auth
botille codex
```

Enable device-code login in your ChatGPT account or workspace if required.  Open the displayed link in your host browser and enter the code.  This flow does not need an inbound callback port.  Codex stores its file-based credentials and local state under `/home/user/.codex`, inside `botille-home`.  Keep the credential store set to `file` if you customize Codex configuration.  See the [Codex authentication documentation](https://learn.chatgpt.com/docs/auth).

Each project has a distinct working directory, so Codex can distinguish saved sessions and project trust while sharing the container's login.  Codex retains its normal sandbox and approval behavior.  Its packaged `bubblewrap` provides the inner Linux sandbox, including on macOS through the Podman VM.  The entrypoint releases its startup mount capability before running commands so it does not conflict with Bubblewrap.

For scripted use, stdin passes through and Botille startup messages go to stderr:

```sh
cat prompt.txt | botille codex exec -
botille codex exec --json "Summarize this repository" > result.jsonl
```

### API keys

Authenticate inside the container on first run.  Credentials persist in the `botille-home` volume.  For Codex API-key login, pass the host key through stdin:

```sh
printf '%s' "$OPENAI_API_KEY" | botille codex -c 'cli_auth_credentials_store="file"' login --with-api-key
```

Keep keys out of declarative Nix configuration, which becomes readable Nix store content.

### Customisation

Create a wrapper `flake.nix` to customise the container.  `lib.mkBotille` returns an `app` and its `container`; `lib.mkApp` remains available when only the app is needed.  Both accept the following module lists:

- **`extraHomeManagerModules`**: home-manager configuration, such as git identity, packages, and shell aliases.
- **`extraContainerModules`**: Podman settings, such as volumes, ports, environment, DNS, and capabilities.  See `nix/container-options.nix` for the options.

The following wrapper exposes apps and images for each supported platform, including the Linux image needed by the macOS builder:

```nix
{
  inputs.botille.url = "github:mjaskelioff/botille";

  outputs = { botille, ... }:
    let
      built = builtins.mapAttrs (system: _: botille.lib.mkBotille {
        inherit system;
        extraHomeManagerModules = [
          {
            programs.git.settings.user = {
              email = "you@example.com";
              name = "Your Name";
            };
          }
        ];
        extraContainerModules = [
          ({ lib, ... }: {
            ports = [ "127.0.0.1:3000:3000" ];
            environment.MY_VAR = "hello";
            dns = lib.mkForce [ "8.8.8.8" ];
          })
        ];
      }) {
        x86_64-linux = null;
        aarch64-linux = null;
        aarch64-darwin = null;
      };
    in {
      apps = builtins.mapAttrs (_: value: { default = value.app; }) built;
      packages = builtins.mapAttrs (_: value: { container = value.container; }) built;
    };
}
```

Then run `nix run .`.  On macOS, first run `/path/to/botille/scripts/mac-build-image.sh .` from the wrapper directory and import the built image as directed by the script.

Modules merge with standard NixOS semantics: lists concatenate, and attribute sets merge by key.  Use `lib.mkForce` to replace defaults.  Modules that use `lib` must receive it as an argument, as the example does.  Runtime CLI flags (`-v`, `-p`) append after declarative settings.

Custom images usually need a build.  Linux can build them directly; macOS uses the Podman VM or a Linux builder.

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
   nix run --accept-flake-config 'github:mjaskelioff/botille'
   ```

### macOS limitations

- **No LAN blocking.**  The firewall is enforced by OCI hooks that run on the container host with Nix-store binaries; on macOS the container host is the podman machine VM, which cannot see the Mac's Nix store, and the remote Podman client has no `--hooks-dir`.  The launcher prints a warning: the container can reach your LAN.  The rest of the sandbox (rootless container inside a VM, only `$PWD` bind-mounted) still applies.
- **`--host-port` has no effect.**  There is no firewall to open, and pasta's gateway mapping points at the VM, not the Mac.  Services running on the Mac are reachable from the container at `host.containers.internal`.
- **Images missing from the cache need a Linux build.**  A Mac cannot build Linux derivations natively.  Custom images need cache publication or a build in the Podman VM.  `scripts/mac-build-image.sh` builds the image inside the podman machine and prints the (sudo) command that imports it into the host store.

## ⚙️ How it works

1. **Launcher** checks the selected Podman backend for the image’s immutable tag and loads it if absent.  Pruning images or resetting the machine is handled on the next launch.
2. **On Linux, OCI hooks** apply iptables rules in two stages: REJECT rules blocking RFC1918, CGNAT, and link-local ranges at `createContainer` (before the process starts), then an ACCEPT rule for the container's own IP at `poststart` (so pasta can forward exposed ports). `CAP_NET_ADMIN`/`CAP_NET_RAW` are dropped so rules are immutable from inside
3. **Entrypoint** serializes image updates, copies missing store paths, adds their registrations to the existing database, retains a GC root for each image version, and runs home-manager activation
4. **Container starts** with your project at `/work/<name>-<hash>`, tools on `$PATH`, DNS forced to 1.1.1.1/1.0.0.1

### Volumes

| Mount | Podman volume | Purpose |
|---|---|---|
| `/work/<name>-<hash>` | bind: physical host `$PWD` | Project files (read-write) |
| `/home/user` | `botille-home` | Credentials, configs, shell history |
| `/var/nix-store` | `botille-nix` | Nix store (persists `nix shell`/`nix-env` installs) |

Reset all state: `podman volume rm botille-home botille-nix`

## 🛡️ Security

The primary security boundary is the **rootless Podman container**.  The working directory is bind-mounted read-write; explicit sharing options expose additional paths.  Linux blocks LAN/private ranges by default.  **macOS does not block LAN access**.
`--host-port PORT` opens a surgical exception for a single TCP port on the host — the host service **must** bind to `127.0.0.1` to prevent LAN exposure.
`--allow-lan` disables the network firewall entirely for that run — use only when needed.

Claude Code's permission rules (`~/.claude/settings.json`) provide a secondary, **advisory** layer. `Read` denies for credential paths (`.ssh`, `.aws`, `.gnupg`, etc.) are enforced by the Read tool. `Bash` deny rules match on literal argument strings only — they do not survive shell expansion or variable indirection, so they prevent accidental access but are not a hard boundary.

**Do not rely on the permission rules to protect secrets.** Keep sensitive files out of the bind-mounted working directory, and treat anything inside the container as potentially visible to the agent.

See [DESIGN.md](DESIGN.md) for the full threat model.

## 🔧 Troubleshooting

- **First run is slow** — Nix store is copied to the persistent volume. Subsequent runs reuse it.
- **`podman load` fails with `copy_file_range: is a directory`**: that image already exists.  The launcher checks its immutable tag before loading.  For manual loading, remove only the tag you intend to reload first.
- **macOS reports `Required system: aarch64-linux`**: the exact image is missing from the readable caches.  Run `bash ~/git/botille/scripts/mac-build-image.sh ~/git/botille`, then run the import command it prints.  Retry Botille from your project directory.
- **Old image versions consume space**: each image retains a root under `/nix/var/nix/gcroots/botille-images`.  Remove roots only for versions no container needs, then run `nix-store --gc`.  Rooted user-installed packages remain registered across updates.
- **Reset everything** — `podman volume rm botille-home botille-nix` removes all persistent state.

## CI image publication

The check workflow builds both Linux architectures.  The automatic lockfile update publishes its commit only after checks and explicit Cachix uploads succeed for both images; it does not depend on a subsequent push workflow.

Configure `CACHIX_AUTH_TOKEN` with write access to the target cache.  This fork uses `mjaskelioff-botille`.  Set the repository variable `CACHIX_CACHE` to the personal cache name.  CI does not upload to the upstream cache.  Add the personal cache URL and public key to `nix/caches.nix` and the literal `nixConfig` in `flake.nix` so launchers and VM builds can read it.  Without both settings, ordinary checks still run, while automatic lockfile publication fails with a clear error.  Workflows in a new fork must also be enabled in GitHub Actions.
