{
  pkgs,
  containerPackages,
  nixConf,
  entrypoint,
  home,
}:
pkgs.dockerTools.buildLayeredImage {
  name = "botille";
  tag = "latest";
  maxLayers = 2;

  contents = containerPackages ++ [
    (pkgs.dockerTools.fakeNss.override {
      extraPasswdLines = [ "user:x:1000:1000::${home}:/bin/bash" ];
      extraGroupLines = [ "user:x:1000:" ];
    })
    nixConf
  ];

  fakeRootCommands = ''
    mkdir -p tmp var/tmp work .${home} usr/bin var/nix-store
    chmod 1777 tmp var/tmp
    chmod 777 work .${home} var/nix-store
    mkdir -p nix/store nix/var
    ln -s ${pkgs.coreutils}/bin/env usr/bin/env
  '';

  config = {
    Entrypoint = [ "${entrypoint}" ];
    Cmd = [ "/bin/bash" ];
    WorkingDir = "/work";
    Env = [
      "PATH=${pkgs.lib.makeBinPath containerPackages}"
      "USER=user"
      "HOME=${home}"
      "XDG_CONFIG_HOME=${home}/.config"
      "XDG_DATA_HOME=${home}/.local/share"
      "XDG_STATE_HOME=${home}/.local/state"
      "XDG_CACHE_HOME=${home}/.cache"
      "NIX_CONF_DIR=/etc/nix"
      "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      "CLAUDE_CONFIG_DIR=${home}/.claude"
      # XDG overrides for tools that don't respect it natively
      "HISTFILE=${home}/.local/state/bash/history"
      "PYTHON_HISTORY=${home}/.local/state/python/history"
      "PYTHONPYCACHEPREFIX=${home}/.cache/python"
      "RIPGREP_CONFIG_PATH=${home}/.config/ripgrep/config"
      "NODE_REPL_HISTORY=${home}/.local/state/node/history"
      "NPM_CONFIG_USERCONFIG=${home}/.config/npm/npmrc"
      "NPM_CONFIG_CACHE=${home}/.cache/npm"
      "WGETRC=${home}/.config/wget/wgetrc"
      "GNUPGHOME=${home}/.config/gnupg"
      "PI_CODING_AGENT_DIR=${home}/.config/pi"
      "GEMINI_CLI_HOME=${home}/.local/state/gemini"
      "SERENA_HOME=${home}/.config/serena"
      "COLORTERM=truecolor"
    ];
  };
}
