#!/usr/bin/env python3
"""Fail fast on Godot's strict indentation rule before opening the editor."""

from __future__ import annotations

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1] / "godot"


def main() -> int:
    failures: list[str] = []
    for source in ROOT.rglob("*.gd"):
        for number, line in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):
            indentation = line[: len(line) - len(line.lstrip(" \t"))]
            if " " in indentation:
                failures.append(f"{source.relative_to(ROOT)}:{number}: leading indentation must use tabs only")
    if failures:
        print("\n".join(failures))
        return 1
    print("GDScript indentation check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
