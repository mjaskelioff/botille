{
  pkgs,
  home,
  hmActivation,
}:
pkgs.replaceVarsWith {
  src = ./entrypoint.sh;
  isExecutable = true;
  replacements = {
    inherit
      home
      hmActivation
      ;
    initStore = pkgs.replaceVarsWith {
      src = ./init-store.sh;
      isExecutable = true;
      replacements = { };
    };
  };
}
