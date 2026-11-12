#!/usr/bin/env python3
"""Read a walk's texts for the ones the test language did not mark.

    cd sara-godot && python scripts/unmarked_texts.py <texts.json> [out-folder]

The test language (`scripts/write_pseudo.py`) puts every catalogue message
between `‹` and `›`. A text that reaches the screen without passing through the
catalogue, or that was built before the language was set, shows with neither,
and that is the same text a Czech painter sees in English. The walk,
`scenarios/every-text-sara-shows-under-the-test-language-is-marked-so-none-stays-english-under-another.py`,
asks the running app for every text each place shows, the `cut_labels` step's
`texts` form, and writes them to `texts.json` as a list of places, each
`{"where", "shot", "texts"}` and each text `{"path", "kind", "what", "text",
"rect"}`. This reads that list.

A text is unmarked when it holds a letter and neither mark. One that is meant
to stay as written, a file name, a version, a document's layer, a module's
or a font's own name, is matched by `KEPT` and listed apart with its reason, so
a second run shows what is left to mend and what was decided. The same text at
the same path is listed once, at the first place it showed.

`write_page` writes `unmarked.md` under the out folder, with a crop of each
text out of its place's shot under `crops/` where Pillow is installed and the
shot holds the text. Exits 1 when an unmarked text is left that `KEPT` does not
name, so a scenario reads the answer off the exit code.
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

OPEN_MARK = "‹"
CLOSE_MARK = "›"

# How far round a text its crop reaches, in pixels, so the reader sees the
# control it sits on.
MARGIN = 6


@dataclass(frozen=True)
class Kept:
    """A text meant to stay as written, by the path it shows at or by its words."""

    path: str
    text: str
    reason: str

    def matches(self, entry: dict) -> bool:
        return bool(re.search(self.path, entry.get("path", ""))) and bool(re.fullmatch(self.text, entry.get("text", ""), re.S))


# Each text the hunt found that is not a message: a name the document, the
# file system or a module owns, which no catalogue carries. A pattern is a
# regular expression, the path searched and the text matched whole.
KEPT: list[Kept] = [
    Kept(
        r"/NewsSections/",
        r".+",
        "the release notes, which a language module translates as a whole page of its own and the test language has none of",
    ),
    Kept(r"/Chord_|/ChordRow/", r".+", "a key chord, written as the keys are printed, which no catalogue translates"),
    Kept(
        r"/Row_(item|docker)_\d+/Hint$",
        r"((Ctrl|Shift|Alt|Meta)\+)*(F\d+|[A-Z0-9]|[-=,.\[\]]|Backspace|Delete|Space|Numpad \d)",
        "a menu row's key chord, written as the keys are printed, which no catalogue translates",
    ),
    Kept(r"/PathBox/PathLabel$|/Folder/PathLabel$", r".+", "a folder on this computer, which is a name the file system owns"),
    Kept(r"/Row_item_\d+/Label$", r"/.+", "a folder on this computer, which is a name the file system owns"),
    Kept(r"/CreditLine$", r"Over the ridges", "the welcome picture's own title, which its painter gave it"),
    Kept(
        r"/Labels/Title$|/LanguageOpt$|/@Label@\d+$|/@HBoxContainer@\d+$",
        r"(\d+\. )?English, (XA|United States of America)",
        "a language's own name, which reads in that language and not in the one around it",
    ),
    Kept(
        r"/Labels/Title$|/Categories/|/PageTitle$",
        r"MIDI|JPEG XL|Pseudo Language",
        "a module's own name, which its manifest gives it",
    ),
    Kept(r"/FormatOption$", r"PNG|JPEG XL|JPEG|WebP|TIFF|EXR|OpenEXR|PSD|KRA|ORA", "a file format's own name"),
    Kept(r"/Row_item_\d+/Label$", r"sRGB / Rec\. 709", "a colour standard's own name, the same in every language"),
    Kept(r"/BackgroundValue$|/ForegroundValue$", r"#[0-9a-f]{6}", "a colour's hex code, the same in every language"),
    Kept(r"/DepthValue$", r"F16|F32|U8|U16", "a texture format's code, the same in every language"),
    Kept(r"/GamutValue$|/WhiteValue$", r"sRGB / Rec\. 709|D65 \(.*\)", "a colour standard's own name, the same in every language"),
    Kept(r"/BrowserRows/|/Row_item_\d+/Label$", r"3D", "a family's name in the filter browser that is an abbreviation, the same in every language"),
    Kept(r"/WorkspacePresetOpt$", r"default", "the name of the painter's saved workspace, which is the painter's own word"),
    Kept(r"/Label$", r"-?\d+(\.\d+)? (EV|s)", "a value with its unit's symbol, EV or s, the same in every language"),
]


def has_letter(text: str) -> bool:
    return any(ch.isalpha() for ch in text)


def is_unmarked(entry: dict) -> bool:
    """Whether *entry*'s text has a letter in it and carries neither mark."""
    text = entry.get("text", "")
    return has_letter(text) and OPEN_MARK not in text and CLOSE_MARK not in text


def reason_kept(entry: dict, kept: list[Kept] | None = None) -> str | None:
    for rule in KEPT if kept is None else kept:
        if rule.matches(entry):
            return rule.reason
    return None


def unmarked(places: list[dict], kept: list[Kept] | None = None) -> tuple[list[dict], list[dict]]:
    """The unmarked texts of *places*, as `(left, kept)`: each entry is the text
    with `where` and `shot` of the place it was first seen in, and a kept one
    carries the `reason` it stays."""
    left: list[dict] = []
    stays: list[dict] = []
    seen: set[tuple[str, str, str]] = set()
    for place in places:
        for entry in place.get("texts", []):
            if not is_unmarked(entry):
                continue
            key = (entry.get("path", ""), entry.get("what", ""), entry.get("text", ""))
            if key in seen:
                continue
            seen.add(key)
            found = dict(entry, where=place.get("where", ""), shot=place.get("shot", ""))
            reason = reason_kept(entry, kept)
            if reason is None:
                left.append(found)
            else:
                stays.append(dict(found, reason=reason))
    return left, stays


def crop(entry: dict, shots: Path, crops: Path, index: int) -> str | None:
    """A crop of *entry* out of its shot, its file name under *crops*, or None
    where there is no Pillow, no shot or no place in it."""
    rect = entry.get("rect") or []
    shot = shots / entry.get("shot", "")
    if len(rect) != 4 or not entry.get("shot") or not shot.is_file():
        return None
    try:
        from PIL import Image
    except ImportError:
        return None
    with Image.open(shot) as picture:
        x, y, w, h = rect
        box = (max(0, x - MARGIN), max(0, y - MARGIN), min(picture.width, x + w + MARGIN), min(picture.height, y + h + MARGIN))
        if box[2] <= box[0] or box[3] <= box[1]:
            return None
        crops.mkdir(parents=True, exist_ok=True)
        name = f"{index:03d}.png"
        picture.crop(box).save(crops / name)
    return name


def write_page(places: list[dict], out: Path, kept: list[Kept] | None = None) -> tuple[list[dict], list[dict]]:
    """`unmarked.md` under *out*, the texts left and the texts kept, each with
    its path and a crop, and the two lists it wrote."""
    left, stays = unmarked(places, kept)
    lines = [
        "# Texts with no mark of the test language, en_XA",
        "",
        f"{sum(len(p.get('texts', [])) for p in places)} texts read in {len(places)} places, "
        f"{len(left)} unmarked, {len(stays)} meant to stay as written.",
        "",
        "## Unmarked",
        "",
    ]
    for i, entry in enumerate(left, 1):
        name = crop(entry, out, out / "crops", i)
        picture = f", ![](crops/{name})" if name else ""
        lines.append(f"- **{entry['where']}**, `{entry['path']}` ({entry['kind']}, {entry['what']}): {entry['text']!r}{picture}")
    if not left:
        lines.append("None.")
    lines += ["", "## Meant to stay as written", ""]
    for entry in stays:
        lines.append(f"- **{entry['where']}**, `{entry['path']}` ({entry['what']}): {entry['text']!r}, {entry['reason']}")
    if not stays:
        lines.append("None.")
    (out / "unmarked.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return left, stays


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__.strip().splitlines()[2].strip())
        return 2
    source = Path(argv[0])
    out = Path(argv[1]) if len(argv) > 1 else source.parent
    places = json.loads(source.read_text(encoding="utf-8"))
    left, stays = write_page(places, out)
    print(f"{len(left)} unmarked texts, {len(stays)} meant to stay, {out / 'unmarked.md'}")
    return 1 if left else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
