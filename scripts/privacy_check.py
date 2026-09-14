#!/usr/bin/env python3
"""Check the public source allowlist without printing matched private values.

This is a heuristic release check, not a secret-management or security audit tool.
It never follows symlinks or reads files named like credentials. Build outputs are
only inspected after an explicit --include-build / --include-dist request.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT_FILES = {
    "README.md", "LICENSE", "CHANGELOG.md", "INSTALL_WITH_AGENT.md",
    "PRIVACY.md", "SECURITY.md", "CONTRIBUTING.md", ".gitignore",
    ".gitattributes", "Makefile", "Info.plist",
}
SOURCE_DIRS = {"Sources", "Tests", "scripts", "docs", "assets"}
SOURCE_SUFFIXES = {
    ".swift", ".py", ".sh", ".zsh", ".md", ".txt", ".json", ".plist",
    ".yml", ".yaml", ".svg", ".xml", ".xcprivacy", ".entitlements",
}
PRIVATE_SUFFIXES = {
    ".p12", ".pfx", ".key", ".pem", ".cer", ".mobileprovision",
    ".provisionprofile", ".keychain", ".keychain-db",
}
PRIVATE_NAMES = {
    ".env", ".netrc", ".npmrc", ".pypirc", "credentials", "credentials.json",
    "secrets.json", "secrets.toml", "id_rsa", "id_ed25519",
}
PATTERNS = {
    "local-user-path": re.compile(rb"/(?:Users|home)/[A-Za-z0-9][A-Za-z0-9._-]*(?:/|\b)"),
    "local-temporary-path": re.compile(rb"/(?:private/)?var/folders/[A-Za-z0-9_/-]{8,}"),
    "private-project-id": re.compile(rb"\bg-p-[a-f0-9]{24,}\b"),
    "embedded-uuid-review": re.compile(rb"\b[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\b", re.I),
    "email-address": re.compile(rb"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),
    "private-key-material": re.compile(rb"-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----"),
    "github-token": re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"),
    "aws-access-key": re.compile(rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    "literal-user-process-id": re.compile(rb"\b(?:UID|PID)\s*[=:]\s*[0-9]{2,}\b", re.I),
    "machine-model-id": re.compile(rb"\b(?:MacBookPro|MacBookAir|Macmini|MacStudio|MacPro|iMac)[0-9]+,[0-9]+\b"),
    "personal-bundle-id": re.compile(rb"\blocal\.macbookpro\b"),
}


def is_private_name(path: Path) -> bool:
    name = path.name.lower()
    return name in PRIVATE_NAMES or name.startswith(".env.") or path.suffix.lower() in PRIVATE_SUFFIXES


def is_source_candidate(relative: Path) -> bool:
    parts = relative.parts
    if len(parts) == 1:
        return relative.name in ROOT_FILES or relative.name in SOURCE_DIRS or relative.name == ".github"
    return parts[0] in SOURCE_DIRS or parts[:2] == (".github", "workflows")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1], help="repository root")
    parser.add_argument("--include-build", action="store_true", help="also check unpacked files under build/")
    parser.add_argument("--include-dist", action="store_true", help="also check unpacked files under dist/")
    args = parser.parse_args()
    root = args.root.resolve()
    if not root.is_dir():
        print("ERROR: repository root is not a directory.", file=sys.stderr)
        return 2
    extra = {name for name, enabled in (("build", args.include_build), ("dist", args.include_dist)) if enabled}
    findings: list[tuple[str, str, str]] = []
    scanned = 0
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        parts = relative.parts
        if ".git" in parts or "__pycache__" in parts:
            continue
        selected = is_source_candidate(relative) or parts[0] in extra
        if not selected:
            continue
        if path.is_symlink():
            findings.append((str(relative), "-", "symlink-not-inspected"))
            continue
        if not path.is_file():
            continue
        if is_private_name(path):
            findings.append((str(relative), "-", "credential-or-certificate-file-not-read"))
            continue
        if path.name == ".DS_Store":
            findings.append((str(relative), "-", "finder-metadata"))
            continue
        is_output = parts[0] in extra
        if not is_output and len(parts) > 1 and path.suffix not in SOURCE_SUFFIXES:
            findings.append((str(relative), "-", "unexpected-public-file-type"))
            continue
        if path.suffix.lower() in {".zip", ".dmg", ".tar", ".gz", ".pkg"}:
            findings.append((str(relative), "-", "archive-not-inspected-unpack-first"))
            continue
        try:
            data = path.read_bytes()
        except OSError:
            findings.append((str(relative), "-", "unreadable-file"))
            continue
        scanned += 1
        is_binary = b"\x00" in data
        if not is_output and is_binary:
            findings.append((str(relative), "binary", "binary-content-in-public-source"))
        for category, pattern in PATTERNS.items():
            for match in pattern.finditer(data):
                location = "binary" if is_binary else str(data.count(b"\n", 0, match.start()) + 1)
                finding = (str(relative), location, category)
                if finding not in findings:
                    findings.append(finding)
    for filename, location, category in findings:
        print(f"REVIEW {filename}:{location} [{category}]")
    if findings:
        print(f"FAIL: {len(findings)} finding(s) in {scanned} inspected file(s). Matched values were not printed.")
        return 1
    print(f"PASS: {scanned} allowlisted file(s) inspected; no configured privacy patterns found.")
    print("Scope: source allowlist" + (" plus " + ", ".join(sorted(extra)) if extra else " only; build/ and dist/ excluded") + ".")
    print("This check does not establish anonymity, inspect archive contents, or replace manual review.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
