"""A relative file the caller wrote, named in a step, made absolute in the caller's folder.

Sara reads a relative name from the run's folder, because the door is another process and never
knows where its caller stands. The client does know, so `sara.py` sends every step through
`absolute_files` and Sara gets the path of the file the caller just wrote beside its own script
or notebook: the `file` of a `write_pixels` step and the `mask` of a `select` step.
`CALLER_FILES` is the one list of which step carries such a file under which key.
A name already absolute goes as it was, and the caller's own dictionaries are left as they were.
"""

from __future__ import annotations

import os

CALLER_FILES = {"write_pixels": "file", "select": "mask"}


def absolute_files(steps: list[dict], folder: str | None = None) -> list[dict]:
    """*steps* with each relative file a caller wrote joined to *folder*, the current one by default."""
    where = folder if folder is not None else os.getcwd()
    return [_absolute(step, where) for step in steps]


def _absolute(step: dict, folder: str) -> dict:
    for kind, key in CALLER_FILES.items():
        spec = step.get(kind)
        if not isinstance(spec, dict):
            continue
        name = spec.get(key)
        if not isinstance(name, str) or not name or os.path.isabs(name):
            continue
        step = dict(step, **{kind: dict(spec, **{key: os.path.abspath(os.path.join(folder, name))})})
    return step
