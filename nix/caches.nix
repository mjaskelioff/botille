# Binary cache URLs and public keys for the container and VM builder.
# The literal nixConfig in flake.nix is checked against this list.
let
  caches = [
    {
      url = "https://mjaskelioff-botille.cachix.org";
      key = "mjaskelioff-botille.cachix.org-1:7ubt1wsOEkHVa6B85OnxKidmU3dc6YRXa1MrqjVm3Yo=";
    }
    {
      url = "https://delirium-systems.cachix.org";
      key = "delirium-systems.cachix.org-1:66ovNl3TR96B++WAvUK0U6nmrejRLR3DYoFzQbKnPHs=";
    }
    {
      url = "https://cache.numtide.com";
      key = "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=";
    }
    {
      url = "https://nix-community.cachix.org";
      key = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";
    }
  ];
in
{
  inherit caches;
  urls = builtins.concatStringsSep " " (map (cache: cache.url) caches);
  keys = builtins.concatStringsSep " " (map (cache: cache.key) caches);
}
