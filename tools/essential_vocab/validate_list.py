#!/usr/bin/env python3
"""Validate essential vocab JSON catalogs (unique id/front/rank, non-empty fields)."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def validate(path: Path) -> list[str]:
    issues: list[str] = []
    data = json.loads(path.read_text(encoding="utf-8"))
    entries = data.get("entries") or []
    if not entries:
        issues.append(f"{path.name}: entries empty")
    seen_ids: set[str] = set()
    seen_fronts: set[str] = set()
    seen_ranks: set[int] = set()
    for e in entries:
        eid = e.get("id", "")
        front = (e.get("front") or "").strip()
        back = (e.get("back") or "").strip()
        rank = e.get("rank")
        if not front:
            issues.append(f"{path.name}: empty front for {eid}")
        if not back:
            issues.append(f"{path.name}: empty back for {eid}")
        if not isinstance(rank, int) or rank <= 0:
            issues.append(f"{path.name}: bad rank for {eid}")
        if eid in seen_ids:
            issues.append(f"{path.name}: duplicate id {eid}")
        seen_ids.add(eid)
        if front in seen_fronts:
            issues.append(f"{path.name}: duplicate front {front}")
        seen_fronts.add(front)
        if rank in seen_ranks:
            issues.append(f"{path.name}: duplicate rank {rank}")
        seen_ranks.add(rank)
    return issues


def main() -> int:
    root = Path(__file__).resolve().parents[2] / "Sources" / "EssentialVocab"
    files = list(root.glob("essential_*_v*.json"))
    if not files:
        print("No catalog files found", file=sys.stderr)
        return 1
    all_issues: list[str] = []
    for f in sorted(files):
        all_issues.extend(validate(f))
        print(f"OK {f.name}" if not any(f.name in i for i in all_issues) else f"FAIL {f.name}")
    if all_issues:
        for i in all_issues:
            print(i, file=sys.stderr)
        return 1
    print(f"Validated {len(files)} catalog file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
