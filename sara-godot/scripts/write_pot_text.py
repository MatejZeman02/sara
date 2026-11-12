"""The text of a `.pot` or a `.po`, laid out as `xgettext` lays it out.

`write_pot.py` reads the tree and this file writes what it read: the
template's header and its entries, each with the places it stands and an
empty translation. `write_pseudo.py` and `write_en_us.py` write their
catalogues one field at a time through `po_field`, and `write_en_us.py`
names a message as a catalogue spells it through `escaped`.
"""

from __future__ import annotations

import datetime
from collections.abc import Iterable
from typing import Protocol

HEAD = """\
# Sara's translation template: every string the tree passes to tr(), tr_n() and
# TranslationServer.translate, and every literal that reads as a label, with the
# files and lines it stands on. Written by sara-godot/scripts/write_pot.py in the
# commit that cuts a release branch, and never edited by hand.
# Plural-Forms is English's, the source language's, and a catalogue made from it
# sets its own language's rule.
"""


class Placed(Protocol):
    """Where a string stands, `write_pot.Place`."""

    path: str
    line: int


class Held(Protocol):
    """One message of the template, `write_pot.Entry`."""

    context: str
    message: str
    plural: str
    places: set

    def first(self) -> tuple[str, int]: ...


def template(entries: Iterable[Held], version: str, now: datetime.datetime) -> str:
    """The `.pot` text, its entries in the order of the first place each stands."""
    stamp = now.strftime("%Y-%m-%d %H:%M+0000")
    head = [
        "Project-Id-Version: Sara %s\n" % version,
        "Report-Msgid-Bugs-To: \n",
        "POT-Creation-Date: %s\n" % stamp,
        "PO-Revision-Date: YEAR-MO-DA HO:MI+ZONE\n",
        "Last-Translator: FULL NAME <EMAIL@ADDRESS>\n",
        "Language-Team: LANGUAGE <LL@li.org>\n",
        "Language: \n",
        "MIME-Version: 1.0\n",
        "Content-Type: text/plain; charset=UTF-8\n",
        "Content-Transfer-Encoding: 8bit\n",
        "Plural-Forms: nplurals=2; plural=(n != 1);\n",
    ]
    out = [HEAD, 'msgid ""\nmsgstr ""\n', "".join('"%s"\n' % escaped(h) for h in head)]
    for entry in sorted(entries, key=lambda e: (e.first(), e.context, e.message)):
        out.append("\n")
        places: list[Placed] = sorted(entry.places, key=lambda p: (p.path, p.line))
        for place in places:
            out.append(f"#: {place.path}:{place.line}\n")
        if entry.context:
            out.append(po_field("msgctxt", entry.context))
        out.append(po_field("msgid", entry.message))
        if entry.plural:
            out.append(po_field("msgid_plural", entry.plural))
            out.append('msgstr[0] ""\nmsgstr[1] ""\n')
        else:
            out.append('msgstr ""\n')
    return "".join(out)


def escaped(text: str) -> str:
    """*text* as it stands between a catalogue's quotes."""
    out = text.replace("\\", "\\\\").replace('"', '\\"')
    return out.replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r")


def po_field(keyword: str, text: str) -> str:
    """One keyword and its string, split after each line end the way `xgettext` writes it."""
    lines = text.split("\n")
    parts = [line + "\n" for line in lines[:-1]] + ([lines[-1]] if lines[-1] else [])
    if len(parts) <= 1:
        return '%s "%s"\n' % (keyword, escaped(text))
    return '%s ""\n' % keyword + "".join('"%s"\n' % escaped(p) for p in parts)
