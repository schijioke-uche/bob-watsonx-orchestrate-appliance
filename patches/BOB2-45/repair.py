#!/usr/bin/env python3
"""Patch 45: discovery-first documentation selection and ANSI/cyan presentation repair.

Apply ON TOP OF Patch 44. Preserve original UI, benchmark authentication/TLS,
all mode names/slugs, domain instructions, permissions and product workspaces.
Python 3.9+; standard library only. Never sources .env, invokes Bob/cloud tools,
installs dependencies, changes Git, or edits retrieved knowledgebase source data.
"""
from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid

HERE = Path(__file__).resolve().parent
PAYLOAD = HERE / "payload"
RELEASE = "BOB2-45.0.0"
RECORD = ".bob/patches-applied/BOB2-45.json"
BACKUP_DIR = ".bob/patch-backups/BOB2-45"
BASELINES = json.loads((HERE / "baseline.json").read_text())


class PatchError(Exception):
    pass


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def out(message: str) -> None:
    print(f"[{RELEASE}] {message}", flush=True)


def safe(root: Path, rel: str) -> Path:
    relative = Path(rel)
    if relative.is_absolute() or ".." in relative.parts:
        raise PatchError(f"Unsafe managed path: {rel}")
    path = root
    for part in relative.parts:
        path /= part
        if path.is_symlink():
            raise PatchError(f"Refusing managed symlink: {path}")
    if path.exists() and not path.is_file() and not path.is_dir():
        raise PatchError(f"Refusing non-regular filesystem object: {path}")
    return path


def atomic(path: Path, data: bytes, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".bob2-patch-", dir=str(path.parent))
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


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise PatchError(f"Invalid JSON file: {path}") from exc


def root_from(value: str | None) -> Path:
    if value:
        root = Path(value).expanduser().resolve()
    else:
        candidates = [HERE, *HERE.parents]
        root = next((p for p in candidates if (p / "use-cases").is_dir() and (p / "patches").is_dir()), None)
        if root is None:
            raise PatchError("Cannot locate repository root. Copy the bundle's patches/ into the repository, or pass --root /path/to/repository.")
    if not root.is_dir() or not safe(root, "use-cases").is_dir() or not safe(root, "patches").is_dir():
        raise PatchError("Target must be the use-case repository containing both use-cases/ and patches/.")
    return root


def manifest_from_record(root: Path) -> tuple[Path, dict]:
    record = load_json(safe(root, RECORD))
    if record.get("release") != RELEASE:
        raise PatchError("Unexpected installed patch release.")
    rel = record.get("backup", "")
    if not rel.startswith(BACKUP_DIR + "/") or not re.fullmatch(r"[A-Za-z0-9./_-]+", rel):
        raise PatchError("Invalid rollback snapshot pointer.")
    backup = safe(root, rel)
    manifest = load_json(safe(root, rel + "/manifest.json"))
    if manifest.get("release") != RELEASE or manifest.get("status") != "applied":
        raise PatchError("The recorded rollback snapshot is not an applied transaction.")
    return backup, manifest


def verify_installed(root: Path) -> tuple[Path, dict]:
    backup, manifest = manifest_from_record(root)
    verify_preserved(root, manifest['code'])
    for rel, info in manifest["files"].items():
        path = safe(root, rel)
        after = info["after"]
        if after is None:
            if path.exists():
                raise PatchError(f"A removed path was recreated: {path}")
            continue
        if not path.is_file() or digest(path.read_bytes()) != after["sha256"]:
            raise PatchError(f"Patch 45 managed file has local edits or is missing: {path}. Preserve/reconcile before reapply or rollback.")
        if stat.S_IMODE(path.stat().st_mode) != after["mode"]:
            raise PatchError(f"Patch 45 managed permissions changed: {path}")
    for rel, info in manifest["files"].items():
        before = info["before"]
        if before is not None:
            original = safe(root, str(backup.relative_to(root) / "files" / rel))
            if not original.is_file() or digest(original.read_bytes()) != before["sha256"]:
                raise PatchError(f"Rollback backup is missing or corrupted for {rel}")
    return backup, manifest


def verify_preserved(root: Path, code: str) -> None:
    for rel, info in BASELINES[code]['preserved'].items():
        p = safe(root, rel)
        if not p.is_file() or digest(p.read_bytes()) != info['sha256'] or stat.S_IMODE(p.stat().st_mode) != info['mode']:
            raise PatchError('Protected UI/auth/TLS/mode-routing component drift: ' + rel)



def instruction_documents(root: Path) -> dict[str,str]:
    """Every active rule/skill document and project policy, not reference datasets."""
    result = {}
    def add(path: Path, category: str):
        rel=str(path.relative_to(root));safe(root,rel)
        if path.is_file() and path.suffix.lower() in {'.md','.markdown','.txt'}:
            result[rel]=category
    for name in ('AGENTS.md','POLICY.md','POLICIES.md'):
        path=safe(root,name)
        if path.is_file():add(path,'policy')
    bob=safe(root,'.bob')
    for directory in sorted(bob.iterdir()):
        safe(root,str(directory.relative_to(root)))
        if directory.is_dir() and (directory.name=='rules' or directory.name.startswith('rules-')):
            for p in sorted(directory.rglob('*')):add(p,'rule')
        elif directory.is_dir() and directory.name=='skills':
            for p in sorted(directory.rglob('*')):add(p,'skill' if p.name.lower()=='skill.md' else 'skill-support')
        elif directory.is_dir() and directory.name.lower() in ('policies','policy'):
            for p in sorted(directory.rglob('*')):add(p,'policy')
        elif directory.is_file() and ('policy' in directory.name.lower() or 'policies' in directory.name.lower() or directory.name=='AGENTS.md'):
            add(directory,'policy')
    # Explicitly named instruction policies may live beside domain tools. Do not
    # rewrite knowledgebase reference articles or operational/template policies.
    excluded={'patch-backups','patches-applied','.git','node_modules','__pycache__',
              '.venv','venv','.terraform','runtime','skills','policies','policy'}
    for parent,dirs,files in os.walk(bob,followlinks=False):
        dirs[:]=[d for d in dirs if d not in excluded and not d.endswith('-knowledgebase') and not d.startswith('rules')]
        for d in dirs:safe(root,str((Path(parent)/d).relative_to(root)))
        for name in files:
            if name.lower() in {'agents.md','policy.md','policies.md'} or name.lower().endswith(('-policy.md','-policies.md')):
                add(Path(parent)/name,'policy')
    return dict(sorted(result.items()))

class Plan:
    def __init__(self, repo: Path, code: str):
        self.repo = repo
        self.code = code
        self.baseline = BASELINES[code]
        self.root = safe(repo, "use-cases/" + self.baseline["folder"])
        self.payload = PAYLOAD / code
        self.config = load_json(safe(self.root, ".bob/runtime/bob-v2/appliance.json")) if safe(self.root, ".bob/runtime/bob-v2/appliance.json").is_file() else {}
        self.files: dict[str, tuple[bytes | None, int]] = {}
        self.current: dict[str, tuple[bytes | None, int]] = {}
        self.already = False
        if not self.root.is_dir():
            raise PatchError(f"Missing appliance: {self.root}")
        # Check fundamental roots before reading recursively; no symlink traversal.
        for rel in (".bob", ".bob/skills", ".bob/runtime", ".bob/patch-backups", ".bob/patches-applied"):
            safe(self.root, rel)
        if safe(self.root, RECORD).exists():
            verify_installed(self.root)
            self.already = True
            return
        self.prepare()

    def put(self, rel: str, data: bytes | None, mode: int = 0o644, expected: str | None = None) -> None:
        p = safe(self.root, rel)
        if p.exists() and not p.is_file():
            raise PatchError(f"File destination is occupied by a directory: {p}")
        before = p.read_bytes() if p.exists() else None
        old_mode = stat.S_IMODE(p.stat().st_mode) if p.exists() else 0
        if expected is not None and before is not None and digest(before) != expected:
            if data is None or before != data:
                raise PatchError(f"Baseline drift: {p}. This patch will not overwrite an unreviewed local revision.")
        if before == data and (data is None or old_mode == mode):
            return
        self.current[rel] = (before, old_mode)
        self.files[rel] = (data, mode)

    def new(self, rel: str, data: bytes, mode: int = 0o644) -> None:
        p = safe(self.root, rel)
        if p.exists() and p.read_bytes() != data:
            raise PatchError(f"New patch destination already has different content: {p}")
        self.put(rel, data, mode)

    def prepare(self) -> None:
        prior = load_json(safe(self.root, '.bob/patches-applied/BOB2-44.json'))
        if prior.get('release') != 'BOB2-44.0.0' or prior.get('code') != self.code:
            raise PatchError(f'{self.code}: install Patch 44 first; do not roll it back.')
        pointer = prior.get('backup', '')
        if not isinstance(pointer,str) or not pointer.startswith('.bob/patch-backups/BOB2-44/'):
            raise PatchError('Invalid Patch 44 snapshot pointer.')
        manifest = load_json(safe(self.root, pointer + '/manifest.json'))
        if manifest.get('release') != 'BOB2-44.0.0' or manifest.get('code') != self.code or manifest.get('status') != 'applied':
            raise PatchError('Patch 44 must be applied, not rolled back.')
        for name, info in manifest.get('files', {}).items():
            p = safe(self.root, name)
            after = info.get('after')
            if after is None:
                if p.exists():
                    raise PatchError('Patch 44 removed file was recreated: ' + name)
            elif not p.is_file() or digest(p.read_bytes()) != after['sha256'] or stat.S_IMODE(p.stat().st_mode) != after['mode']:
                raise PatchError('Patch 44 baseline drift: ' + name + '. Preserve/reconcile local edits; no files have been changed.')
            before = info.get('before')
            if before is not None:
                backup = safe(self.root, pointer + '/files/' + name)
                if not backup.is_file() or digest(backup.read_bytes()) != before['sha256']:
                    raise PatchError('Patch 44 rollback material is missing/corrupt: ' + name)
        verify_preserved(self.root, self.code)
        launchers = list(self.root.glob('bob-' + self.baseline['stem'] + '-v*.sh'))
        if len(launchers) != 1 or digest(safe(self.root, launchers[0].name).read_bytes()) != self.baseline['launcher_sha256']:
            raise PatchError('Expected one unmodified versioned launcher. Patch 45 does not rename launchers.')
        for name, expected in self.baseline['expected'].items():
            p = safe(self.root, name)
            if not p.is_file() or digest(p.read_bytes()) != expected:
                raise PatchError('Baseline drift: ' + name + '. Reconcile the local revision before applying Patch 45.')
        common = PAYLOAD / 'common'
        self.put('.bob/runtime/bob-v2/production_display.py', (common/'production_display.py').read_bytes(), 0o755)
        self.new('.bob/runtime/bob-v2/terminal_style.py', (common/'terminal_style.py').read_bytes(), 0o755)
        self.new('.bob/BOB2-DOCUMENTATION-DISCOVERY-POLICY.md', (common/'discovery-policy.md').read_bytes())
        self.put('.bob/runtime/bob-v2/runtime.py', (common/'runtime.py').read_bytes(), 0o755)
        self.put('.bob/hooks/bob2-context.py', (common/'bob2-context.py').read_bytes(), 0o755)
        self.put('.bob/custom_modes.yaml', (self.payload/'custom_modes.yaml').read_bytes())
        self.put('.bob/BOB2-PRODUCTION-DISPLAY-PLAN.md', (common/'display-plan.md').read_bytes())
        self.put('.bob/BOB2-RETRIEVAL-DISPLAY-POLICY.md', (common/'retrieval-policy.md').read_bytes())
        directive = (common/'display-pointer.md').read_text(encoding='utf-8').strip()
        coverage = {}
        for name, category in instruction_documents(self.root).items():
            if name in ('.bob/BOB2-PRODUCTION-DISPLAY-PLAN.md', '.bob/BOB2-RETRIEVAL-DISPLAY-POLICY.md', '.bob/BOB2-DOCUMENTATION-DISCOVERY-POLICY.md'):
                continue
            p = safe(self.root,name)
            try:
                text = p.read_text(encoding='utf-8')
            except UnicodeDecodeError as exc:
                raise PatchError('Instruction file is not UTF-8: ' + name) from exc
            if '<!-- BOB2-45-DISCOVERY-DISPLAY:' in text:
                raise PatchError('Unrecorded Patch 45 directive found: ' + name)
            old = re.compile(r'<!-- BOB2-44-RETRIEVAL:BEGIN -->.*?<!-- BOB2-44-RETRIEVAL:END -->',re.S)
            text, replaced = old.subn(lambda _: directive, text)
            if '<!-- BOB2-44-RETRIEVAL:' in text:
                raise PatchError('Malformed Patch 44 instruction block: ' + name)
            if replaced == 0:
                text = text.rstrip() + '\n\n' + directive + '\n'
            self.put(name,text.encode('utf-8'),stat.S_IMODE(p.stat().st_mode))
            coverage[name] = category
        text = (self.payload/'custom_modes.yaml').read_text()
        slugs = re.findall(r'^- slug: ([a-z0-9-]+)$',text,re.M)
        if len(slugs) != self.baseline['mode_count'] or len(slugs) != len(set(slugs)) or not {'ask','code','advance'} <= set(slugs):
            raise PatchError('Custom-mode count/slug invariant failed.')
        if text.count('<!-- BOB2-45-DISCOVERY-DISPLAY:BEGIN -->') != len(slugs) or '<!-- BOB2-44-RETRIEVAL:' in text:
            raise PatchError('Not every custom mode received the retrieval directive.')
        report = {'release':RELEASE,'code':self.code,'instruction_documents':coverage,
                  'modes':slugs, 'policy':'.bob/BOB2-RETRIEVAL-DISPLAY-POLICY.md',
                  'plan':'.bob/BOB2-PRODUCTION-DISPLAY-PLAN.md',
                  'discovery':'.bob/BOB2-DOCUMENTATION-DISCOVERY-POLICY.md',
                  'excluded':'Historical snapshots/patches, product/reference data, environments, stores, credentials and workspaces are not instruction targets.'}
        self.new('.bob/BOB2-45-POLICY-COVERAGE.json',(json.dumps(report,indent=2)+'\n').encode())
        for name,(data,mode) in self.files.items():
            if data is None:continue
            if name.endswith('.py'):compile(data,name,'exec')
            elif name.endswith('.json'):json.loads(data)

    def verify_no_race(self) -> None:
        for rel, (before, mode) in self.current.items():
            p = safe(self.root, rel)
            actual = p.read_bytes() if p.is_file() else None
            if actual != before or (p.exists() and stat.S_IMODE(p.stat().st_mode) != mode):
                raise PatchError(f"Source changed after preflight: {p}")

    def apply(self, transaction: str) -> tuple[Path, dict] | None:
        if self.already:
            out(f"{self.code}: already applied; verified, no changes.")
            return None
        self.verify_no_race()
        backup_rel = BACKUP_DIR + "/" + transaction
        backup = safe(self.root, backup_rel)
        backup.mkdir(parents=True, mode=0o700)
        os.chmod(backup, 0o700)
        manifest = {"release": RELEASE, "code": self.code, "stem": self.baseline["stem"], "status": "preparing",
                    "transaction": transaction,
                    "created_at": dt.datetime.now(dt.timezone.utc).isoformat(), "files": {}, "created_dirs": []}
        # Snapshot *all* originals before applying the first change.
        for rel, (data, mode) in self.files.items():
            before, old_mode = self.current[rel]
            entry = {"before": None, "after": None}
            if before is not None:
                atomic(backup / "files" / rel, before, old_mode)
                entry["before"] = {"sha256": digest(before), "mode": old_mode}
            if data is not None:
                entry["after"] = {"sha256": digest(data), "mode": mode}
            manifest["files"][rel] = entry
            parent = safe(self.root, rel).parent
            while parent != self.root and not parent.exists():
                relative = str(parent.relative_to(self.root))
                if relative not in manifest["created_dirs"]:
                    manifest["created_dirs"].append(relative)
                parent = parent.parent
        atomic(backup / "manifest.json", (json.dumps(manifest, indent=2) + "\n").encode(), 0o600)
        try:
            for rel, (data, mode) in self.files.items():
                path = safe(self.root, rel)
                if data is None:
                    path.unlink()
                else:
                    atomic(path, data, mode)
            manifest["status"] = "applied"
            atomic(backup / "manifest.json", (json.dumps(manifest, indent=2) + "\n").encode(), 0o600)
            record = {"release": RELEASE, "code": self.code, "backup": backup_rel, "transaction": transaction}
            atomic(safe(self.root, RECORD), (json.dumps(record, indent=2) + "\n").encode(), 0o600)
            verify_installed(self.root)
        except BaseException:
            restore(self.root, backup, manifest, automatic=True)
            raise
        out(f"{self.code}: applied {len(self.files)} file/content/permission changes; rollback snapshot {backup_rel}")
        return backup, manifest


def restore(root: Path, backup: Path, manifest: dict, automatic: bool = False) -> None:
    if not automatic:
        verify_installed(root)
    for rel, info in reversed(list(manifest["files"].items())):
        path = safe(root, rel)
        before = info["before"]
        if before is None:
            if path.exists():
                if not path.is_file():
                    raise PatchError(f"Rollback refused non-file: {path}")
                path.unlink()
        else:
            original = backup / "files" / rel
            data = original.read_bytes()
            if digest(data) != before["sha256"]:
                raise PatchError(f"Corrupt backup: {rel}")
            atomic(path, data, before["mode"])
    record = safe(root, RECORD)
    if record.exists():
        record.unlink()
    for rel in sorted(manifest.get("created_dirs", []), key=lambda s: len(Path(s).parts), reverse=True):
        p = safe(root, rel)
        try:
            p.rmdir()  # Never recursively delete; retain later user files.
        except (FileNotFoundError, OSError):
            pass
    manifest["status"] = "rolled-back"
    manifest["rolled_back_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
    atomic(backup / "manifest.json", (json.dumps(manifest, indent=2) + "\n").encode(), 0o600)
    out(f"{manifest['code']}: restored original file bytes and permissions; audit snapshot retained.")


@contextlib.contextmanager
def patch_lock(repo: Path, codes: list[str]):
    path = safe(repo, "patches/.bob2-upgrade.lock")
    streams = []
    try:
        # The repository lock serializes patch controllers; session locks stop an
        # upgrade from changing a running, already-upgraded appliance.
        paths = [path]
        for code in codes:
            candidate = safe(repo, "use-cases/" + BASELINES[code]["folder"] + "/.bob/runtime/bob-v2/.session.lock")
            if candidate.parent.is_dir():
                paths.append(candidate)
        for lock_path in paths:
            stream = open(lock_path, "a", encoding="utf-8")
            streams.append(stream)
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as exc:
                raise PatchError("Another patch or appliance session is active. Close it before patching.") from exc
        yield
    finally:
        for stream in reversed(streams):
            stream.close()


def verify_bundle() -> None:
    index = HERE / "payload-sha256.json"
    if not index.is_file():
        raise PatchError("Payload checksum manifest is missing.")
    for rel, expected in load_json(index).items():
        p = safe(HERE, rel)
        if not p.is_file() or digest(p.read_bytes()) != expected:
            raise PatchError(f"Patch payload checksum mismatch: {rel}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--check", action="store_true", help="read-only preflight; the default")
    action.add_argument("--apply", action="store_true", help="apply selected patches with rollback snapshots")
    action.add_argument("--rollback", action="store_true", help="restore original bytes/modes from the installed snapshot")
    action.add_argument("--status", action="store_true", help="verify installed patches")
    parser.add_argument("--root", help="repository root containing patches/ and use-cases/")
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--all", action="store_true")
    selection.add_argument("--only", choices=list(BASELINES), help="one appliance code")
    args = parser.parse_args()
    verify_bundle()
    repo = root_from(args.root)
    codes = [args.only] if args.only else list(BASELINES)
    if args.status:
        for code in codes:
            root = safe(repo, "use-cases/" + BASELINES[code]["folder"])
            if safe(root, RECORD).exists():
                _, m = verify_installed(root)
                out(f"{code}: APPLIED and verified ({m['transaction']}).")
            else:
                out(f"{code}: NOT APPLIED.")
        return 0
    if args.rollback:
        with patch_lock(repo, codes):
            prepared = []
            for code in codes:
                root = safe(repo, "use-cases/" + BASELINES[code]["folder"])
                if not safe(root, RECORD).exists():
                    out(f"{code}: not applied; nothing to roll back.")
                    continue
                backup, manifest = verify_installed(root)
                prepared.append((root, backup, manifest))
            for root, backup, manifest in reversed(prepared):
                restore(root, backup, manifest)
        return 0
    if not args.apply:
        for code in codes:
            plan = Plan(repo, code)
            out(f"{code}: {'already applied and verified' if plan.already else f'preflight PASS; {len(plan.files)} planned changes'}")
        out("Read-only preflight complete. No .env, product workload, cloud service, or Git command was executed.")
        return 0
    with patch_lock(repo, codes):
        # All selected appliances must pass before any appliance is modified.
        plans = [Plan(repo, code) for code in codes]
        transaction = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
        completed = []
        try:
            for plan in plans:
                result = plan.apply(transaction)
                if result:
                    completed.append((plan.root, *result))
        except BaseException:
            out("Apply failed; restoring previously applied appliances in this transaction.")
            for root, backup, manifest in reversed(completed):
                restore(root, backup, manifest, automatic=True)
            raise
    out("Patch 45 complete. Run xLaunchpad.sh --preview and --doctor, then verify discovery-first retrieval, status styling and cyan native input/footer in each appliance. Use Patch 45 --status; do not reapply older patches.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (PatchError, OSError, ValueError, SyntaxError) as exc:
        print(f"[{RELEASE}] ERROR: {exc}", file=sys.stderr)
        sys.exit(2)
    except KeyboardInterrupt:
        print(f"[{RELEASE}] Interrupted.", file=sys.stderr)
        sys.exit(130)
