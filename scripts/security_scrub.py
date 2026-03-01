#!/usr/bin/env python3
"""Scan repository content for likely secret leaks.

The scanner supports two modes:
- Git repo mode: scans tracked files (and optional history).
- Non-git mode: scans repository files while skipping known local-only artifacts.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


@dataclass
class Rule:
    name: str
    severity: str
    pattern: re.Pattern[str]


RULES = [
    Rule("anthropic_key", "high", re.compile(r"sk-ant-[A-Za-z0-9_-]{20,}")),
    Rule("openai_project_key", "high", re.compile(r"sk-proj-[A-Za-z0-9_-]{20,}")),
    Rule("github_token", "high", re.compile(r"(ghp|gho)_[A-Za-z0-9]{20,}")),
    Rule("github_pat", "high", re.compile(r"github_pat_[A-Za-z0-9_]{20,}")),
    Rule("aws_access_key", "high", re.compile(r"AKIA[0-9A-Z]{16}")),
    Rule("aws_temp_key", "high", re.compile(r"ASIA[0-9A-Z]{16}")),
    Rule("slack_token", "high", re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}")),
    Rule(
        "private_key_block",
        "high",
        re.compile(r"-----BEGIN (RSA|OPENSSH|EC|DSA|PGP|PRIVATE) KEY-----"),
    ),
    Rule("kubeconfig_client_key_data", "high", re.compile(r"client-key-data:\s*[A-Za-z0-9+/=]{40,}")),
    Rule("k3s_join_token", "high", re.compile(r"K10[0-9a-f]{64}::server:[0-9a-f]{64}")),
    Rule("proxmox_api_token", "high", re.compile(r"root@pam![A-Za-z0-9._-]+=[A-Za-z0-9-]{12,}")),
]

# Skip noise from local state/cache and known local-only artifacts in this repo.
SKIP_PATH_PREFIXES = (
    ".git/",
    ".terraform/",
    "terraform/.terraform/",
    "terraform/.terraform.lock.hcl",
    "terraform/terraform.tfstate",
    "terraform/terraform.tfstate.backup",
    "terraform/terraform.tfvars",
)
SKIP_PATH_EXACT = {
    ".k3s-node-token",
    "kubeconfig-raw.yml",
}
SKIP_EXTENSIONS = {
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".svg",
    ".ico",
    ".pdf",
    ".zip",
    ".gz",
    ".tgz",
    ".tar",
    ".dylib",
    ".so",
    ".woff",
    ".woff2",
    ".ttf",
}

PLACEHOLDER_MARKERS = (
    "CHANGE_ME",
    "REDACTED",
    "EXAMPLE",
    "YOUR_",
    "YOUR-",
    "changeme",
    "${",
    "<",
)
SENSITIVE_KEY_HINTS = ("PASSWORD", "TOKEN", "SECRET", "API_KEY", "PRIVATE_KEY", "ENCRYPTION_KEY", "JWT")
NON_SECRET_VALUES = {"", "true", "false", "yes", "no", "null", "none", "\"\"", "''"}


def run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, check=check)


def in_git_repo() -> bool:
    proc = run(["git", "rev-parse", "--is-inside-work-tree"], check=False)
    return proc.returncode == 0


def should_skip_path(path: str) -> bool:
    if path in SKIP_PATH_EXACT:
        return True
    if any(path.startswith(prefix) for prefix in SKIP_PATH_PREFIXES):
        return True
    if Path(path).suffix.lower() in SKIP_EXTENSIONS:
        return True
    full = ROOT / path
    try:
        if full.stat().st_size > 5 * 1024 * 1024:
            return True
    except OSError:
        return True
    return False


def candidate_files() -> list[str]:
    if in_git_repo():
        proc = run(["git", "ls-files"])
        files = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    else:
        files = []
        for dirpath, dirnames, filenames in os.walk(ROOT):
            rel_dir = Path(dirpath).relative_to(ROOT).as_posix()
            # Prune common local/cache directories early.
            dirnames[:] = [d for d in dirnames if d not in {".git", ".terraform", "__pycache__", ".mypy_cache", ".pytest_cache"}]
            for filename in filenames:
                rel = f"{rel_dir}/{filename}" if rel_dir != "." else filename
                files.append(rel)
    return [p for p in files if not should_skip_path(p) and (ROOT / p).is_file()]


def is_placeholder(value: str) -> bool:
    v = value.strip().strip('"').strip("'")
    if not v:
        return True
    if v.lower() in NON_SECRET_VALUES:
        return True
    if v.startswith("${") and v.endswith("}"):
        return True
    if any(marker in v for marker in PLACEHOLDER_MARKERS):
        return True
    return False


def scan_sensitive_key_assignment(line: str) -> tuple[str, str] | None:
    # Match simple YAML assignments, then filter to uppercase env-style key names.
    match = re.match(r'^\s*([A-Za-z0-9_]+)\s*:\s*["\']?([^"\']*)["\']?\s*$', line)
    if not match:
        return None
    key, value = match.group(1), match.group(2).strip()
    if key != key.upper():
        return None
    if not any(hint in key for hint in SENSITIVE_KEY_HINTS):
        return None
    if value.lower() in NON_SECRET_VALUES:
        return None
    if len(value) < 8:
        return None
    if is_placeholder(value):
        return None
    return key, value


def scan_tree() -> list[tuple[str, str, str]]:
    findings: list[tuple[str, str, str]] = []
    for path in candidate_files():
        full = ROOT / path
        try:
            with full.open("r", errors="ignore") as fh:
                for lineno, line in enumerate(fh, start=1):
                    for rule in RULES:
                        match = rule.pattern.search(line)
                        if match:
                            findings.append(
                                (rule.severity, f"{path}:{lineno}", f"{rule.name} -> {match.group(0)[:120]}")
                            )
                    key_hit = scan_sensitive_key_assignment(line)
                    if key_hit:
                        key, value = key_hit
                        findings.append(
                            ("high", f"{path}:{lineno}", f"plaintext_sensitive_value -> {key}={value[:80]}")
                        )
        except OSError:
            continue
    return findings


def scan_history() -> list[tuple[str, str, str]]:
    if not in_git_repo():
        return []
    findings: list[tuple[str, str, str]] = []
    revs = run(["git", "rev-list", "--all"]).stdout.splitlines()
    for rev in revs:
        for rule in RULES:
            proc = run(["git", "grep", "-nI", "-E", rule.pattern.pattern, rev], check=False)
            for line in proc.stdout.splitlines():
                if not line.strip():
                    continue
                parts = line.split(":", 3)
                if len(parts) < 4:
                    continue
                _, path, lineno, content = parts
                findings.append((rule.severity, f"{rev[:8]}:{path}:{lineno}", f"{rule.name} -> {content[:120]}"))
    return findings


def show(title: str, findings: list[tuple[str, str, str]]) -> None:
    if not findings:
        print(f"[security_scrub] {title}: no findings")
        return
    print(f"[security_scrub] {title}: {len(findings)} finding(s)")
    for sev, loc, detail in findings[:200]:
        print(f"  - [{sev}] {loc} | {detail}")
    if len(findings) > 200:
        print(f"  ... truncated, {len(findings) - 200} more")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-history", action="store_true", help="Skip git history scan")
    parser.add_argument("--strict", action="store_true", help="Fail on medium findings as well as high")
    args = parser.parse_args()

    tree = scan_tree()
    hist = [] if args.no_history else scan_history()
    show("working tree", tree)
    if in_git_repo():
        show("history", hist)
    else:
        print("[security_scrub] history: skipped (not a git repository)")

    total = tree + hist
    high = sum(1 for sev, *_ in total if sev == "high")
    medium = sum(1 for sev, *_ in total if sev == "medium")
    print(f"[security_scrub] summary: high={high} medium={medium}")

    fail = high > 0 or (args.strict and medium > 0)
    if fail:
        print("[security_scrub] FAILED: potential secrets detected")
        return 1
    print("[security_scrub] PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
