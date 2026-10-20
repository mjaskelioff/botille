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
in
[
  pkgs.bash
  # Codex's /proc fallback needs Bubblewrap's pre-0.12 diagnostics.
  # Prefer the base version on PATH: https://github.com/openai/codex/issues/52260
  pkgs.bubblewrap
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
  llmAgentsPkgs.gemini-cli
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
