#!/usr/bin/env python3
"""The step catalogue, read out of the executor rather than written by hand.

`SaStepTable.run` is a chain of `step.has("<key>")` branches, each dispatching
to a handler in one of eleven files. This parses that chain in order and
reports, per key, the argument the dispatch line casts to, the file and
function it dispatches to, and the handler's own `##` doc comment.

Nothing is copied into a table here, so a step kind another group adds appears
in the catalogue the moment it is added, and a key whose handler has no doc
comment is listed as undocumented with its source location rather than omitted
or guessed at.

    scripts/sara_steps.py            # every key, one line each
    scripts/sara_steps.py --json     # the same as JSON, for a program to read
    scripts/sara_steps.py zoom shot  # only these keys, with their docs
    scripts/sara_steps.py --check    # exit 1 when any key is undocumented or its line is wrong
    scripts/sara_steps.py --page     # write the steps page, docs/guides/DOOR-STEPS.md of a checkout that has docs/
    scripts/sara_steps.py --page --check  # exit 1 when that page is stale
    scripts/sara_steps.py --page --out FILE  # write (or check) the page at FILE, which a copy with no docs/ needs

The JSON is over a hundred thousand characters, which is more than a small
model reads before it paints. The page is the short form, one line a step kind,
generated here so it cannot drift from the table.

The JSON is also what the door reads `{"steps": true}` out of. An exported
build carries no doc comments, so `packaging/build.sh` packs `--json` into the
build as `step_catalogue.json`, and the door in a checkout runs this script
instead. The door does not answer the whole of it: each kind's `brief`, the
line cut here from its doc, and the schema of the kinds flagged `start` fit a
small model's context, and one kind's whole doc is a request of its own.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path, PurePath

PROJECT_DIR = Path(__file__).resolve().parent.parent
EXECUTOR = PROJECT_DIR / "harness" / "sa_step_table.gd"
PAGE = PROJECT_DIR.parent / "docs" / "guides" / "DOOR-STEPS.md"
## The end of a doc comment's first sentence: a full stop before a space, where
## what follows starts a new sentence rather than continuing an abbreviation.
SENTENCE_END_RE = re.compile(r"(?<=[.!?])\s+(?=[A-Z`*(\[])")

## `if step.has("zoom"):` and `elif step.has("zoom"):`, which is the whole chain.
BRANCH_RE = re.compile(r'^\s*(?:el)?if step\.has\("([a-z_0-9]+)"\)')
## What the dispatch line does with the value, in the order the executor writes
## it. A step's argument is whatever the cast on its own line says it is.
CAST_PATTERNS: list[tuple[str, re.Pattern]] = [
    ("Dictionary", re.compile(r'step\["[a-z_0-9]+"\] as Dictionary')),
    ("Array", re.compile(r'step\["[a-z_0-9]+"\] as Array')),
    ("String", re.compile(r'String\(step\["[a-z_0-9]+"\]\)')),
    ("int", re.compile(r'int\(step\["[a-z_0-9]+"\]\)')),
    ("float", re.compile(r'float\(step\["[a-z_0-9]+"\]\)')),
]
## `_menus.open_menu(...)`, `_run.shoot(...)`, `_stroke.stroke(...)`.
CALL_RE = re.compile(r"(?:print\()?\s*([A-Za-z_][A-Za-z_0-9]*(?:\.[A-Za-z_][A-Za-z_0-9]*)*)\(")
## The calls that only write out what they are handed, so the handler to read
## is the one inside them. Two kinds wrap their dispatch in
## `SaDoorVerdicts.say` rather than `print`, because a `layers` line of the
## 540-layer file is 116 kB and belongs in the door's answer and not in the
## log, and the kind they document is still the one that made the line.
PRINTERS = ("print", "SaDoorVerdicts.say")
## `const InputDriver := preload("res://harness/drivers/sa_input_driver.gd")`.
PRELOAD_RE = re.compile(r'^const\s+([A-Za-z_0-9]+)\s*:?=\s*preload\("(res://[^"]+)"\)')
## `var _input: InputDriver = null`, so a dispatch through one of the table's
## own drivers can be followed to the file its type preloads. Every handler is
## an instance method, so without this the catalogue reports sixty step kinds
## as having no handler at all.
MEMBER_RE = re.compile(r"^var\s+(_[A-Za-z_0-9]+)\s*:\s*([A-Za-z_0-9]+)")
## `class_name SaLayoutPage`, so a dispatch through a global class can be
## followed to the file that declares it. Guessing the path from the name was
## the first draft and it was wrong for every class in a subdirectory, which is
## most of them: the handler was found and its doc comment was not.
CLASS_RE = re.compile(r"^class_name\s+([A-Za-z_0-9]+)")

## The kinds a painting needs first. The door answers each of them with its
## line and the schema its `Arguments` paragraph gives, and every other kind
## with its name and its line, which is what keeps the first answer inside a
## small model's context. A flag on each kind of the JSON, so
## the door, the copy a build packs and the page read this one list.
START = ("path", "stroke", "colour", "layer", "tool", "shot", "state", "undo", "message", "save", "look", "quit")
## The kinds the door answers itself, which `DOOR_KINDS` in
## `harness/door/sa_door_catalogue.gd` describes since the table has no branch
## for them.
DOOR_ONLY = ("quit",)
## The longest line a kind is listed by. An agent chooses a kind by it, and 152
## lines of 40 are what leave room under the door's budget for the start kinds'
## schemas.
LINE_MAX = 40
## Where a line ends inside the first sentence: the job comes first by the
## catalogue's rule, and a colon or a backtick is where its example begins.
LINE_END_RE = re.compile(r"[:`]")
## The words a clause cannot end on, since each wants something after it. A
## line that ends on one was cut in the middle of its job.
DANGLING = frozenset(
    "a an the of to with by for in on at from into onto over under as and or but nor its their his her "
    "that which whose whom who where when while than then so if is are be was were has have had one each "
    "every this these those any some no not either both through via per like named called".split()
)
## The words ending in an s that are not a verb a line can open on. A line opens
## on what the step does, `Zooms` or `Fills`, which the catalogue's own rule
## asks and a noun phrase such as "The step" breaks.
NOT_VERBS = frozenset("this its his hers ours yours theirs is was as thus less yes us".split())
## The paragraph that types the keys of a kind's argument, its first line this
## and then a line a key: `- `from` array, where the stroke starts.`
ARGUMENTS_HEAD = "**Arguments.**"
JSON_TYPE_WORDS = ("object", "array", "string", "integer", "number", "boolean")
ARGUMENT_RE = re.compile(
    r"^- `([a-z_0-9]+)` ((?:%s)(?: or (?:%s))*), (.+)$" % ("|".join(JSON_TYPE_WORDS), "|".join(JSON_TYPE_WORDS))
)


def executor_source() -> str:
    return EXECUTOR.read_text(encoding="utf-8")


_CLASS_FILES: dict[str, str] | None = None


def res_path_of(path: PurePath, project: PurePath = PROJECT_DIR) -> str:
    """The `res://` path of *path*, with forward slashes whatever the platform.

    `str()` of a path on Windows joins its parts with backslashes, so a page
    generated there named the file behind a class as `harness\\drivers\\...` and
    `--page --check` would refuse a tree that is up to date.
    """
    return "res://" + path.relative_to(project).as_posix()


def class_files() -> dict[str, str]:
    """Every `class_name` in the project, and the file that declares it."""
    global _CLASS_FILES
    if _CLASS_FILES is not None:
        return _CLASS_FILES
    found: dict[str, str] = {}
    for path in PROJECT_DIR.rglob("*.gd"):
        if any(part in (".godot", "scratch", "build") for part in path.parts):
            continue
        try:
            head = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for line in head.splitlines():
            declared = CLASS_RE.match(line)
            if declared:
                found[declared.group(1)] = res_path_of(path)
                break
    _CLASS_FILES = found
    return found


def preloads(source: str) -> dict[str, str]:
    """Const or member name -> the file behind it, so a dispatch can be followed."""
    out: dict[str, str] = {}
    for line in source.splitlines():
        found = PRELOAD_RE.match(line)
        if found:
            out[found.group(1)] = found.group(2)
    for line in source.splitlines():
        member = MEMBER_RE.match(line)
        if member and member.group(2) in out:
            out[member.group(1)] = out[member.group(2)]
    return out


def catalogue() -> list[dict]:
    """Every step key `SaStepTable.run` answers to, in the order it tries them."""
    source = executor_source()
    const_files = preloads(source)
    lines = source.splitlines()
    out: list[dict] = []
    for i, line in enumerate(lines):
        branch = BRANCH_RE.match(line)
        if not branch:
            continue
        key = branch.group(1)
        # The dispatch is the next non-empty line, or several when the call was
        # wrapped by the formatter at the 130-column limit.
        body = _body_after(lines, i)
        entry = {
            "step": key,
            "argument": _argument_of(body),
            "dispatch": body.strip(),
            "line": i + 1,
            **_handler_of(body, const_files, key),
        }
        # The page lists each kind by this sentence, and it is cut here so the
        # rule for a sentence has one home.
        entry["summary"] = first_sentence(entry["doc"])
        entry["brief"] = line_of(entry["doc"])
        entry["start"] = key in START
        entry["inputSchema"] = input_schema(key, entry["argument"], arguments_of(entry["doc"]))
        out.append(entry)
    return out


## The JSON type each cast of the table reads, for an MCP tool's schema. A
## kind whose value is read as it comes, `any`, gets no type at all.
JSON_TYPES = {"Dictionary": "object", "Array": "array", "String": "string", "int": "integer", "float": "number"}


def input_schema(key: str, argument: str, arguments: dict[str, tuple[list[str], str]] | None = None) -> dict:
    """The `inputSchema` of an MCP tool for one step kind.

    A step is an object with the kind as its key, so the schema is an object
    that requires that key and types its value by the table's cast. The door
    answers its catalogue in the fields of an MCP tool, `name`, `description`
    and this, so an agent that has read a tool list reads the catalogue
    without a manual, and it checks a step's argument against this type.

    *arguments* is the kind's `Arguments` paragraph read by `arguments_of`. A
    line naming the kind's own key describes its value, and every other line is
    a key of the value, typed and described under `properties`. The value's own
    type stays the cast's, since that is the type the door refuses a step by,
    and a value the table reads as it comes, `colour`'s string or array, says
    its types in its words instead.
    """
    value: dict = {"type": JSON_TYPES[argument]} if argument in JSON_TYPES else {}
    for name, (types, words) in (arguments or {}).items():
        if name == key:
            value["description"] = words if "type" in value else "%s, %s" % (" or ".join(types), words)
            continue
        value.setdefault("properties", {})[name] = {"type": types[0] if len(types) == 1 else types, "description": words}
    return {"type": "object", "properties": {key: value}, "required": [key]}


def arguments_of(doc: str) -> dict[str, tuple[list[str], str]]:
    """The `Arguments` paragraph of a doc comment, by key: its JSON types and words.

    A line of the paragraph that does not open on `- ` continues the one before
    it, so a key whose words wrap still reads as one.
    """
    for paragraph in doc.split("\n\n"):
        lines = paragraph.strip().splitlines()
        if not lines or lines[0].strip() != ARGUMENTS_HEAD:
            continue
        joined: list[str] = []
        for line in lines[1:]:
            text = line.strip()
            if text.startswith("- ") or not joined:
                joined.append(text)
            else:
                joined[-1] += " " + text
        out: dict[str, tuple[list[str], str]] = {}
        for text in joined:
            found = ARGUMENT_RE.match(text)
            if found:
                out[found.group(1)] = (found.group(2).split(" or "), found.group(3).rstrip("."))
        return out
    return {}


def _body_after(lines: list[str], index: int) -> str:
    """The dispatch under a branch, joined when the formatter wrapped it.

    Comment lines are skipped rather than taken as the body: a branch may carry
    two lines of why before the call, and the first draft of this read those as
    the dispatch and reported three step kinds as having no handler.
    """
    body: list[str] = []
    for line in lines[index + 1 :]:
        if BRANCH_RE.match(line) or line.strip() == "else:":
            break
        text = line.strip()
        if not text or text.startswith("#"):
            continue
        body.append(text)
        if line.count("(") <= line.count(")"):
            break
    return " ".join(body)


def _argument_of(body: str) -> str:
    for name, pattern in CAST_PATTERNS:
        if pattern.search(body):
            return name
    return "any"


def _handler_of(body: str, const_files: dict[str, str], key: str) -> dict:
    """The file and function a dispatch lands in, and its doc comment.

    A branch that assigns rather than calls, which `wait` is and is the only
    one, has no handler to document and says so with the executor as its file.
    """
    call = CALL_RE.search(body)
    if call is None or call.group(1) in ("int", "float", "String", "bool"):
        # An assignment with no call of its own, which `wait` is and is the
        # only one: nothing to document, and the executor is where to read.
        return {"handler": "", "file": "harness/sa_step_table.gd", "doc": "", "documented": False}
    target = call.group(1)
    if target in PRINTERS:
        rest = CALL_RE.search(body[call.end() :])
        target = rest.group(1) if rest else target
    if "." in target:
        holder, func = target.rsplit(".", 1)
        # A preloaded const, or a global class, or neither.
        path = const_files.get(holder, "") or class_files().get(holder, "")
    else:
        # A bare call is a function of the table's own. There is none today,
        # and the fallback names the table's own file rather than guessing.
        holder, func, path = "", target, "res://harness/sa_step_table.gd"
    doc = _doc_for(path, func)
    return {
        "handler": ("%s.%s" % (holder, func)) if holder else func,
        "file": path.replace("res://", ""),
        "doc": doc,
        "documented": bool(doc),
    }


def _doc_for(res_path: str, func: str) -> str:
    """The `##` block directly above a function, as one paragraph."""
    path = PROJECT_DIR / res_path.replace("res://", "")
    if not path.is_file():
        return ""
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    pattern = re.compile(r"^\s*(?:static\s+)?func\s+%s\s*\(" % re.escape(func))
    for i, line in enumerate(lines):
        if not pattern.match(line):
            continue
        doc: list[str] = []
        for above in range(i - 1, -1, -1):
            text = lines[above].strip()
            if text.startswith("##"):
                doc.insert(0, text.lstrip("#").strip())
                continue
            if text.startswith("#") or not text:
                if doc:
                    break
                continue
            break
        return "\n".join(doc).strip()
    return ""


def first_sentence(doc: str) -> str:
    """The first sentence of a doc comment, on one line."""
    text = " ".join(doc.split("\n\n", 1)[0].split())
    return SENTENCE_END_RE.split(text, 1)[0] if text else ""


def line_of(doc: str) -> str:
    """The line a kind is listed by: its first sentence up to a colon or a backtick.

    The catalogue's rule puts the job first and the example after it in the same
    sentence, so the cut keeps the job and leaves the example to the kind's
    whole doc. Read off the doc rather than kept in a table, so a kind cannot be
    added without its words.
    """
    sentence = first_sentence(doc)
    cut = LINE_END_RE.search(sentence)
    return (sentence[: cut.start()] if cut else sentence).rstrip(" ,;.")


def clause_problem(line: str) -> str:
    """Why *line* does not stand as a clause, or "" when it does.

    A clause here opens on a capital letter, ends on a word that wants nothing
    after it, and leaves no bracket open. That is what a cut in the middle of a
    sentence breaks, which is the failure a line too short for its job has.
    """
    if not line:
        return "is empty"
    if not line[0].isupper():
        return "opens on %r rather than a capital letter" % line[0]
    words = line.split()
    if len(words) < 2:
        return "is one word"
    first = words[0].strip(",").lower()
    if not first.endswith("s") or first in NOT_VERBS:
        return "opens on %r, not a verb saying what the step does" % words[0]
    last = words[-1].strip("*_").lower()
    if last in DANGLING:
        return "ends on %r, which wants something after it" % words[-1]
    for opening, closing in ("()", "[]"):
        if line.count(opening) != line.count(closing):
            return "leaves a %s open" % opening
    if line.count("*") % 2:
        return "leaves an emphasis open"
    return ""


def line_problems(entries: list[dict], start: tuple[str, ...] | None = None) -> list[str]:
    """Every way the lines and the start kinds' arguments of *entries* fail.

    A line over `LINE_MAX` or not a clause, two kinds of one line, a start kind
    the table has not got, and a start kind whose doc carries no `Arguments`
    paragraph. A kind the table tries twice is judged by its last branch, the
    one the door describes it by.
    """
    start = START if start is None else start
    last = {entry["step"]: entry for entry in entries}
    problems: list[str] = []
    by_line: dict[str, list[str]] = {}
    for key, entry in last.items():
        line = line_of(entry["doc"])
        if len(line) > LINE_MAX:
            problems.append("`%s`'s line is %d characters, over %d: %s" % (key, len(line), LINE_MAX, line))
        why = clause_problem(line)
        if why:
            problems.append("`%s`'s line %s: %s" % (key, why, line))
        by_line.setdefault(line, []).append(key)
    for line, keys in by_line.items():
        if len(keys) > 1:
            problems.append("%s share one line: %s" % (" and ".join("`%s`" % key for key in keys), line))
    for key in start:
        if key in DOOR_ONLY:
            continue
        if key not in last:
            problems.append("start kind `%s` is not in the table" % key)
        elif not arguments_of(last[key]["doc"]):
            problems.append("start kind `%s` has no %s paragraph in its doc" % (key, ARGUMENTS_HEAD))
    return problems


def _group_of(entry: dict) -> str:
    """The driver a step kind is grouped under on the page.

    A dispatch through one of the table's own members is grouped by that
    member's file, which is a driver. A dispatch through a global class is
    grouped by the folder the class lives in, so the page has one heading per
    part of the app rather than one per file.
    """
    handler = entry["handler"]
    path = entry["file"]
    if ("." in handler and handler.startswith("_")) or path == "harness/sa_step_table.gd":
        return path
    return path.rsplit("/", 1)[0] + "/"


def _named(keys: tuple[str, ...]) -> str:
    """*keys* in backticks as a list in prose, the last after an `and`."""
    quoted = ["`%s`" % key for key in keys]
    return ", ".join(quoted[:-1]) + " and " + quoted[-1] if len(quoted) > 1 else "".join(quoted)


def page_text(entries: list[dict] | None = None) -> str:
    """DOOR-STEPS.md as the table would write it now."""
    entries = catalogue() if entries is None else entries
    # A key the chain tries twice, as `import` is for an `.ora` before every
    # other file, is one line on the page: the last branch, which is the one
    # with no condition, and the line of the earlier one to read.
    last: dict[str, dict] = {}
    earlier: dict[str, list[int]] = {}
    for entry in entries:
        if entry["step"] in last:
            earlier.setdefault(entry["step"], []).append(last[entry["step"]]["line"])
        last[entry["step"]] = entry
    groups: dict[str, list[dict]] = {}
    for entry in last.values():
        groups.setdefault(_group_of(entry), []).append(entry)
    out = [
        "# The step kinds",
        "",
        "Generated by `sara-godot/scripts/sara_steps.py --page` from",
        "`sara-godot/harness/sa_step_table.gd`, so do not edit it by hand.",
        "`sara_steps.py <key>` prints a step kind's whole doc comment, and",
        "[DOOR.md](DOOR.md) says how a step reaches Sara.",
        "",
        "**Start here.** The door answers `{\"steps\": true}` with the kinds a",
        "painting needs first whole, each with its line and the keys of its",
        "argument, and every other kind by its line alone: %s." % _named(START),
        "`POST /step` takes an array of steps and answers an array of answers,",
        "and `{\"steps\": \"<name>\"}` gives one kind whole.",
        "",
        "%d step kinds. Each line is the key, the type the table casts its" % len(last),
        "argument to, where `any` means it is read as it comes, and the first",
        "sentence of its handler's doc comment, whose words up to its first",
        "colon or backtick are the line the door lists it by.",
    ]
    for group in sorted(groups):
        out += ["", "## `%s`" % group, ""]
        for entry in groups[group]:
            sentence = first_sentence(entry["doc"]) or "Undocumented, read the table at line %d." % entry["line"]
            also = earlier.get(entry["step"], [])
            if also:
                sentence += " A narrower branch comes first, table line %s." % ", ".join(str(n) for n in also)
            out.append("- `%s`, %s. %s" % (entry["step"], entry["argument"], sentence))
    return "\n".join(out) + "\n"


def write_page(check: bool, page: Path = PAGE) -> int:
    """Write the page, or with `check` exit 1 when it differs from the table."""
    text = page_text()
    current = page.read_text(encoding="utf-8") if page.is_file() else ""
    if current == text:
        return 0
    if check:
        print("  %s is stale, run `python3 scripts/sara_steps.py --page`" % page.name)
        return 1
    page.write_text(text, encoding="utf-8", newline="\n")
    print("  wrote %s, %d characters" % (page.name, len(text)))
    return 0


def report_line_problems(entries: list[dict]) -> int:
    """Prints every problem `line_problems` finds, and 1 when there is one.

    Run by `--check`, and by `--page --check`, which is the line the gate runs,
    so a kind added with a line too long for the door's budget fails the gate
    rather than the next small model that asks.
    """
    problems = line_problems(entries)
    for problem in problems:
        print("  %s" % problem)
    if problems:
        print(
            "  --check: a kind's line is its doc's first sentence up to a colon or a backtick, a clause of"
            " %d characters at most, and a start kind's doc carries an %s paragraph" % (LINE_MAX, ARGUMENTS_HEAD)
        )
    return 1 if problems else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("keys", nargs="*", help="only these step keys")
    parser.add_argument("--json", action="store_true", help="print the catalogue as JSON")
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit 1 when any key has no doc comment or its line breaks the rule, naming each one",
    )
    parser.add_argument("--page", action="store_true", help="write the step kinds page, or with --check test it")
    parser.add_argument(
        "--out",
        type=Path,
        default=None,
        help="with --page, the file to write or test, where the default docs/guides/DOOR-STEPS.md has no folder",
    )
    args = parser.parse_args()

    if args.out is not None and not args.page:
        parser.error("--out goes with --page")
    if args.page:
        target = args.out if args.out is not None else PAGE
        if not target.parent.is_dir():
            print("  %s has no folder here, so a copy without docs/ names the file: --page --out FILE" % target.name)
            return 2
        written = write_page(args.check, target)
        return max(written, report_line_problems(catalogue())) if args.check else written
    entries = catalogue()
    if args.check and report_line_problems(entries):
        return 1
    if args.keys:
        entries = [entry for entry in entries if entry["step"] in args.keys]
    if args.json:
        print(json.dumps(entries, indent=2))
        return 0

    undocumented = 0
    for entry in entries:
        mark = " " if entry["documented"] else "?"
        print(f"{mark} {entry['step']:22s} {entry['argument']:10s} {entry['handler']:36s} {entry['file']}")
        if args.keys and entry["doc"]:
            for line in entry["doc"].splitlines():
                print(f"      {line}")
        undocumented += 0 if entry["documented"] else 1
    print(f"\n  {len(entries)} step kinds, {undocumented} of them with no doc comment (marked ?)")
    # `--check` is for a gate rather than for a reader, so it is the only mode
    # that can fail. Printing the count and failing on nothing is how two keys
    # reached the catalogue undocumented.
    if args.check and undocumented:
        print("  --check: every step kind needs a `##` above the handler the executor dispatches to")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
