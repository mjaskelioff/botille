{ pkgs, launcher }:
let
  testUser = "tester";

  tools = [
    {
      name = "claude-code";
      bin = "claude";
    }
    {
      name = "codex";
      bin = "codex";
    }
    {
      name = "gemini-cli";
      bin = "gemini";
    }
    {
      name = "copilot-cli";
      bin = "copilot";
    }
    {
      name = "opencode";
      bin = "opencode";
    }
    {
      name = "pi-coding-agent";
      bin = "pi";
    }
  ];

  runAs =
    cmd: "su -l ${testUser} -c ${pkgs.lib.escapeShellArg "cd /home/${testUser}/project && ${cmd}"}";

  mockPodman = pkgs.writeShellScriptBin "podman" ''
    exec ${pkgs.python3}/bin/python3 ${./test-launcher.py} --podman "$@"
  '';
  testLauncher =
    isDarwin:
    import ./launcher.nix {
      pkgs = pkgs // {
        stdenv = pkgs.stdenv // {
          inherit isDarwin;
        };
        podman = mockPodman;
      };
      container = pkgs.writeText "mock-botille-image" "";
      hooksDir = if isDarwin then null else "/mock/hooks";
      podmanFlags = [ ];
    };

  subtestScript = builtins.concatStringsSep "\n" (
    map (t: ''
      with subtest("${t.name}"):
          output = machine.succeed(${builtins.toJSON (runAs "${pkgs.lib.getExe launcher} ${t.bin} --version")})
          print(f"${t.name}: {output.strip()}")
    '') tools
  );
in
{
  launcher-args = pkgs.runCommand "botille-launcher-tests" { } ''
    ${pkgs.python3}/bin/python3 ${./test-launcher.py} ${pkgs.lib.getExe (testLauncher false)} ${mockPodman}/bin
    ${pkgs.python3}/bin/python3 ${./test-launcher.py} ${pkgs.lib.getExe (testLauncher true)} ${mockPodman}/bin
    touch $out
  '';

  ai-tools = pkgs.testers.runNixOSTest {
    name = "botille-ai-tools";
    nodes.machine = {
      virtualisation = {
        podman.enable = true;
        diskSize = 32768;
        memorySize = 2048;
      };
      users.users.${testUser} = {
        isNormalUser = true;
        extraGroups = [ "podman" ];
        subUidRanges = [
          {
            startUid = 100000;
            count = 65536;
          }
        ];
        subGidRanges = [
          {
            startGid = 100000;
            count = 65536;
          }
        ];
      };
    };
    testScript = ''
      machine.wait_for_unit("default.target")
      machine.succeed("mkdir -p /home/${testUser}/project /home/${testUser}/other/project")
      machine.succeed("chown -R ${testUser}:users /home/${testUser}/project /home/${testUser}/other")

      ${subtestScript}

      import shlex
      launcher = "${pkgs.lib.getExe launcher}"

      def launch(command: str, project: str = "/home/${testUser}/project") -> str:
          return machine.succeed("su -l ${testUser} -c " + shlex.quote(
              "cd " + shlex.quote(project) + " && " + launcher + " " + command
          ))

      with subtest("persistent project identity"):
          first = launch("pwd").strip()
          second = launch("pwd", "/home/${testUser}/other/project").strip()
          assert first.startswith("/work/project-") and second.startswith("/work/project-")
          assert first != second
          assert launch("pwd").strip() == first
          launch("bash -c 'echo project-a > marker'")
          launch("bash -c 'test ! -e marker'", "/home/${testUser}/other/project")
          launch("bash -c 'test $(cat marker) = project-a'")
          launch("bash -c 'mkdir -p ~/.codex; echo persisted > ~/.codex/botille-test-state'")
          launch("bash -c 'test $(cat ~/.codex/botille-test-state) = persisted'",
                 "/home/${testUser}/other/project")

      with subtest("piped stdin"):
          output = machine.succeed(${builtins.toJSON (runAs "printf piped-input | ${pkgs.lib.getExe launcher} cat")})
          assert output == "piped-input"

      with subtest("devshell at the project path"):
          machine.succeed(${builtins.toJSON (runAs "echo 'export BOTILLE_TEST_DEVSHELL=loaded' > .envrc")})
          launch("--devshell bash -c 'test $BOTILLE_TEST_DEVSHELL = loaded'")

      with subtest("Claude onboarding follows the project path"):
          launch(shlex.join(["bash", "-c",
              'jq -e --arg project "$PWD" \' .projects[$project].hasTrustDialogAccepted \' "$CLAUDE_CONFIG_DIR/settings.json"'
          ]))

      with subtest("Codex sandbox inside rootless Podman"):
          launch("bash -euc 'touch /home/user/outside-workspace; rm /home/user/outside-workspace'")
          launch("codex sandbox -P :workspace -- bash -euc 'touch sandbox-probe; ! touch /home/user/outside-workspace'")
          launch("codex sandbox -P :read-only -- bash -euc 'test -f sandbox-probe; ! touch sandbox-probe'")
    '';
  };
}
