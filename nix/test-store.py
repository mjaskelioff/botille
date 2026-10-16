"""Check image upgrades, registration, GC and concurrent startup in tiny stores."""

import fcntl
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def check(helper):
    env = dict(os.environ, NIX_CONFIG="build-users-group =\nreserved-size = 0\n")

    def nix(root, *args, input=None, check=True):
        return subprocess.run(
            ["nix-store", "--store", f"local?root={root}", *args],
            input=input, text=True, capture_output=True, env=env, check=check,
        )

    def physical(root, path):
        return root / path.lstrip("/")

    def register_refs(root, path, refs):
        # --register-validity computes the NAR hash; explicitly register the
        # references that closureInfo normally derives from its inputs.
        registration = f"{path}\n\n{len(refs)}\n" + "".join(f"{ref}\n" for ref in refs)
        nix(root, "--register-validity", "--reregister", input=registration)

    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)

        def image(version):
            root = base / f"image-{version}"
            sources = base / f"sources-{version}"
            sources.mkdir()
            paths = []
            for name, content in [("common", "shared"), ("fake-nss", f"user-{version}"),
                                  ("entrypoint", f"startup-{version}")]:
                source = sources / name
                source.write_text(content)
                paths.append(nix(root, "--add", str(source)).stdout.strip())
            package_dir = sources / "readonly-package"
            package_dir.mkdir()
            (package_dir / "payload").write_text(version)
            directory = nix(root, "--add", str(package_dir)).stdout.strip()
            paths.append(directory)
            closure_source = sources / "image-closure"
            closure_source.mkdir()
            (closure_source / "registration").write_text(nix(root, "--dump-db").stdout)
            closure = nix(root, "--add", str(closure_source)).stdout.strip()
            register_refs(root, closure, paths)
            registration_source = sources / "closure-registration"
            registration_source.mkdir()
            (registration_source / "registration").write_text(nix(root, "--dump-db").stdout)
            registration = nix(root, "--add", str(registration_source)).stdout.strip()
            return root, closure, registration, paths

        first = image("first")
        second = image("second")
        volume = base / "volume"

        def launch(fixture, *, check=True):
            root, closure, registration, _ = fixture
            return subprocess.run(
                ["bash", helper, str(root / "nix"), str(volume), closure, registration],
                text=True, capture_output=True, env=env, check=check,
            )

        launch(first)
        user_source = base / "user-package"
        user_source.write_text("installed independently of the image")
        user = nix(volume, "--add", str(user_source)).stdout.strip()
        user_root = volume / "nix/var/nix/gcroots/user-package"
        user_root.symlink_to(user)

        launch(second)
        launch(first)
        launch(second)
        expected = [user, first[1], second[1], *first[3], *second[3]]
        nix(volume, "--check-validity", *expected)
        refs = nix(volume, "--query", "--references", second[1]).stdout.splitlines()
        assert set(refs) == set(second[3]), refs
        current_root = volume / "nix/var/nix/gcroots/botille-images" / Path(second[1]).name
        current_root.unlink()
        launch(second)
        assert current_root.is_symlink(), "a warm launch must restore its image root"
        nix(volume, "--gc")
        nix(volume, "--check-validity", *expected)
        for fixture in (first, second):
            assert physical(volume, fixture[3][1]).read_text().startswith("user-")
            assert physical(volume, fixture[3][2]).read_text().startswith("startup-")
            directory = physical(volume, fixture[3][3])
            assert (directory / "payload").is_file()
            assert directory.stat().st_mode & 0o777 == 0o555
        assert physical(volume, user).read_text() == user_source.read_text()
        print("Image changes preserve user registrations, both image roots and their closures.", flush=True)

        # A failed update cannot commit its marker.  A later launch must
        # retry registration rather than treating a partial update as complete.
        bad = (first[0], first[1], "/nix/store/missing-registration", first[3])
        marker = volume / ".botille-image"
        before = marker.read_text()
        assert launch(bad, check=False).returncode != 0
        assert marker.read_text() == before
        launch(first)
        assert marker.read_text() == first[1]

        # Check both startup serialization and exclusion against Nix's GC lock.
        for lock_path in (volume / ".botille-init.lock", volume / "nix/var/nix/gc.lock"):
            with lock_path.open("w") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                root, closure, registration, _ = second
                command = ["bash", helper, str(root / "nix"), str(volume), closure, registration]
                child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                         text=True, env=env)
                try:
                    child.communicate(timeout=0.2)
                    raise AssertionError(f"startup ignored {lock_path.name}")
                except subprocess.TimeoutExpired:
                    pass
                finally:
                    fcntl.flock(lock, fcntl.LOCK_UN)
                _, stderr = child.communicate(timeout=30)
                assert child.returncode == 0, stderr
        nix(volume, "--check-validity", *expected)
        print("Failed updates retry; startup coordinates with other launches and GC.", flush=True)


if __name__ == "__main__":
    try:
        check(sys.argv[1])
    except subprocess.CalledProcessError as error:
        print(error.stdout or "", file=sys.stderr)
        print(error.stderr or "", file=sys.stderr)
        raise
