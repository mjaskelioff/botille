"""Exercise the generated launcher with a recording Podman substitute."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def podman():
    args = sys.argv[2:]
    hooks = args[:1] == ["--hooks-dir"]
    if hooks:
        args = args[2:]
    record = {"args": args, "hooks": hooks}
    image = Path(os.environ["TEST_PODMAN_IMAGE"])
    status = 0
    if args[0] == "run":
        assert image.exists(), "attempted to run an absent image"
        record["stdin"] = sys.stdin.read() if "-i" in args else ""
        print('{"ok":true}')
    elif args[:2] == ["machine", "inspect"]:
        print(os.environ.get("TEST_MACHINE_STATE", "running"))
    elif args[:2] == ["image", "exists"]:
        status = 0 if image.exists() else 1
    elif args[0] == "load":
        image.touch()
        print("Podman image diagnostic")
        # Simulate losing a concurrent load race after the image appeared.
        status = int(os.environ.get("TEST_LOAD_STATUS", "0"))
    else:
        raise AssertionError(args)
    with open(os.environ["TEST_PODMAN_LOG"], "a") as log:
        log.write(json.dumps(record) + "\n")
    sys.exit(status)


def check(launcher, mock_bin, platform):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        home = root / "home"
        home.mkdir()
        first = root / "one" / "same name"
        second = root / "two" / "same name"
        first.mkdir(parents=True)
        second.mkdir(parents=True)
        alias = root / "alias"
        alias.symlink_to(first, target_is_directory=True)
        log = root / "podman.jsonl"
        image = root / "loaded-image"
        env = dict(os.environ, HOME=str(home), XDG_STATE_HOME=str(root / "state"),
                   PATH=f"{mock_bin}:{os.environ['PATH']}", TEST_PODMAN_LOG=str(log),
                   TEST_PODMAN_IMAGE=str(image))

        def run(cwd, *args, stdin="", env_extra=None):
            log.write_text("")
            result = subprocess.run([launcher, *args], cwd=cwd,
                                    env=dict(env, **(env_extra or {})),
                                    input=stdin, text=True, capture_output=True)
            assert result.returncode == 0, result.stderr
            # Image loading must not contaminate Codex's JSON output.
            assert result.stdout == '{"ok":true}\n', result.stdout
            records = [json.loads(line) for line in log.read_text().splitlines()]
            inspections = [r for r in records if r["args"][:2] == ["machine", "inspect"]]
            assert bool(inspections) == (platform == "darwin"), records
            records = [r for r in records if r not in inspections]
            call = records[-1]
            assert call["args"][0] == "run", records
            assert call["hooks"] == (platform == "linux"), call
            assert ("LAN blocking is unavailable on macOS" in result.stderr) == (platform == "darwin")
            return call, records

        def value(args, flag):
            return args[args.index(flag) + 1]

        def command(args):
            return args[args.index("botille:mock-image") + 1:]

        call, records = run(first, "codex", "-p", "review", stdin="a piped prompt\n")
        assert [r["args"][0] for r in records] == ["image", "load", "run"]
        args = call["args"]
        workdir = value(args, "-w")
        assert re.fullmatch(r"/work/same-name-[0-9a-f]{16}", workdir), workdir
        assert f"{first.resolve()}:{workdir}" in args
        assert f"BOTILLE_WORKDIR={workdir}" in args
        assert command(args) == ["codex", "-p", "review"]
        assert call["stdin"] == "a piped prompt\n"
        assert "-i" in args and "-t" not in args

        call, records = run(first, "codex")
        assert [r["args"][0] for r in records] == ["image", "run"], records
        assert value(call["args"], "-w") == workdir
        assert "--pull=never" in call["args"]
        # A prune or a switch to a backend with no image must reload it,
        # even if the old launcher's marker remains on the host.
        marker = root / "state/botille/loaded-image"
        marker.parent.mkdir(parents=True)
        marker.write_text("stale-image-path")
        image.unlink()
        _, records = run(first, "codex")
        assert [r["args"][0] for r in records] == ["image", "load", "run"]
        image.unlink()
        _, records = run(first, "codex", env_extra={"TEST_LOAD_STATUS": "125"})
        assert [r["args"][0] for r in records] == ["image", "load", "image", "run"]
        call, _ = run(alias, "codex")
        assert value(call["args"], "-w") == workdir
        call, _ = run(second, "codex")
        assert value(call["args"], "-w") != workdir

        forwarded = ["codex", "-p", "review", "--port", "literal", "--allow-lan", "-v", "data"]
        call, _ = run(first, "-p", "127.0.0.1:8000:8000", "--devshell",
                      "--volume", "/tmp/a b:/data:ro", "--host-port", "8080", *forwarded)
        assert command(call["args"]) == forwarded
        assert value(call["args"], "-p") == "127.0.0.1:8000:8000"
        assert "/tmp/a b:/data:ro" in call["args"]
        assert "BOTILLE_DEVSHELL=1" in call["args"]
        call, _ = run(first, "--", *forwarded)
        assert command(call["args"]) == forwarded
        call, _ = run(first)
        assert command(call["args"]) == []

        claude = home / ".claude"
        claude.mkdir()
        (claude / "CLAUDE.md").write_text("Instructions\n")
        (claude / "skills").mkdir()
        call, _ = run(first, "--share-claude", "claude")
        state_source = claude / "projects" / re.sub(r"[^a-zA-Z0-9]", "-", str(first.resolve()))
        state_dest = re.sub(r"[^a-zA-Z0-9]", "-", workdir)
        assert f"{state_source}:/home/user/.claude/projects/{state_dest}" in call["args"]
        assert f"{claude}/skills:/home/user/.claude/skills:ro" in call["args"]
        assert state_source.is_dir()
        # --share-memory performs only the project-state mount.
        call, _ = run(first, "--share-memory", "claude")
        assert f"{state_source}:/home/user/.claude/projects/{state_dest}" in call["args"]
        assert f"{claude}/skills:/home/user/.claude/skills:ro" not in call["args"]
        assert f"{claude}/CLAUDE.md:/home/user/.claude/CLAUDE.md:ro" not in call["args"]
        assert command(call["args"]) == ["claude"]
        # bash keeps an inherited logical $PWD that names the cwd; the host
        # state directory must still be keyed by the physical path, matching
        # both host Claude Code (process.cwd()) and the workspace identity.
        call, _ = run(alias, "--share-claude", "claude", env_extra={"PWD": str(alias)})
        assert f"{state_source}:/home/user/.claude/projects/{state_dest}" in call["args"]

        # A cold image marker makes sure a bad flag fails before any podman
        # call: the image must not be removed and reloaded over a typo.
        cold = dict(env, XDG_STATE_HOME=str(root / "cold-state"))
        for args in [["--port"], ["--volume"], ["--host-port", "invalid"]]:
            log.write_text("")
            result = subprocess.run([launcher, *args], cwd=first, env=cold,
                                    input="", text=True, capture_output=True)
            assert result.returncode != 0, args
            records = [json.loads(line) for line in log.read_text().splitlines()]
            assert all(r["args"][:2] == ["machine", "inspect"] for r in records), args
        if platform == "darwin":
            result = subprocess.run([launcher, "true"], cwd=first,
                                    env=dict(env, TEST_MACHINE_STATE="stopped"),
                                    input="", text=True, capture_output=True)
            assert result.returncode != 0 and "no running podman machine" in result.stderr
    print(f"Launcher checks passed: {launcher}")


if __name__ == "__main__":
    if sys.argv[1] == "--podman":
        podman()
    else:
        check(*sys.argv[1:])
