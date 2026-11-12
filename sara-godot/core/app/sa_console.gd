## Terminal output formatting: colours, headings, tables and the boot banner.
##
## Everything the application prints at startup goes through here, so the format
## lives in one place instead of being spelled out at every call site. Output is
## written once and never redrawn - there is no cursor movement and no overdraw,
## so the transcript stays readable when piped, scrolled back, or read out of
## user://logs/godot.log.
##
## Colours are emitted as BBCode through print_rich(), which Godot turns into
## truecolor ANSI for a terminal, renders natively in the editor's Output panel,
## and strips entirely from the log file. That last part matters: the log stays
## plain text, so scripts/check_lsp_errors.py and the godot-console skill keep
## parsing it unchanged. **Nothing here may ever emit raw ANSI**, which would go
## into the log verbatim and break both readers.
##
## **Two modes.** Human is the default and is what a person reads: the mark,
## the boxes, the columns and the colour. Machine is asked for by
## `SARA_CONSOLE=machine` or by `--machine-console` after the `--`, and is what
## a script reads: no logo, no box drawing, no padding, no colour, and one fact
## per line as tab separated fields whose first is the kind of line it is.
##
## Both modes print the same facts. That is the rule the two are built to,
## because a mode that hides something is a mode that gets debugged twice. The
## one asymmetry is deliberate and goes the other way: the human mode truncates
## a long kernel list to fit its column and the machine mode prints all of it.
class_name SaConsole
extends RefCounted

# --- Palette ------------------------------------------------------------------
# Warm orange is the app's accent. The rest is chosen to stay legible on both
# light and dark terminals, which is why nothing here is pure black or white.

const BRAND := "#ff8c42"
const OK := "#7ec86a"
const WARN := "#ffcc55"
const ERR := "#ff5f56"
const SKIP := "#8a7fd0"
const INFO := "#5fd3f3"
const HEAD := "#cfd6e0"
const DIM := "#6f7885"

const RULE_WIDTH: int = 66
const LABEL_WIDTH: int = 12

## How wide a `row` pads its name, and how long a detail may be before the
## human mode cuts it. The machine mode does neither.
const ROW_WIDTH: int = 18
const DETAIL_MAX: int = 44

## The kind of line, first field of every machine mode line.
const KIND_BANNER := "sara"
const KIND_SECTION := "section"
const KIND_FIELD := "field"
const KIND_ITEM := "item"
const KIND_ROW := "row"
const KIND_NOTICE := "notice"
const KIND_READY := "ready"

## What each status glyph is called when there is no terminal to draw it on.
const GLYPH_WORDS := {"✓": "ok", "✗": "fail", "·": "skip", "●": "ok", "▲": "warn"}

## The BBCode this file emits, and nothing else, so a detail carrying a square
## bracket of its own survives being made plain.
const _TAG_PATTERN := "\\[/?(?:b|color(?:=[^\\]]*)?)\\]"

## Cached, because every line asks and neither the environment nor the user
## arguments change while the process runs. -1 is "not asked yet".
## Test seam. Pass -1 to go back to asking the environment.
static var machine: int = -1

static var _tags: RegEx = null


## Wraps `text` in a colour.
static func tint(text: String, colour: String) -> String:
    return "[color=%s]%s[/color]" % [colour, text]


static func bold(text: String, colour: String = HEAD) -> String:
    return "[b]%s[/b]" % tint(text, colour)


## A section heading with an optional right-aligned summary.
static func section(title: String, summary: String = "") -> void:
    if wants_machine():
        machine_line(KIND_SECTION, [title, summary])
        return
    var line := "  " + bold(title)
    if summary != "":
        var pad: int = maxi(1, RULE_WIDTH - title.length() - summary.length() - 2)
        line += " ".repeat(pad) + tint(summary, DIM)
    print_rich(line)


## A dim label with a value, aligned into a column.
static func field(label: String, value: String) -> void:
    if wants_machine():
        machine_line(KIND_FIELD, [label, value])
        return
    print_rich("    %s  %s" % [tint(label.rpad(LABEL_WIDTH), DIM), value])


## A status line: a coloured glyph, a name, and trailing detail.
##
## The glyph is what a person reads and a word is what a script reads, so the
## machine mode prints the word [constant GLYPH_WORDS] maps it to rather than a
## character whose colour carried half its meaning.
static func item(
    glyph: String, glyph_colour: String, name: String, detail: String = "", width: int = 26, name_colour: String = HEAD
) -> void:
    if wants_machine():
        machine_line(KIND_ITEM, [GLYPH_WORDS.get(glyph, glyph), name, detail])
        return
    var line := "    %s %s" % [tint(glyph, glyph_colour), tint(name.rpad(width), name_colour)]
    if detail != "":
        line += " " + tint(detail, DIM)
    print_rich(line)


## A name, a count and the detail behind it: what the shader report draws for
## every file and the module report for every skipped folder.
##
## Here rather than at the two call sites because a mode switch that two files
## can forget about is a mode switch that prints in two shapes. The human column
## cuts a long detail to fit, the machine one never does, which is the only
## place the two modes differ and it differs towards the machine.
static func row(name: String, count: String, detail: String, name_colour: String = HEAD) -> void:
    if wants_machine():
        machine_line(KIND_ROW, [name, count, detail])
        return
    var shown := detail
    if shown.length() > DETAIL_MAX:
        shown = shown.substr(0, DETAIL_MAX - 1) + "…"
    print_rich(
        (
            "    %s %s  %s"
            % [
                tint(name.rpad(ROW_WIDTH), name_colour),
                tint(count.lpad(2), BRAND if name_colour == HEAD else DIM),
                tint(shown, DIM)
            ]
        )
    )


static func blank() -> void:
    if wants_machine():
        return
    print_rich("")


static func rule() -> void:
    if wants_machine():
        return
    print_rich(tint("  " + "─".repeat(RULE_WIDTH), DIM))


## Boxed title bar, padded so a matching close_box() lines up exactly.
static func open_box(title: String, colour: String = BRAND) -> void:
    if wants_machine():
        machine_line(KIND_SECTION, [title])
        return
    var lead := "╭─ "
    var used: int = lead.length() + title.length() + 1
    print_rich(tint("  " + lead, DIM) + bold(title, colour) + " " + tint("─".repeat(maxi(0, RULE_WIDTH - used)) + "╮", DIM))


static func close_box() -> void:
    if wants_machine():
        return
    print_rich(tint("  ╰" + "─".repeat(RULE_WIDTH - 1) + "╯", DIM))


static func divider() -> void:
    if wants_machine():
        return
    print_rich(tint("  ├" + "─".repeat(RULE_WIDTH - 1) + "┤", DIM))


## A headless run has no terminal to draw a picture on, and its output usually
## ends up in a log or a CI transcript where ten rows of half-blocks are noise.
static func wants_banner() -> bool:
    if wants_machine():
        return false
    if DisplayServer.get_name() == "headless":
        return false
    return not OS.get_cmdline_user_args().has("--no-banner")


## Whether the console prints for a script rather than for a person.
##
## Two ways in because there are two kinds of caller: a script starting Sara
## through a wrapper sets the environment variable, and a person trying the mode
## once passes the argument. Not tied to a headless run, which is a different
## question: a headless run has no terminal to draw a logo on and is still read
## by a person most of the time.
static func wants_machine() -> bool:
    if machine == -1:
        var asked := OS.get_environment("SARA_CONSOLE") == "machine"
        machine = 1 if asked or OS.get_cmdline_user_args().has("--machine-console") else 0
    return machine == 1


## One machine mode line: the kind, then a field each, tab separated, with the
## colour taken out. Empty trailing fields are dropped rather than printed as
## empty columns, so a line has as many fields as it has facts.
##
## Built and printed separately so a test can read the shape without capturing
## stdout, which GDScript has no way to do.
static func machine_text(kind: String, fields: Array) -> String:
    var parts := PackedStringArray([kind])
    for field_text: Variant in fields:
        parts.append(plain(str(field_text)).strip_edges())
    while parts.size() > 1 and parts[parts.size() - 1] == "":
        parts.remove_at(parts.size() - 1)
    return "\t".join(parts)


static func machine_line(kind: String, fields: Array) -> void:
    print(machine_text(kind, fields))


## `text` with this file's own BBCode taken out, for a surface that cannot
## render it. `print_rich` would strip it too, but the machine mode uses
## `print`, so the stripping has to happen here.
static func plain(text: String) -> String:
    if _tags == null:
        _tags = RegEx.create_from_string(_TAG_PATTERN)
    return _tags.sub(text, "", true)


## The mark plus build information, with the text set beside the logo rather
## than under it so the whole header stays about ten rows.
static func banner(version: String, extra: Array[String] = []) -> void:
    if wants_machine():
        machine_line(KIND_BANNER, [version, "GPU-first digital painting", "GPLv3", "Godot " + _godot_version()])
        for line: String in extra:
            machine_line(KIND_FIELD, ["Banner", line])
        return
    if not wants_banner():
        print_rich("  %s %s %s" % [bold("SARA", BRAND), tint(version, HEAD), tint("· GPU-first digital painting", DIM)])
        return

    # Captions sit beside the mark, vertically centred against it, so the header
    # stays as tall as the logo rather than the logo plus a text block.
    var captions: Array[String] = [
        "",
        "",
        "",
        "",
        "",
        "",
        bold("SARA", BRAND) + tint("   " + version, HEAD),
        "",
        tint("GPU-first digital painting", DIM),
        "",
        tint("GPLv3  ·  Godot " + _godot_version(), DIM),
    ]
    captions.append_array(extra)

    blank()
    var mark := SaLogo.lines()
    for i in mark.size():
        var caption: String = captions[i] if i < captions.size() else ""
        print_rich("  " + mark[i] + ("   " + caption if caption != "" else ""))
    blank()


## "4.7-stable (official) 5b4e0cb0f" - the short build hash is kept because the
## engine header carried it and we suppress that header. It is the one detail
## that actually matters when reporting an engine bug.
static func _godot_version() -> String:
    var info := Engine.get_version_info()
    var text := "%s.%s-%s" % [info.get("major", 0), info.get("minor", 0), info.get("status", "")]

    # "(official)" is the common case and says nothing. A custom or mono build is
    # worth flagging, so only that gets named. Dropping it also keeps the widest
    # banner line inside 80 columns, which the 32-column mark had pushed past.
    var build := str(info.get("build", "official"))
    if build != "official":
        text += " (%s)" % build

    var build_hash := str(info.get("hash", ""))
    if build_hash.length() >= 9:
        text += "  " + build_hash.substr(0, 9)
    return text


## Final "everything is up" line. The figure is milliseconds since the engine
## started, `SaBootMarks.ready_line_ms()`.
static func ready(milliseconds: int, note: String = "") -> void:
    if wants_machine():
        machine_line(KIND_READY, [str(milliseconds), note])
        return
    print_rich(ready_text(milliseconds, note))


## The human ready line, built apart from its printing for the same reason
## `machine_text` is, so a suite can read the figure it carries.
static func ready_text(milliseconds: int, note: String = "") -> String:
    var line := "  %s %s" % [tint("●", OK), tint("Ready in %d ms" % milliseconds, HEAD)]
    if note != "":
        line += "   " + tint(note, DIM)
    return line


static func notice(text: String) -> void:
    if wants_machine():
        machine_line(KIND_NOTICE, [text])
        return
    print_rich("  %s %s" % [tint("▲", WARN), tint(text, DIM)])
