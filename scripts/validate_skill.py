#!/usr/bin/env python3
"""Portable static checks for the public scale-development Codex Skill."""
from __future__ import annotations
import argparse
import re
import sys
from pathlib import Path

PERSONAL = re.compile(r"(?:[A-Za-z]:[\\\\/](?:Users|个人|home)[\\\\/]|" + re.escape("C:" + "/Users/") + "|" + re.escape("F:" + "/scale-deve-skill") + ")", re.I)
API_SECRET = re.compile(r"(?:sk-[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{20,}|Bearer\s+[A-Za-z0-9._-]{20,})")
U_PLUS = re.compile(r"<U\+[0-9A-Fa-f]{4,6}>")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("skill_root")
    args = ap.parse_args()
    root = Path(args.skill_root).resolve()
    errors: list[str] = []
    if not (root / "SKILL.md").is_file(): errors.append("missing SKILL.md")
    text_files = []
    forbidden = []
    for p in root.rglob("*"):
        if ".git" in p.relative_to(root).parts:
            continue
        if p.is_file() and (p.name.endswith((".bak", ".pyc")) or ".bak-" in p.name):
            forbidden.append(f"forbidden backup/cache file: {p.relative_to(root)}")
        if p.is_dir() and (p.name == "__pycache__" or p.name in {"outputs", "figures"} or p.name.startswith("test_")):
            forbidden.append(f"forbidden generated directory: {p.relative_to(root)}")
    errors.extend(forbidden)
    for pattern in ("*.md", "*.py", "*.R", "*.yaml", "*.yml", "*.json", "*.txt", "VERSION", "CHANGELOG.md", "LICENSE", ".gitignore"):
        text_files.extend(p for p in root.rglob(pattern) if ".git" not in p.relative_to(root).parts)
    for p in text_files:
        if any(part == "__pycache__" or part.endswith(".bak") or ".bak-" in part for part in p.parts):
            errors.append(f"forbidden backup/cache file: {p.relative_to(root)}")
            continue
        try: text = p.read_text(encoding="utf-8")
        except UnicodeDecodeError: continue
        if PERSONAL.search(text): errors.append(f"personal absolute path in {p.relative_to(root)}")
        if API_SECRET.search(text): errors.append(f"possible API secret in {p.relative_to(root)}")
        if U_PLUS.search(text) and not (p.name in {"genie_report.R", "test_genie_report.R"} or "tests" in p.parts):
            errors.append(f"unresolved Unicode escape in {p.relative_to(root)}")
    required = [
        "SKILL.md", "README.md", "LICENSE", "CHANGELOG.md", "VERSION", ".gitignore",
        "agents/openai.yaml", ".github/workflows/test.yml",
        "scripts/build_aigenie_call.py", "scripts/genie_report.R", "scripts/genie_report_docx.py",
        "scripts/setup_check.R", "assets/construct_template.json",
        "tests/test_build_aigenie_call.py", "tests/test_genie_report.R",
        "tests/test_genie_report_docx.py", "tests/fixtures/fake_items.csv",
        "tests/fixtures/fake_genie_results_raw.rds",
    ]
    for rel in required:
        if not (root / rel).is_file(): errors.append(f"missing required file: {rel}")
    if errors:
        print("Skill validation failed:")
        print("\n".join(f"- {e}" for e in errors))
        return 1
    print(f"Skill validation OK: {root}")
    return 0

if __name__ == "__main__": raise SystemExit(main())
