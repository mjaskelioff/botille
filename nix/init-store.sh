#!/usr/bin/env bash
set -euo pipefail

# Register an image in a persistent local store before the entrypoint binds
# it over /nix.  Explicit paths also let the lifecycle check use tiny stores.
image_nix=${1:?image Nix directory required}
nix_vol=${2:?persistent volume directory required}
image_closure=${3:?image closure required}
image_registration=${4:?image registration required}
nix_data="$nix_vol/nix"
marker="$nix_vol/.botille-image"
store="local?root=$nix_vol"

mkdir -p "$nix_vol"
exec 9>"$nix_vol/.botille-init.lock"
flock 9

# Nix uses flock on this file too.  Exclude GC until copied paths are
# registered and their permanent root is visible, including on warm starts.
mkdir -p "$nix_data/var/nix"
exec 8>"$nix_data/var/nix/gc.lock"
flock -s 8

pin_image() {
  # Keep roots for older images: another container can still be using them.
  roots="$nix_data/var/nix/gcroots/botille-images"
  mkdir -p "$roots"
  ln -sfn "$image_closure" "$roots/${image_closure##*/}"
}

if [ -f "$marker" ] && [ "$(<"$marker")" = "$image_closure" ] &&
  nix-store --store "$store" --check-validity "$image_closure" >/dev/null 2>&1; then
  pin_image
  exit 0
fi

echo "botille: updating Nix store (preserving existing registrations)" >&2
mkdir -p "$nix_data/store"
chmod u+w "$nix_data/store"
staging=$(mktemp -d "$nix_vol/.botille-copy.XXXXXX")
cleanup() {
  chmod -R u+w "$staging" 2>/dev/null || true
  rm -rf "$staging"
}
trap cleanup EXIT
for path in "$image_nix"/store/*; do
  name=${path##*/}
  if ! [ -e "$nix_data/store/$name" ]; then
    # Rename only complete copies into the store.  An interrupted copy must
    # not leave a partial path that the next launch would silently reuse.
    cp --reflink=auto -a "$path" "$staging/"
    # A non-root rename between parents needs write access to a directory
    # to update its ".." entry.  Restore the original mode before registration.
    if [ -d "$staging/$name" ] && ! [ -L "$staging/$name" ]; then
      chmod u+w "$staging/$name"
    fi
    mv "$staging/$name" "$nix_data/store/$name"
    if ! [ -L "$nix_data/store/$name" ]; then
      chmod --reference="$path" "$nix_data/store/$name"
    fi
  fi
done

# --load-db adds registrations to the existing database.  It must never
# replace the database holding user installs and other running images.
nix-store --store "$store" --load-db < "$image_nix/store/${image_closure##*/}/registration"
nix-store --store "$store" --load-db < "$image_nix/store/${image_registration##*/}/registration"

# Retain one root per image, so GC cannot break a container using an older
# image.  Operators can remove unused image roots when no container needs them.
pin_image
printf '%s' "$image_closure" > "$staging/marker"
mv "$staging/marker" "$marker"
