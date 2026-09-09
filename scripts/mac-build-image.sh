#!/usr/bin/env bash
# Build the botille container image for Linux inside the podman machine VM
# and export it to a local file cache, for macOS hosts that cannot build
# Linux derivations.  Needed when the image cannot be substituted from the
# binary cache: customised mkApp images, or a plain cache miss.
#
# Run from the repository (or wrapper flake) root, with a running podman
# machine.  The final import into /nix/store must be done by a trusted
# user because the locally built paths are unsigned; the script prints the
# sudo command to finish the job.
set -euo pipefail

flake=${1:-.}
case "$(uname -m)" in
  arm64 | aarch64) linux_system=aarch64-linux ;;
  *)
    echo "unsupported architecture: $(uname -m) (only Apple silicon is supported)" >&2
    exit 1
    ;;
esac

cache_dir=$PWD/.botille-image-cache
mkdir -p "$cache_dir"

echo "botille: instantiating image derivation" >&2
drv=$(nix eval --raw "$flake#packages.$linux_system.container.drvPath")
out=$(nix eval --raw "$flake#packages.$linux_system.container.outPath")

if nix path-info "$out" >/dev/null 2>&1; then
  echo "botille: $out is already in the host store — nothing to do" >&2
  exit 0
fi

echo "botille: exporting derivation closure to $cache_dir" >&2
nix copy --derivation --to "file://$cache_dir" "$drv"

# Cache URLs/keys duplicated from nix/caches.nix — inside the throwaway
# builder there is no flake evaluation to read them from.
substituters='https://delirium-systems.cachix.org https://cache.numtide.com https://nix-community.cachix.org'
trusted_keys='delirium-systems.cachix.org-1:66ovNl3TR96B++WAvUK0U6nmrejRLR3DYoFzQbKnPHs= niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs='

echo "botille: building $drv in a podman container (first run downloads several GB)" >&2
podman volume create botille-build >/dev/null 2>&1 || true
podman run --rm \
  -v "$cache_dir:/cache" \
  -v botille-build:/nix \
  docker.io/nixos/nix:latest \
  sh -c "
    set -e
    nix --extra-experimental-features nix-command copy --derivation --no-check-sigs --from file:///cache '$drv'
    nix-store --realise '$drv' \
      --option extra-substituters '$substituters' \
      --option extra-trusted-public-keys '$trusted_keys'
    nix --extra-experimental-features nix-command copy --no-check-sigs --to file:///cache '$out'
  "

echo
echo "botille: image built: $out"
echo "botille: import it into the host store with:"
echo
echo "  sudo nix copy --no-check-sigs --from 'file://$cache_dir' '$out'"
echo
echo "then 'nix run' works as usual, and $cache_dir can be deleted."
