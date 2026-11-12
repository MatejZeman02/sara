"""The template writer's reading of a pixel function's uniforms.

A `.gmacs` pixel function registered as a filter earns a widget for each
`uniform` line, and the widget's label is the uniform's name as
`SaPixelFilter.title_for` writes it, `level` as "Level" and `box_size` as
"Box size". The label goes through the catalogue in `SaSlider` and its
siblings, but no `.gd` file spells it, so `write_pot.py` never held it and the
dialog's one row stayed English under every language. This file reads each
uniform's name from the kernels of the tree and hands the template its title,
on the line the uniform stands on.

An array uniform, `float near[9]`, is the grid named by the name before its
bracket, as `SaPixelFilter` names it.

A pixel function's leading comment is its filter's sentence, the first
paragraph as `SaPixelFilter.leading_sentence` joins it, which the menu row's
tooltip shows. No `.gd` file spells that either, so it is read here too, or
the box blur's sentence would have left the catalogue when it moved into its
kernel.
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

UNIFORM = re.compile(r"^uniform\s+\w+\s+([A-Za-z_]\w*)")

# The one function a pixel function's file defines, which tells it from a
# written kernel, whose leading comment is no filter's sentence.
PIXEL = re.compile(r"^def\s+pixel\s*\(", re.MULTILINE)


def title_for(stem: str) -> str:
    """`threshold` as "Threshold": the underscores spaces and the first letter a capital."""
    words = stem.replace("_", " ").strip()
    return words[:1].upper() + words[1:] if words else ""


def uniform_titles(kernels: dict[str, str]) -> list[tuple[str, str, int]]:
    """Each uniform's title in *kernels*, with its file and the line it stands on, counted from one."""
    out: list[tuple[str, str, int]] = []
    for path, text in kernels.items():
        for number, line in enumerate(text.splitlines(), start=1):
            found = UNIFORM.match(line)
            if found and title_for(found.group(1)):
                out.append((title_for(found.group(1)), path, number))
    return out


def leading_sentences(kernels: dict[str, str]) -> list[tuple[str, str, int]]:
    """Each pixel function's sentence in *kernels*, with its file and the line it opens on, counted from one.

    The first paragraph of the `#` lines the file opens with, joined by spaces,
    the licence line left out, as `SaPixelFilter.leading_sentence` reads it.
    Only a file under a module's folder, because a module is what registers a
    filter, and the shipped patterns under `patterns/` are pixel functions too
    whose comments no painter is shown.
    """
    out: list[tuple[str, str, int]] = []
    for path, text in kernels.items():
        if "modules" not in Path(path).parts or not PIXEL.search(text):
            continue
        words: list[str] = []
        first = 0
        for number, line in enumerate(text.splitlines(), start=1):
            trimmed = line.strip()
            if not trimmed.startswith("#"):
                break
            said = trimmed[1:].strip()
            if not said:
                if words:
                    break
                continue
            if said.startswith("SPDX-License-Identifier"):
                continue
            first = first or number
            words.append(said)
        if words:
            out.append((" ".join(words), path, first))
    return out


def kernel_sources(root: Path, tracked: bool) -> dict[str, str]:
    """Every pixel function under *root* outside a tests folder, by its path under it.

    *tracked* reads git's list, submodules too, as `tracked_sources` does, and
    otherwise the folder itself, a fixture's that is not a checkout.
    """
    if tracked:
        listed = subprocess.run(
            ["git", "ls-files", "--recurse-submodules", "*.gmacs"],
            cwd=root,
            capture_output=True,
            encoding="utf-8",
            check=True,
        ).stdout.splitlines()
    else:
        listed = [f.relative_to(root).as_posix() for f in root.rglob("*.gmacs")]
    out: dict[str, str] = {}
    for path in sorted(listed):
        file = root / path
        if "tests" not in Path(path).parts and file.is_file():
            out[path] = file.read_text(encoding="utf-8", errors="replace")
    return out
