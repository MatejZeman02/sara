## The reader of a Krita `.shortcuts` export, against the Krita action each row
## of `SaShortcutKritaTable` names. Private to the chord store's folder: Import
## from Krita asks `SaShortcutStore.import_krita`, which reads through this and
## lays what it read over the Krita profile.
##
## An export is an INI file of `action=chord` lines under one `[Shortcuts]`
## section, `none` for an unbound action. Krita's own maps, the
## `krita_default.shortcuts` it installs among them, put `; ` between
## alternatives, and the hand-written fixture under `scenarios/fixtures` a
## comma, so both read.
## Krita ships far more actions than Sara has commands, and the table holds only
## the ones with a Sara counterpart. An action the table does not name
## contributes nothing to the import, the same silence a saved profile keeps
## about a chord nobody touched.
class_name SaShortcutKritaNames
extends RefCounted

## The modifiers Krita writes that Godot reads by the same word, lowercase
## because Krita's own maps write "ctrl+alt+0" beside "Ctrl+A".
const MODIFIERS: Array[String] = ["ctrl", "shift", "alt", "meta"]


## What one read of an export found, and the profile the store saved it as.
class Reading:
    extends RefCounted

    ## Sara's command id -> the chords the file gives it, in the shape
    ## `SaShortcutStore.save_overrides` writes, before the store lays them over
    ## the Krita profile. A command Krita gave chords of which none read is not
    ## here, so it keeps the profile's rather than being cleared by a file that
    ## did name a key for it.
    var overrides: Dictionary[String, Array] = {}

    ## Sara's command id -> each chord Krita wrote for it that no key here
    ## reads, as the file spells it. What Import from Krita names.
    var unread: Dictionary[String, Array] = {}

    ## The profile the store saved this as, empty while it has not.
    var profile: String = ""

    ## One action's value, Krita's chords for *command_id* or `none`, which
    ## clears it because that is what Krita means by it. A command whose row
    ## names two of Krita's actions is taken once for each, and holds the
    ## chords of both: a `none` beside a chord that reads clears nothing.
    func take(command_id: String, raw: String) -> void:
        var written := SaShortcutKritaNames.alternatives(raw)
        var chords: Array = overrides.get(command_id, [])
        if written.is_empty() or raw == "none":
            overrides[command_id] = chords
            return
        var read := 0
        for chord: String in written:
            var event := SaShortcutStore.parse_chord(SaShortcutKritaNames.sara_spelling(chord))
            if event != null:
                chords.append(SaShortcutStore.chord_text(event))
                read += 1
            elif unread.has(command_id):
                unread[command_id].append(chord)
            else:
                unread[command_id] = [chord]
        if read > 0:
            overrides[command_id] = chords

    ## The profile's *chord* for one of *command_id*'s actions the file left
    ## out, in Sara's spelling already, beside what the file gave the others.
    func keep(command_id: String, chord: String) -> void:
        var chords: Array = overrides.get(command_id, [])
        chords.append(chord)
        overrides[command_id] = chords


## Reads a Krita `.shortcuts` export. An empty reading when the file will not
## open, which is also what an importer asked for a file that is not one gets.
##
## Read line by line rather than through `ConfigFile`: Krita's own file is an
## INI Godot's parser refuses, `action=none` is a bareword value with no
## quotes and no type `_parse` in `core/io/config_file.cpp` accepts, so
## `ConfigFile.load()` fails on the first such line, which in a real export
## is the second line of the file.
static func parse(path: String) -> Reading:
    var reading := Reading.new()
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return reading
    var written: Dictionary[String, String] = {}
    var in_section := false
    while not file.eof_reached():
        var line := file.get_line().strip_edges()
        if line.is_empty() or line.begins_with(";") or line.begins_with("#"):
            continue
        if line.begins_with("["):
            in_section = line == "[Shortcuts]"
            continue
        var split := line.find("=")
        if in_section and split > 0:
            written[line.substr(0, split)] = _unescaped(line.substr(split + 1).strip_edges())
    # In the table's order rather than the file's, so Save's two actions give
    # their chords in the order the profile lists them whichever the file wrote
    # first. An action the file leaves out beside one it names keeps the
    # profile's chord for it: Krita's Save Custom Shortcuts writes only what a
    # painter changed, and a file holding `save_incremental_version=none` alone
    # took Ctrl+S off Save while that painter's Krita still saved on it.
    for command: String in SaShortcutKritaTable.ACTIONS:
        var actions := SaShortcutKritaTable.actions_of(command)
        if not actions.any(func(action: String) -> bool: return written.has(action) and _moves(command, written[action])):
            continue
        var profile := SaShortcutStore.entry_chords(SaShortcutKritaTable.CHORDS.get(command, ""))
        for at: int in actions.size():
            if written.has(actions[at]):
                reading.take(command, written[actions[at]])
            elif at < profile.size():
                reading.keep(command, profile[at])
    return reading


## Whether *value*, what a file wrote for one of *command*'s actions, moves the
## command off the Krita profile. A `none` on an action Krita ships with no
## chord does not: it is Krita's stock, which the profile answers by leaving
## Sara's own chord, and Krita's Export Scheme writes it for every such action,
## so an export of an untouched Krita took Ctrl+, off Preferences.
static func _moves(command: String, value: String) -> bool:
    if SaShortcutKritaTable.CHORDS.has(command):
        return true
    return value != "none" and not alternatives(value).is_empty()


## The chords one value holds, `Ctrl+=; Ctrl++` as Krita writes it or
## `Ctrl+=,Ctrl++` as the fixture under `scenarios/fixtures` does.
##
## Parted on `; ` first, exactly as Qt's `QKeySequence::listFromString` parts
## what its `listToString` joined. So `Ctrl+Shift+;; Ctrl+3` is two chords and
## `; `, which is what Krita writes for an action holding two empty ones, is
## none. A comma parts two chords only where a key cannot stand: at the start
## of a chord or after a "+" it is the key, so Krita's "," for the next
## favourite preset and its "Ctrl+," stay one chord each.
static func alternatives(raw: String) -> Array[String]:
    var pieces: Array[String] = []
    for sequence: String in raw.split("; "):
        var key_due := true
        pieces.append("")
        for at: int in sequence.length():
            var c := sequence[at]
            if c == "," and not key_due:
                pieces.append("")
                key_due = true
            else:
                pieces[-1] += c
                key_due = c == "+" and not key_due
    var out: Array[String] = []
    for piece: String in pieces:
        if not piece.strip_edges().is_empty():
            out.append(piece.strip_edges())
    return out


## A value as KConfig wrote it, read back: `\\` is a backslash and `\s` a
## space, which is how Krita's own file holds the backslash key and the `; `
## of an action with two empty chords.
static func _unescaped(value: String) -> String:
    var out := ""
    var at := 0
    while at < value.length():
        var pair := value.substr(at, 2)
        if pair == "\\\\" or pair == "\\s":
            out += " " if pair == "\\s" else "\\"
            at += 2
        else:
            out += value[at]
            at += 1
    return out


## One chord as Krita spells it, in a spelling `SaShortcutStore.parse_chord`
## reads, or empty when it names a modifier Godot has no word for.
##
## Krita names keys the way Qt does. The words Qt and Godot spell apart, PgUp
## and the rest, the store reads itself. What is left is Qt's own: a glyph key
## written as its character, ";" or "\", which Godot reads only by its word,
## the keypad written as a modifier, "Num+5", which Godot would read as the top
## row's 5, and a media key's name in two words, "Media Play", which Godot
## writes as one.
static func sara_spelling(chord: String) -> String:
    var cut := SaCommandRegistry.key_name_at(chord)
    var key := chord.substr(cut)
    var parts := PackedStringArray()
    var keypad := false
    for part: String in chord.substr(0, cut).split("+", false):
        if part.to_lower() == "num":
            keypad = true
        elif MODIFIERS.has(part.to_lower()):
            parts.append(part)
        else:
            return ""
    if keypad and SaCommandRegistry.KEY_GLYPHS.values().has("Numpad " + key):
        key = "Numpad " + key
    elif key.length() == 1:
        key = OS.get_keycode_string(key.to_upper().unicode_at(0) as Key)
    elif not keypad:
        key = key.replace(" ", "")
    parts.append(key)
    return "+".join(parts)
