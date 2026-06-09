#!/usr/bin/env python3
"""Check that markdown links to local skill files resolve."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+)\)")


def main() -> int:
    missing: list[str] = []
    for path in ROOT.rglob("*.md"):
        text = path.read_text(encoding="utf-8")
        for target in LINK_RE.findall(text):
            if "://" in target or target.startswith("#"):
                continue
            local = (path.parent / target).resolve()
            if not local.exists():
                missing.append(f"{path.relative_to(ROOT)} -> {target}")
    if missing:
        print("Missing local links:")
        print("\n".join(missing))
        return 1
    print("All local markdown links resolve.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
