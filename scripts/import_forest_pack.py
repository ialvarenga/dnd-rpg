#!/usr/bin/env python3
"""Copy the Color1 KayKit forest models into the project's managed layout."""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path


FAMILIES = (("Tree_", "trees"), ("Bush_", "bushes"), ("Grass_", "grass"), ("Rock_", "rocks"), ("Hill_", "hills"))
DESTINATION = Path(__file__).resolve().parents[1] / "godot/assets/kaykit_forest"
TEXTURE_URI = '"uri" : "forest_texture.png"'
SHARED_TEXTURE_URI = '"uri" : "../forest_texture.png"'


def family_for(name: str) -> str | None:
    for prefix, family in FAMILIES:
        if name.startswith(prefix):
            return family
    return None


def retarget_texture(gltf: Path) -> None:
    """Rewrite the atlas URI to the shared copy one directory up."""
    text = gltf.read_text()
    if TEXTURE_URI not in text:
        raise SystemExit("Unexpected texture URI in %s" % gltf)
    gltf.write_text(text.replace(TEXTURE_URI, SHARED_TEXTURE_URI))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pack_root", type=Path)
    args = parser.parse_args()
    source = args.pack_root / "Assets/gltf/Color1"
    if not source.is_dir():
        raise SystemExit("Color1 glTF directory not found: %s" % source)

    copied = 0
    for gltf in sorted(source.glob("*.gltf")):
        family = family_for(gltf.name)
        if family is None:
            continue
        target_dir = DESTINATION / family
        target_dir.mkdir(parents=True, exist_ok=True)
        for item in (gltf, gltf.with_suffix(".bin")):
            if not item.is_file():
                raise SystemExit("Missing companion file: %s" % item)
            shutil.copy2(item, target_dir / item.name)
        # glTF image URIs are relative to the model. Point every family at the one
        # shared atlas: Godot's glTF importer does not resolve symlinked images and
        # silently drops the albedo texture when it cannot find the file.
        retarget_texture(target_dir / gltf.name)
        copied += 1
    print("Copied %d Color1 models into %s" % (copied, DESTINATION))


if __name__ == "__main__":
    main()
