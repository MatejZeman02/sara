"""The paintings open in Sara beside the one a notebook is working on, and which is in front.

    import sara
    doc, layer, a = sara.init()        # a new document, in front of whatever else is open
    doc.documents()                    # every open painting, in tab order, the front one marked
    doc.front("study.sad")             # brings that one forward, the way a click on its tab does

`sara.py`'s `Document.documents` and `Document.front` are these two calls, kept
in a file of their own because `sara.py` is near the thousand lines a file is
allowed. They speak the door's `documents` and `front` steps, which
`ui/document_tabs/sa_document_tabs.gd` answers.

Every other step acts on the document in front, `init()` included, so these two
are what a notebook reaches a second painting through: bring it forward, do the
work, bring the first back. Nothing outside the standard library but `sara`
itself, for its door and its error, the way `sara_array.py` imports it.
"""

from __future__ import annotations

import sara


def documents(door: sara.Door) -> list[dict]:
    """The open paintings through *door*, in tab order, one dict each: `at` its place counted from 0,
    `name` the file's name or `Untitled` for one never saved, `id` its surface's id as the state dump
    spells it, `modified` whether it has unsaved changes, and `front` for the one every other step acts on."""
    said = door.verdict({"documents": True})
    if not isinstance(said, list):
        raise sara.SaraError(f"{sara.VERDICT}documents {said}")
    return said


def front(door: sara.Door, name: str) -> dict:
    """Brings the open painting called *name* forward through *door*, the way a click on its tab does,
    and answers its `name` and `id`. The name is the one `documents` answers, and a surface id such as
    `document_2` names one of two untitled paintings. A name no open painting carries, or one that two
    share, raises rather than moving the front."""
    if not isinstance(name, str) or not name:
        raise sara.SaraError(f"a painting is brought forward by its name, not {name!r}")
    said = door.verdict({"front": name})
    if not isinstance(said, dict) or "id" not in said:
        raise sara.SaraError(f"{sara.VERDICT}front {said}")
    return said
