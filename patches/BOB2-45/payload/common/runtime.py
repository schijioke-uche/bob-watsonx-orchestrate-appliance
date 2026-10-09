#!/usr/bin/env python3
"""Project-local Bob Shell 2.x adapter. Python 3.9+, standard library only.

The working BQCA v2.0.5 launcher is the command-contract reference. This
adapter does not install Bob, fabricate login tokens, or rewrite Bob's home.
"""
from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlparse
from production_display import run_stream, chat_terminal

RELEASE = "BOB2-45.0.0"
VERSION_RE = re.compile(r"(?<![0-9])([0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9][A-Za-z0-9.-]*)?)(?![0-9])")
SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SLUG_LINE = re.compile(r"^\s*-\s+slug:\s*['\"]?([A-Za-z0-9-]+)['\"]?\s*$", re.M)


class UserError(Exception):
    pass


def log(message: str) -> None:
    print(f"[BOB2] {message}", file=sys.stderr, flush=True)


def checked_path(root: Path, relative: str) -> Path:
    part = Path(relative)
    if part.is_absolute() or ".." in part.parts:
        raise UserError(f"Unsafe project path: {relative}")
    current = root
    for name in part.parts:
        current = current / name
        if current.is_symlink():
            raise UserError(f"Refusing symlink in managed path: {current}")
    return current


def atomic_bytes(path: Path, data: bytes, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".bob2-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(name, mode)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def positive_int(name: str, default: int, limit: int = 1000000) -> int:
    value = os.environ.get(name, str(default))
    if not value.isdecimal() or not 0 < int(value) <= limit:
        raise UserError(f"{name} must be an integer between 1 and {limit}.")
    return int(value)


def toggle(name: str, default: bool) -> bool:
    value = os.environ.get(name, "1" if default else "0").lower()
    if value in {"1", "true", "yes"}:
        return True
    if value in {"0", "false", "no"}:
        return False
    raise UserError(f"{name} must be 1/0 or true/false.")


def safe_environment() -> dict[str, str]:
    env = dict(os.environ)
    env.pop("NODE_TLS_REJECT_UNAUTHORIZED", None)
    env.pop("BOBSHELL_API_KEY", None)
    if not toggle("BOB2_PRESERVE_LEGACY_ENDPOINT_OVERRIDES", False):
        for key in ("BOB_ENDPOINT", "BOB_AUTH_ENDPOINT", "BOB_REGION"):
            env.pop(key, None)
    ca = env.get("BOB_NODE_EXTRA_CA_CERTS", "")
    if ca:
        if not Path(ca).is_file():
            raise UserError("BOB_NODE_EXTRA_CA_CERTS does not identify a CA file.")
        env["NODE_EXTRA_CA_CERTS"] = ca
    key = env.get("BOB_API_KEY", "")
    if "\n" in key or "\r" in key:
        raise UserError("BOB_API_KEY contains a newline or carriage return.")
    return env


def redact(text: str, env: dict[str, str]) -> str:
    for key, value in env.items():
        if value and len(value) >= 5 and re.search(r"(KEY|TOKEN|SECRET|PASSWORD)", key):
            text = text.replace(value, "[REDACTED]")
    return text[-6000:]


class Appliance:
    def __init__(self, root: Path):
        self.root = root.resolve()
        self.home = checked_path(self.root, ".bob/runtime/bob-v2")
        try:
            self.config = json.loads((self.home / "appliance.json").read_text())
        except (OSError, ValueError) as exc:
            raise UserError(f"Missing or invalid Bob 2.x appliance configuration: {exc}") from exc
        self.env = safe_environment()
        requested = self.env.get("BOB2_BIN") or self.env.get("BOB_BIN", "bob")
        self.binary = shutil.which(requested)
        if not self.binary:
            raise UserError("Bob CLI is not executable. Install Bob Shell 2.x or set BOB_BIN to its executable path.")
        self.binary = str(Path(self.binary).resolve())
        self.help_cache: dict[str, str] = {}
        self._version = ""
        self._authentication_done = False
        # Bootstrap the version using a TLS-safe environment, then source the
        # ACTUAL benchmark TLS file before any backend/user operation.
        self.version()
        self.shell_environment("tls")

    def ui(self, action: str, choice: str = "") -> None:
        view = checked_path(self.root, ".bob/runtime/bob-v2/menu.sh")
        rc = subprocess.call(["bash", str(view), action, choice], cwd=str(self.root), env=self.env)
        if rc:
            raise UserError(f"Production menu renderer failed (exit {rc}).")

    def shell_environment(self, component: str) -> None:
        """Source the real Bash policy and carry its exported environment forward.

        Authentication diagnostics stream to stderr. The environment travels only
        through a captured pipe (never an on-disk credential file or terminal).
        """
        if component not in {"tls", "auth"}:
            raise UserError("Unknown shell policy component.")
        policy = checked_path(self.root, "bob-auth.sh" if component == "auth" else "tls-control.sh")
        if not policy.is_file():
            raise UserError(f"Required policy file is missing: {policy.name}")
        env = dict(self.env)
        env["BOB_BIN"] = self.binary
        env["BOB2_BIN"] = self.binary
        env["BOB_VERSION"] = self._version
        deadline = positive_int("BOB_AUTH_PROBE_TIMEOUT_SECONDS", 90, 3600) + 15 if component == "auth" else 30
        command = r'''set -Eeuo pipefail
root="$1"
policy="$2"
{
  source "$root/.bob/runtime/bob-v2/menu.sh"
  bob2_ui_init
  source "$policy"
} >&2
exec python3 -c 'import json,os,sys; json.dump(dict(os.environ),sys.stdout)'
'''
        # The private temporary parent also cleans probe files after interrupts.
        with tempfile.TemporaryDirectory(prefix="bob2-policy-") as temporary:
            prior_tmp = env.get("TMPDIR")
            env["TMPDIR"] = temporary
            process = subprocess.Popen(["bash", "-c", command, "bob2-policy", str(self.root), str(policy)],
                                       cwd=str(self.root), env=env, text=True,
                                       stdout=subprocess.PIPE, stderr=None, start_new_session=True)
            try:
                stdout, _ = process.communicate(timeout=deadline)
            except BaseException as exc:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                if isinstance(exc, subprocess.TimeoutExpired):
                    raise UserError(f"{policy.name} exceeded its {deadline}-second safety deadline.") from exc
                raise
            if process.returncode:
                raise UserError(f"{policy.name} failed (exit {process.returncode}); no user task was launched.")
            try:
                updated = json.loads(stdout)
            except ValueError as exc:
                # Never echo this buffer: it contains the child environment.
                raise UserError("The shell policy did not return a valid environment handoff.") from exc
            if not isinstance(updated, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in updated.items()):
                raise UserError("Invalid shell policy environment handoff.")
            if component == "auth" and updated.get("BOB_AUTH_VALIDATED") != "1":
                raise UserError("The benchmark helper did not validate backend authentication.")
            if prior_tmp is None:
                updated.pop("TMPDIR", None)
            else:
                updated["TMPDIR"] = prior_tmp
            self.env = updated

    def capture(self, args: list[str], cwd: Path | None = None, timeout: int = 30) -> subprocess.CompletedProcess:
        try:
            return subprocess.run([self.binary, *args], cwd=str(cwd or self.root), env=self.env,
                                  text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            raise UserError(f"Bob command exceeded {timeout} seconds.") from exc
        except OSError as exc:
            raise UserError(f"Could not start Bob: {exc}") from exc

    def version(self) -> str:
        if not self._version:
            result = self.capture(["--version"])
            match = VERSION_RE.search(result.stdout + "\n" + result.stderr)
            if result.returncode or not match:
                raise UserError("Unable to determine Bob Shell version from bob --version.")
            self._version = match.group(1)
            if self._version.split(".")[0] != "2":
                raise UserError(f"This upgrade requires Bob Shell 2.x; detected {self._version}. No legacy fallback was executed.")
            self.env["BOB_VERSION"] = self._version
        return self._version

    def help(self, command: str) -> str:
        if command not in self.help_cache:
            result = self.capture([command, "--help"] if command else ["--help"])
            if result.returncode:
                raise UserError(f"bob {command} --help failed; cannot validate the installed CLI contract.")
            self.help_cache[command] = result.stdout + "\n" + result.stderr
        return self.help_cache[command]

    def supports(self, command: str, option: str) -> bool:
        return bool(re.search(r"(?<![A-Za-z0-9_-])" + re.escape(option) + r"(?![A-Za-z0-9_-])", self.help(command)))

    def require(self, command: str, options: list[str]) -> None:
        missing = [flag for flag in options if not self.supports(command, flag)]
        if missing:
            raise UserError(f"Installed bob {command or '(root)'} does not advertise {', '.join(missing)}. Refusing an incompatible invocation.")

    def slugs(self) -> set[str]:
        path = checked_path(self.root, ".bob/custom_modes.yaml")
        text = path.read_text(encoding="utf-8")
        if not re.search(r"^customModes:\s*$", text, re.M):
            raise UserError(".bob/custom_modes.yaml must contain the customModes root key.")
        slugs = SLUG_LINE.findall(text)
        if not slugs or len(slugs) != len(set(slugs)):
            raise UserError("Custom mode slugs are missing or duplicated. Run the upgrade preflight/doctor.")
        # The installer emits this conventional YAML form; Bob remains the YAML parser.
        # Refuse unsupported syntax rather than pretending a partial YAML parse is complete.
        if len(re.findall(r"^\s*-\s+slug:", text, re.M)) != len(slugs):
            raise UserError("A custom mode slug is malformed; use lowercase hyphenated identifiers.")
        return set(slugs)

    def mode(self, role: str) -> str:
        value = self.env.get(f"BOB2_{role.upper()}_MODE", self.config["modes"][role]).strip()
        value = self.config["aliases"].get(value, value)
        if not SLUG_RE.fullmatch(value) or value not in self.slugs():
            raise UserError(f"Unavailable project mode for {role}: {value!r}. No generic Agent fallback was used.")
        rules = checked_path(self.root, f".bob/rules-{value}")
        if not rules.is_dir() or not any(rules.glob("*.md")):
            raise UserError(f"Missing mode-specific rules for {value}.")
        return value

    def context(self, choice: str, mode: str) -> None:
        entry = self.config["menu"].get(choice, self.config["menu"]["1"])
        pairs = {"MENU_OPTION": choice, "MENU_ACTION": entry["action"],
                 "MENU_SKILL_ID": entry["skill"], "SELECTED_MODE": mode}
        for key, value in pairs.items():
            self.env["BOB2_" + key] = value
            self.env[self.config["code"] + "_" + key] = value
        self.env["BOB2_APPLIANCE_CODE"] = self.config["code"]
        self.env["BOB2_WORKSPACE"] = str(self.root)
        self.env["SCRIPT_DIR"] = str(self.root)
        for kind in ("design", "store"):
            var = self.config["code"] + "_" + kind.upper() + "_DIR"
            path = Path(self.env.get(var, str(self.root / self.config[kind])))
            if not path.is_absolute():
                path = self.root / path
            if not path.resolve().is_relative_to(self.root):
                raise UserError(f"{var} points outside this appliance. Review the path explicitly; workspace trust will not be broadened automatically.")
            self.env[var] = str(path.resolve())

    def envelope(self, prompt: str, mode: str) -> str:
        c = self.config
        return (f"[{c['code']} PROJECT CONTEXT]\nAppliance: {c['title']}\n"
                f"Workspace: {self.root}\nMode: {mode}\n"
                f"Menu action: {self.env.get('BOB2_MENU_ACTION', 'User request')}\n"
                f"Read AGENTS.md, .bob/BOB2-APPLIANCE-POLICY.md, .bob/rules-{mode}/, "
                f"relevant .bob/skills/ and {c['tools']}/. Preserve domain-specific instructions.\n"
                f"Designs: {c['design']}/; implementation/results: {c['store']}/. "
                "Knowledgebases are supplementary, not replacement authorities. Do not expose credentials.\n"
                "Apply .bob/BOB2-DOCUMENTATION-DISCOVERY-POLICY.md: inspect the installed tool schema; "
                "browse/discover before searching unless the current task already has a validated catalog. "
                "Use exact tool-supported selectors, not product/mode slugs or guessed index mappings. "
                "On a missing library invalidate its binding, refresh once, retry once only with a newly "
                "validated selector. Verify product/version relevance; never loop or invent evidence.\n"
                "Apply .bob/BOB2-RETRIEVAL-DISPLAY-POLICY.md and .bob/BOB2-PRODUCTION-DISPLAY-PLAN.md: "
                "Browse/Search/Knowledgebase retrieval remain permitted. Keep evidence in the running "
                "task context, never echo raw payloads/metadata. Preserve status/answer styling and "
                "provide the useful sourced answer without duplicate statuses.\n"
                f"[USER REQUEST]\n{prompt}")

    def team_flag(self, command: str) -> list[str]:
        team = self.env.get("BOB_TEAM_ID", "").strip()
        if not team:
            return []
        if command == "chat" and not self.supports("chat", "--team-id"):
            log("BOB_TEAM_ID is set, but bob chat does not advertise --team-id. Select the team with /team, or use an inference-scope key.")
            return []
        self.require(command, ["--team-id"])
        return ["--team-id", team]

    def log_flag(self, command: str) -> list[str]:
        level = self.env.get("BOB2_LOG_LEVEL", "warn")
        if level not in {"error", "warn", "info", "debug", "trace"}:
            raise UserError("Invalid BOB2_LOG_LEVEL.")
        if self.supports(command, "--log-level"):
            return ["--log-level", level]
        return []

    def authenticate(self, required: bool = True, force: bool = False) -> None:
        # Use the benchmark Bash helper, not a second Python implementation of
        # its probe. In-memory state prevents double probing within one launch.
        if self._authentication_done and not force:
            return
        self.ui("authenticating")
        self.shell_environment("auth")
        self._authentication_done = True

    def resolve_task(self, requested: str) -> str:
        if requested != "latest":
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,199}", requested):
                raise UserError("Invalid task identifier.")
            return requested
        self.require("", ["--list-tasks"])
        result = self.capture(["--list-tasks", "all"])
        if result.returncode:
            raise UserError("Could not list tasks for this workspace.")
        records = []
        try:
            doc = json.loads(result.stdout)
            if isinstance(doc, list):
                records = doc
            elif isinstance(doc, dict) and isinstance(doc.get("tasks"), list):
                records = doc["tasks"]
            elif isinstance(doc, dict):
                records = [doc]
        except ValueError:
            for line in result.stdout.splitlines():
                try:
                    records.append(json.loads(line))
                except ValueError:
                    continue
        candidates = []
        for row in records:
            if not isinstance(row, dict):
                continue
            workspace = str(row.get("workspace", ""))
            parsed = urlparse(workspace)
            if parsed.scheme == "file":
                workspace = unquote(parsed.path)
            if not workspace or Path(workspace).resolve() != self.root:
                continue
            title = str(row.get("title", ""))
            if re.search(r"AUTH[_ -]?PROBE|BOB_AUTH_OK|BOB2_AUTH_PROBE|BQCA_AUTH_PROBE", title, re.I):
                continue
            ident = str(row.get("id", ""))
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,199}", ident):
                continue
            try:
                updated = float(row.get("updatedAt", 0))
            except (TypeError, ValueError):
                continue
            candidates.append((updated, ident))
        if not candidates:
            raise UserError("No resumable user task with a matching workspace was found. Start a session first, or supply its explicit task ID.")
        return max(candidates)[1]

    def chat(self, mode: str, resume: str = "") -> int:
        self.require("chat", ["--mode", "--trust"] + (["--resume"] if resume else []))
        args = ["chat", "--trust", "--mode", mode]
        if toggle("BOB2_CHAT_AUTO_APPROVE", True):
            self.require("chat", ["--auto-approve"])
            args.append("--auto-approve")
            log("You Selected Start Interactive BQCA Session, please wait ⏳")
        instance = self.env.get("BOB2_INSTANCE_ID", "").strip()
        if instance:
            self.require("chat", ["--instance-id"])
            args += ["--instance-id", instance]
        if resume:
            args += ["--resume", resume]
        args += self.team_flag("chat") + self.log_flag("chat")
        self.authenticate(required=False)
        log(f"Launching {self.config['code']} interactive mode {mode}" + (f"; task {resume}" if resume else ""))
        return chat_terminal([self.binary, *args], self.root, self.env, self.config)

    def run(self, mode: str, prompt: str, choice: str) -> int:
        if not prompt.strip():
            raise UserError("The request must not be empty.")
        self.require("run", ["--mode", "--format", "--max-turns", "--workspace", "--trust", "--accept-license"])
        # Production display is enforced independently of old output overrides.
        # Results still reach Bob unchanged; only its stdout presentation changes.
        fmt = "stream-json"
        args = ["run", "--mode", mode, "--format", fmt,
                "--max-turns", str(positive_int("BOB2_MAX_TURNS", 50)), "--workspace", str(self.root),
                "--trust", "--accept-license"]
        args += self.team_flag("run") + self.log_flag("run")
        self.authenticate(required=True)
        if self.config["code"] == "WXA" and choice in {"3", "4"} and toggle("WXA_ENSURE_ADK_ON_AGENT_BUILD", True):
            helper = checked_path(self.root, ".bob/watsonx-orchestrate-tools/ensure-wxo-adk-env.sh")
            if not helper.is_file():
                raise UserError("The WXA ADK environment helper is missing.")
            log("Running the existing WXA wxo-adk-env readiness helper.")
            rc = subprocess.call(["bash", str(helper)], cwd=str(self.root), env=self.env)
            if rc:
                return rc
        # A fixed context prefix prevents prompt text beginning with '-' from becoming an option.
        args.append(self.envelope(prompt, mode))
        log(f"Launching {self.config['code']} {mode}; Browse/Search/Knowledgebase status-only display. bob run pre-approves tools.")
        return run_stream([self.binary, *args], self.root, self.env, self.config)

    def synchronize(self, check_only: bool = False) -> str:
        version = self.version()
        target = checked_path(self.root, f"bob-{self.config['stem']}-v{version}.sh")
        expected = self.config["launcher_sha256"]
        pattern = re.compile(r"^bob-" + re.escape(self.config["stem"]) + r"-v[0-9].*\.sh$")
        launchers = [p for p in self.root.iterdir() if pattern.fullmatch(p.name)]
        if len(launchers) != 1:
            raise UserError("Expected exactly one managed versioned launcher; resolve duplicates before launching.")
        source = launchers[0]
        checked_path(self.root, source.name)
        if hashlib.sha256(source.read_bytes()).hexdigest() != expected:
            raise UserError("The versioned launcher has local edits. Refusing to rename or overwrite it automatically.")
        if target.exists() and source != target:
            raise UserError(f"Launcher-name collision: {target.name}")
        if source != target and not check_only:
            os.replace(source, target)
            log(f"Synchronized launcher filename: {source.name} -> {target.name}")
        return version

    def doctor(self) -> int:
        print(f"Release: {RELEASE}\nAppliance: {self.config['title']}\nBob Shell: {self.version()}\nWorkspace: {self.root}")
        self.require("chat", ["--mode", "--trust", "--resume"])
        self.require("run", ["--mode", "--format", "--max-turns", "--workspace", "--trust", "--accept-license"])
        if toggle("BOB2_CHAT_AUTO_APPROVE", True):
            self.require("chat", ["--auto-approve"])
        self.require("", ["--list-tasks"])
        self.team_flag("chat")
        self.team_flag("run")
        for role in ("interactive", "ask", "code", "advanced", "resume"):
            print(f"{role}: {self.mode(role)}")
        for rel in ("AGENTS.md", ".bob/BOB2-APPLIANCE-POLICY.md", ".bob/settings.json", ".bob/hooks/bob2-context.py",
                    "bob-auth.sh", "tls-control.sh", ".bob/runtime/bob-v2/menu.sh", ".bob/runtime/bob-v2/auth-timeout.py",
                    ".bob/runtime/bob-v2/production_display.py", ".bob/runtime/bob-v2/terminal_style.py", ".bob/BOB2-DOCUMENTATION-DISCOVERY-POLICY.md", ".bob/BOB2-PRODUCTION-DISPLAY-PLAN.md", ".bob/BOB2-RETRIEVAL-DISPLAY-POLICY.md", ".bob/BOB2-MODE-MAP.json"):
            if not checked_path(self.root, rel).is_file():
                raise UserError(f"Missing integration component: {rel}")
        settings = json.loads(checked_path(self.root, ".bob/settings.json").read_text())
        for event in ("SessionStart", "UserPromptSubmit"):
            if "bob2-context.py" not in json.dumps(settings.get("hooks", {}).get(event, [])):
                raise UserError(f"Missing project context hook: {event}")
        print(f"Custom modes: {len(self.slugs())}; skills: {len(list((self.root/'.bob/skills').rglob('SKILL.md')))}")
        print("Authentication: actual benchmark-derived bob-auth.sh; TLS: actual benchmark tls-control.sh")
        print("Production display: run=structured Browse/Search/Knowledgebase statuses; native chat=retrieval-header/JSON collapse; policy=all rules/skills/modes; discovery-first; ANSI-safe native cyan accent")
        print("PASS: local structure and advertised CLI contract. No backend or product workload was executed.")
        return 0

    def launch(self, args: list[str]) -> int:
        parser = argparse.ArgumentParser(description=self.config["title"] + " - Bob Shell 2.x")
        group = parser.add_mutually_exclusive_group()
        group.add_argument("--chat", action="store_true")
        group.add_argument("--ask", metavar="PROMPT")
        group.add_argument("--code", metavar="PROMPT")
        group.add_argument("--design", metavar="PROMPT")
        group.add_argument("--resume", nargs="?", const="latest", metavar="TASK_ID")
        group.add_argument("--doctor", action="store_true")
        group.add_argument("--preview", action="store_true", help="show the original production menu without authentication or a user task")
        group.add_argument("--auth-check", action="store_true", help="run the benchmark backend authentication only")
        group.add_argument("--menu", choices=list("012345"))
        parser.add_argument("initial_prompt", nargs="*")
        parsed = parser.parse_args(args)
        if parsed.doctor:
            return self.doctor()
        if parsed.preview:
            self.ui("preview")
            return 0
        if parsed.auth_check:
            self.authenticate(force=True)
            self.ui("time")
            return 0
        if parsed.chat:
            choice = "1"
        elif parsed.ask is not None:
            choice = "2"
        elif parsed.code is not None:
            choice = "3"
        elif parsed.design is not None:
            choice = "4"
        elif parsed.resume is not None:
            choice = "5"
        elif parsed.menu is not None:
            choice = parsed.menu
        else:
            self.ui("menu")
            self.authenticate()
            self.ui("time")
            self.ui("select")
            try:
                choice = input().strip()
            except EOFError:
                raise UserError("No menu selection received. Use --chat, --ask, --code, --design, or --resume for scripted invocation.")
        if choice == "0":
            self.ui("goodbye")
            return 0
        if choice not in "12345" or len(choice) != 1:
            raise UserError("Invalid menu option.")
        role = {"1": "interactive", "2": "ask", "3": "code", "4": "advanced", "5": "resume"}[choice]
        mode = self.mode(role)
        self.context(choice, mode)
        if parsed.initial_prompt:
            self.env["BOB2_INITIAL_PROMPT"] = " ".join(parsed.initial_prompt)
        if choice == "1":
            return self.chat(mode)
        if choice == "5":
            self.authenticate()
            return self.chat(mode, self.resolve_task(parsed.resume or "latest"))
        prompt = {"2": parsed.ask, "3": parsed.code, "4": parsed.design}[choice]
        if prompt is None:
            try:
                self.ui("prompt", choice)
                prompt = input()
            except EOFError:
                raise UserError("No request received.")
        return self.run(mode, prompt, choice)


@contextlib.contextmanager
def runtime_lock(app: Appliance):
    path = checked_path(app.root, ".bob/runtime/bob-v2/.session.lock")
    with open(path, "a", encoding="utf-8") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise UserError("Another appliance session or upgrade is active. Close it before continuing.") from exc
        yield


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("operation", choices=["launch", "version", "sync", "auth", "doctor"])
    parser.add_argument("--root", required=True)
    opts, rest = parser.parse_known_args()
    app = Appliance(Path(opts.root))
    if opts.operation == "version":
        print(app.version())
        return 0
    if opts.operation == "doctor":
        return app.doctor()
    if opts.operation == "auth":
        app.version()
        app.authenticate(required=True, force=True)
        return 0
    with runtime_lock(app):
        version = app.synchronize(check_only=opts.operation == "sync" and "--check" in rest)
        if opts.operation == "sync":
            print(version)
            return 0
        return app.launch(rest)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except UserError as exc:
        log("ERROR: " + str(exc))
        sys.exit(2)
    except KeyboardInterrupt:
        log("Interrupted.")
        sys.exit(130)
    except (OSError, ValueError, KeyError) as exc:
        log("ERROR: " + str(exc))
        sys.exit(2)
