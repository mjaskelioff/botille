{
  pkgs,
  llmAgentsPkgs,
  homeManagerPkg,
  serenaPkg,
}:
let
  claude-yolo = pkgs.writeShellScriptBin "claude-yolo" ''
    exec claude --dangerously-skip-permissions "$@"
  '';

  # Upstream postPatch calls `node` which leaks into fetchNpmDeps (stdenvNoCC,
  # no nodejs). Add nodejs to the FOD's nativeBuildInputs so the patch runs.
  gemini-cli = llmAgentsPkgs.gemini-cli.overrideAttrs (old: {
    npmDeps = old.npmDeps.overrideAttrs (odeps: {
      nativeBuildInputs = odeps.nativeBuildInputs ++ [ pkgs.nodejs ];
    });
  });
in
[
  pkgs.bash
  pkgs.coreutils
  pkgs.git
  pkgs.gnugrep
  pkgs.gnused
  pkgs.gawk
  pkgs.findutils
  pkgs.which
  pkgs.less
  pkgs.neovim
  pkgs.iproute2
  pkgs.iputils
  pkgs.curl
  pkgs.wget
  pkgs.direnv
  pkgs.nix-direnv
  pkgs.cachix
  pkgs.nix
  pkgs.cacert
  # AI agents
  llmAgentsPkgs.claude-code
  claude-yolo
  llmAgentsPkgs.codex
  gemini-cli
  llmAgentsPkgs.copilot-cli
  llmAgentsPkgs.opencode
  llmAgentsPkgs.pi

  pkgs.python3
  pkgs.uv
  serenaPkg
  # Search & navigation
  pkgs.ripgrep
  pkgs.fd
  pkgs.tree
  pkgs.file
  # JSON & diffs
  pkgs.jq
  pkgs.diffutils
  pkgs.delta
  # Archives & hex
  pkgs.unixtools.xxd
  pkgs.unzip
  pkgs.gnutar
  # Git & GitHub
  pkgs.gh
  pkgs.openssh
  pkgs.gnupg
  # General
  pkgs.nodejs
  pkgs.rsync
  pkgs.tmux
  pkgs.man
  pkgs.ncurses
  # Network analysis
  pkgs.nmap
  pkgs.tcpdump
  # pkgs.wireshark-cli # broken: upstream source hash mismatch in nixpkgs
  pkgs.netcat-gnu
  pkgs.traceroute
  pkgs.dnsutils
  pkgs.whois
  pkgs.mtr
  # Process & debug tools
  pkgs.procps
  pkgs.psmisc
  pkgs.lsof
  pkgs.htop
  pkgs.strace
  # Needed for mount --bind in the entrypoint
  pkgs.util-linux
  pkgs.starship
  pkgs.getent
  # Home environment
  homeManagerPkg
]
