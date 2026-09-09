{ home }:
{ lib, config, ... }:
let
  inherit (lib)
    mkDefault
    mkIf
    mkOption
    types
    ;
in
{
  options = {
    devshell = mkOption {
      type = types.bool;
      default = false;
      description = "Enable direnv integration inside the container (sets BOTILLE_DEVSHELL=1).";
    };

    allowLan = mkOption {
      type = types.bool;
      default = false;
      description = "Disable the network firewall, allowing the container to reach LAN addresses.";
    };

    hostPorts = mkOption {
      type = types.listOf types.port;
      default = [ ];
      description = "Host TCP ports the container is allowed to reach through the firewall.";
      example = [
        8080
        11434
      ];
    };

    volumes = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Volume mounts passed to podman run as -v flags.";
      example = [ "/host/path:/container/path:Z" ];
    };

    ports = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Port mappings passed to podman run as -p flags.";
      example = [ "8080:8080" ];
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Environment variables passed to podman run as -e flags.";
    };

    dns = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "DNS servers for the container.";
    };

    network = mkOption {
      type = types.str;
      default = "";
      description = "Network mode for the container.";
    };

    capabilities = mkOption {
      type = types.lazyAttrsOf (types.nullOr types.bool);
      default = { };
      description = ''
        Capabilities to configure. true = --cap-add, false = --cap-drop, null = default.
      '';
    };

    securityOpt = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Security options passed to podman run.";
    };

    userns = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "User namespace mode.";
    };

    logDriver = mkOption {
      type = types.str;
      default = "";
      description = "Logging driver for the container.";
    };

    annotations = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "OCI annotations passed to podman run.";
    };

    extraOptions = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra flags passed verbatim to podman run.";
    };
  };

  # Base values. List/attr types use normal priority so extraContainerModules
  # merge (append) rather than replace. Scalar types use mkDefault so
  # extraContainerModules can override with a plain assignment.
  config = {
    volumes = [
      "botille-home:${home}"
      "botille-nix:/var/nix-store"
    ];

    dns = [
      "1.1.1.1"
      "1.0.0.1"
    ];

    capabilities = {
      SYS_ADMIN = mkDefault true;
      NET_ADMIN = mkDefault false;
      NET_RAW = mkDefault false;
    };

    securityOpt = [
      "no-new-privileges"
      # SELinux labeling gives each run its own MCS category pair, making
      # files one run writes to the shared volumes unreadable by the next
      # (podman machine's Fedora CoreOS VM enforces SELinux, as do
      # Fedora/RHEL hosts).  The container boundary is the sandbox here,
      # so disable labeling rather than relabel the multi-GB store with
      # :Z on every run.
      "label=disable"
    ];

    network = mkDefault "pasta:-4,--map-gw,-a,10.171.0.100,-n,24,-g,10.171.0.1";
    userns = mkDefault "keep-id:uid=1000,gid=1000";
    extraOptions = [ "--passwd=false" ];
    logDriver = mkDefault "none";

    environment = mkIf config.devshell { BOTILLE_DEVSHELL = "1"; };
  };
}
