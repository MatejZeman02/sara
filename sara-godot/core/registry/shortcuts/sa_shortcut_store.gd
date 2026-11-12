## Every chord Sara answers to, as a thing that can be changed and kept.
##
## The InputMap is the truth about what the app answers to, and it is rebuilt
## from `project.godot` and from each command's `default_events` on every
## launch. So a rebind is stored as an override on top of that: a profile file
## names only the actions whose chords differ from the shipped map, and
## `apply` puts the shipped map back before laying the overrides over it. That
## is what lets a build that adds a command ship its chord to a painter who
## already has a profile.
##
## A chord is stored as the text a painter reads, "Ctrl+Shift+Z", because the
## file is meant to be legible and because `OS.find_keycode_from_string` reads
## that form back including its modifiers. `project.godot` binds most keys by
## physical keycode and a rebind writes a keycode event instead. Both reach
## `InputMap.action_has_event`, and the difference only shows on a non-QWERTY
## layout, where a rebound key follows the letters printed on the keys and a
## shipped one follows their position.
class_name SaShortcutStore
extends RefCounted

## The profile a fresh install is on: the shipped map, with no file behind it.
const DEFAULT_PROFILE: String = "Sara Default"

## Beside `docker_layout.cfg` and the brush presets, one file per profile.
const DIR_NAME: String = "shortcuts"
const EXTENSION: String = ".cfg"

## The section every profile file keeps its chords under.
const SECTION: String = "chords"

## What the painter reads when a profile's file could not be written.
# gdlint:ignore=max-line-length
const NOT_SAVED: String = "The shortcuts could not be saved as '%s', so the profile in use stays as it was. A name cannot hold any of \\ / : * ? \" < > | %%."

## The shipped map, action -> its chords as text, captured before anything has
## been laid over it. Static because there is one InputMap.
static var _defaults: Dictionary[String, Array] = {}

## Whether the sweep in `capture_defaults` has run.
##
## Separate from `_defaults` being empty, because `remember_shipped` writes into
## the same dictionary one action at a time and would otherwise make the sweep
## think it had already happened.
static var _captured: bool = false

## What each of `ALIASES` answered to when the shipped map was captured, the
## engine's own forms among them. Restored before a profile is laid over, so a
## profile that moves Redo and a switch back do not leave `ui_redo` on Sara's
## one chord with the engine's Ctrl+Y gone from every text box.
static var _alias_defaults: Dictionary[String, Array] = {}

## Where the profile files live. A test points this somewhere disposable.
static var dir_override: String = ""


## Remembers the InputMap as the build shipped it, once.
##
## Called by everything below before it reads or writes, so the order of
## startup does not decide whether the defaults are the shipped map or a
## painter's overrides. It is only ever the first call that captures.
static func capture_defaults() -> void:
    if _captured:
        return
    _captured = true
    for alias: String in ALIASES:
        if InputMap.has_action(StringName(alias)):
            _alias_defaults[alias] = _key_chords(StringName(alias))
    # Merged rather than assigned, so an action `remember_shipped` recorded
    # before the sweep keeps the chords it was born with. The two agree for an
    # action that existed either way, this only matters for one created in
    # between.
    for action: String in current_map():
        if not _defaults.has(action):
            _defaults[action] = current_map()[action]


## The chords *action* ships with, recorded the moment it is created.
##
## `capture_defaults` sweeps the InputMap at one instant, so an action created
## later was never in the shipped map without this: `overrides_now` would write
## its ordinary chord into every profile saved, and `apply_profile`, walking the
## shipped map, would never put it back. Called by
## `SaCommandRegistry._ensure_action`, where a command's own `default_events`
## reach the InputMap. A second record is refused, so a re-registration cannot
## promote a painter's override to a default.
static func remember_shipped(action: StringName) -> void:
    _record_shipped(action, InputMap.action_get_events(action))


## The chords a command ships with, recorded for an action that was already in
## the InputMap when the command registered.
##
## `remember_shipped` cannot read such an action, because it may have been
## rebound since and its chords would become a default. The one way an action
## exists before its command is a profile naming it at boot: the File menu's
## commands register when the router first runs, after `apply_active`, so a
## saved profile that binds Import a picture creates the action first. With the
## record empty, Back to Sara Default, which walks the record, would pass that
## action by for good and leave its Reset lit.
##
## What the build ships is the descriptor's own `default_events`, which is
## what `SaCommandRegistry._ensure_action` hands in. Before the sweep an action
## that exists came from `project.godot` and the sweep reads it, so nothing is
## recorded until then.
##
## **A late record puts the chords on an action left answering to nothing,
## unless the profile in force names it.** `apply_profile` reads an action it
## has no record of as unbound, so a switch to a profile that does not name it,
## made after another profile created it and before its command registered,
## takes its chords off, and the record alone would leave its row on Set… with
## a lit Reset. A profile that names the action laid what the painter asked
## for, and an action that still answers to a chord was given it on purpose,
## so both stay.
static func remember_shipped_events(action: StringName, shipped: Array) -> void:
    if not _captured or _defaults.has(String(action)):
        return
    _record_shipped(action, shipped)
    if not _defaults.has(String(action)) or not chords_for(action).is_empty():
        return
    if _overrides_in_force().has(String(action)):
        return
    for event: InputEvent in shipped:
        InputMap.action_add_event(action, event)


## The overrides of the profile the settings name, read the way `apply_active`
## reads the setting at boot.
static func _overrides_in_force() -> Dictionary[String, Array]:
    var profile := SaSettings.shortcuts_profile
    if profile.is_empty() or profile == "default":
        return {}
    return load_profile(profile)


static func _record_shipped(action: StringName, events: Array) -> void:
    var name := String(action)
    if name.is_empty() or _defaults.has(name) or is_engine_action(action):
        return
    var chords: Array[String] = []
    for event: InputEvent in events:
        var text := chord_text(event)
        if not text.is_empty():
            chords.append(text)
    _defaults[name] = chords


## The shipped map, action -> Array of chord texts.
static func defaults() -> Dictionary[String, Array]:
    capture_defaults()
    return _defaults


## The InputMap as it is now, action -> Array of chord texts, skipping the
## actions Godot ships for focus traversal and dialog buttons.
static func current_map() -> Dictionary[String, Array]:
    var out: Dictionary[String, Array] = {}
    for action: StringName in InputMap.get_actions():
        if not is_engine_action(action):
            out[String(action)] = _key_chords(action)
    return out


## The chords *action* answers to now, as text.
static func _key_chords(action: StringName) -> Array[String]:
    var chords: Array[String] = []
    for event: InputEvent in InputMap.action_get_events(action):
        var text := chord_text(event)
        if not text.is_empty():
            chords.append(text)
    return chords


## Actions that are a second name for another one, alias -> the owner.
##
## Godot's `ui_undo` and `ui_redo` carry Ctrl+Z and Ctrl+Shift+Z beside Sara's
## own `edit_undo` and `edit_redo`, because a LineEdit answers to the engine's
## pair and the menu to Sara's. They are one command to a painter, so the page
## shows one row, a rebind moves both, and the two sharing a chord is not a
## conflict. Without this the page opened with Undo and Redo marked as
## colliding with themselves.
const ALIASES := {
    "ui_undo": "edit_undo",
    "ui_redo": "edit_redo",
}

## Actions that are one gesture on purpose, each entry the set of names the
## router answers in a single branch.
##
## The stamp brush's `brush_toggle_eraser` command and the Eraser tool's
## `tool_eraser` answer one chord together: E toggles the brush's eraser mode
## when the brush is active and picks the Eraser tool when it is not. Two
## actions on one chord is what that costs, and a page that marked them told a
## painter their map was broken while it was doing what it was built to do.
##
## A pair is not an alias. An alias is one command under two names, so the page
## shows one row and the other name is not offered at all. A pair is two
## commands a painter looks for separately, under Tools and under Brush here, so
## both rows stay. What the two share is that neither collides with the other,
## and that a rebind moves the whole set: a pair that has come apart is not a
## gesture any more, and nothing on the page would say so.
const PAIRS: Array = [["brush_toggle_eraser", "tool_eraser"]]

## The command and quick tool pairs that share a key on purpose, so the page does
## not mark either of them.
##
## A quick tool is a key a painter leans on over the canvas rather than a chord
## they press, and none of the three is offered on the page at all:
## `ui/settings/input/tests/test_shortcut_sections.gd` carries the same roster
## under `NOT_ROWS`. A row marked against one names a thing the painter cannot
## act on.
##
## Not "a command never collides with a quick tool", which is one rule too
## wide: it would hide a command that landed on Alt or Space by accident, which
## is a collision a painter does want told. It is narrowed to the sharing that
## was decided, Ctrl+Space for the docker maximise against `tool_zoom_quick`.
##
## Not `PAIRS`, because these two do not move together. A painter who rebinds the
## maximise leaves the quick zoom on Ctrl+Space, where it ships.
const GESTURE_PAIRS: Array = [["docker_maximise", "tool_zoom_quick"]]

## The `ui_` actions Sara names that way and offers for rebinding, the rest of
## the prefix being Godot's own focus and dialog traversal (moved down from
## `SaShortcutsPage.LABELS`, so `core` does not name a class under `ui` to
## ask). `SaShortcutRows.LABELS` keeps the words a painter reads beside each
## one, which `ui/settings/input/tests/test_shortcut_sections.gd` holds this list to.
const UI_ACTIONS: Array[String] = ["ui_quit", "ui_scale_up", "ui_scale_down", "ui_scale_reset", "ui_take_note"]


## Godot's own actions, which are not Sara's to offer for rebinding, and the
## aliases, which are offered under the name they mirror. The `ui_` names Sara
## does list are exceptions, because they are Sara's commands named that way.
static func is_engine_action(action: StringName) -> bool:
    var action_name := String(action)
    if ALIASES.has(action_name):
        return true
    if not action_name.begins_with("ui_"):
        return false
    return not UI_ACTIONS.has(action_name)


## The other actions *action* is one gesture with, empty for all but the pairs
## above. What a rebind moves with it and what a conflict is not reported over.
static func paired_with(action: StringName) -> Array[StringName]:
    var out: Array[StringName] = []
    for pair: Array in PAIRS:
        if not pair.has(String(action)):
            continue
        for name: String in pair:
            if name != String(action):
                out.append(StringName(name))
    return out


## The other actions *action* shares a key with on purpose, empty for all but
## `GESTURE_PAIRS`. What a conflict is not reported over, and nothing a rebind
## moves along.
static func gesture_paired_with(action: StringName) -> Array[StringName]:
    var out: Array[StringName] = []
    for pair: Array in GESTURE_PAIRS:
        if not pair.has(String(action)):
            continue
        for name: String in pair:
            if name != String(action):
                out.append(StringName(name))
    return out


## The aliases of *action*, which a rebind has to move with it.
static func aliases_of(action: StringName) -> Array[StringName]:
    var out: Array[StringName] = []
    for alias: String in ALIASES:
        if ALIASES[alias] == String(action):
            out.append(StringName(alias))
    return out


## "Ctrl+Shift+Z" for a key event, empty for anything else.
##
## The same sentence `SaCommandRegistry.format_events` writes, one event at a
## time, so what the page shows and what the file stores cannot drift.
static func chord_text(event: InputEvent) -> String:
    var key := event as InputEventKey
    if key == null:
        return ""
    return SaCommandRegistry.format_events([key])


## The event a chord text stands for, or null when nothing reads it.
##
## Null as well when the modifiers read and the key does not. Godot answers
## "Ctrl+PgUp" with the Ctrl bit alone, and an event holding no key showed as
## "Ctrl+(unset)" on the row it landed on.
static func parse_chord(text: String) -> InputEventKey:
    if text.strip_edges().is_empty():
        return null
    var code := OS.find_keycode_from_string(_godot_spelling(text))
    if (code & KEY_CODE_MASK) == KEY_NONE:
        return null
    var event := InputEventKey.new()
    event.keycode = (code & KEY_CODE_MASK) as Key
    event.ctrl_pressed = bool(code & KEY_MASK_CTRL)
    event.shift_pressed = bool(code & KEY_MASK_SHIFT)
    event.alt_pressed = bool(code & KEY_MASK_ALT)
    event.meta_pressed = bool(code & KEY_MASK_META)
    return event


## Qt's word for a key Godot names another way, as Krita writes it.
const QT_KEY_NAMES: Dictionary[String, String] = {
    "PgUp": "PageUp",
    "PgDown": "PageDown",
    "Del": "Delete",
    "Ins": "Insert",
    "Esc": "Escape",
    "Return": "Enter",
}


## A chord whose key is written as its glyph or its page name, "Ctrl+[" or
## "Ctrl+Numpad +", in the word Godot can look up, "Ctrl+BracketLeft" or
## "Ctrl+Kp Add".
##
## Both spellings read, because a profile saved by an older build holds the
## word and must not stop opening. Only the key name is rewritten, so the
## modifiers in front of it are untouched. Qt's words for the keys Godot names
## otherwise read too, because they are how a Krita export writes them.
static func _godot_spelling(text: String) -> String:
    var cut := SaCommandRegistry.key_name_at(text)
    var name := text.substr(cut)
    if QT_KEY_NAMES.has(name):
        return text.substr(0, cut) + String(QT_KEY_NAMES[name])
    for code: int in SaCommandRegistry.KEY_GLYPHS:
        if String(SaCommandRegistry.KEY_GLYPHS[code]) == name:
            return text.substr(0, cut) + OS.get_keycode_string(code as Key)
    return text


## The chord an event carries, in the shape the page shows and the file keeps.
## Public so a capture step and the page's key grabber agree on one spelling.
static func chord_of_event(event: InputEventKey) -> String:
    var copy := InputEventKey.new()
    copy.keycode = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
    copy.ctrl_pressed = event.ctrl_pressed
    copy.shift_pressed = event.shift_pressed
    copy.alt_pressed = event.alt_pressed
    copy.meta_pressed = event.meta_pressed
    return chord_text(copy)


## The chords *action* answers to now, as text.
static func chords_for(action: StringName) -> Array[String]:
    var out: Array[String] = []
    if not InputMap.has_action(action):
        return out
    for event: InputEvent in InputMap.action_get_events(action):
        var text := chord_text(event)
        if not text.is_empty():
            out.append(text)
    return out


## Gives *action* exactly these chords, dropping whatever it had.
##
## The mouse and joypad events an action may also carry are kept: a rebind is
## about keys, and dropping the wheel binding off a zoom command because the
## page cannot show it would be a silent loss.
static func set_chords(action: StringName, chords: Array) -> void:
    _write_chords(action, chords)
    for alias: StringName in aliases_of(action):
        _write_chords(alias, chords)
    # The rest of the pair moves too, or half a gesture is left on the old chord
    # with nothing on the page saying it came apart.
    for partner: StringName in paired_with(action):
        _write_chords(partner, chords)
        for alias: StringName in aliases_of(partner):
            _write_chords(alias, chords)


## Every key event goes and the rest are put back, rather than each key event
## erased by itself: `InputMap.action_erase_event` matches by the key, so an
## event holding none was never matched and outlived every profile switch.
static func _write_chords(action: StringName, chords: Array) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    var kept := InputMap.action_get_events(action).filter(func(event: InputEvent) -> bool: return not event is InputEventKey)
    InputMap.action_erase_events(action)
    for event: InputEvent in kept:
        InputMap.action_add_event(action, event)
    for text: String in chords:
        var event := parse_chord(String(text))
        if event != null:
            InputMap.action_add_event(action, event)


## The actions other than *ignore* that already answer to *chord*.
##
## A conflict is reported rather than refused: two commands on one chord is a
## thing a painter may be halfway through fixing, and a page that refuses the
## first half of a swap cannot do the second.
##
## An action *ignore* is declared one gesture with is not a conflict with it,
## which is `PAIRS` above, and neither is one it shares a key with on purpose,
## which is `GESTURE_PAIRS`. Everything else that answers to the chord is
## reported, a quick tool included.
static func conflicts(chord: String, ignore: StringName = &"") -> Array[String]:
    var out: Array[String] = []
    if chord.is_empty():
        return out
    var paired := paired_with(ignore)
    var shared := gesture_paired_with(ignore)
    for action: StringName in InputMap.get_actions():
        if action == ignore or is_engine_action(action) or paired.has(action):
            continue
        if shared.has(action):
            continue
        if chords_for(action).has(chord):
            out.append(String(action))
    return out


## Every action but *action* that answers to *chord*, the other half of a pair
## and a quick tool included, in the order the `InputMap` lists them.
##
## Not `conflicts`, which leaves a pair's other half out because the two are one
## gesture. A line saying who holds a key has to name everyone who does: a
## painter who put the Brush on E has to be told about the Eraser and its toggle
## both, and the page coloured the row and named nobody.
static func holders(chord: String, action: StringName = &"") -> Array[String]:
    var out: Array[String] = []
    if chord.is_empty():
        return out
    for other: StringName in InputMap.get_actions():
        if other == action or is_engine_action(other):
            continue
        if chords_for(other).has(chord):
            out.append(String(other))
    return out


## Takes *chord* off every action that answers it beside *keep*, each keeping
## the other chords it has, and answers the actions it took it from. An action
## in *spare* keeps it.
##
## What a move on the page does when a painter answers that a taken chord should
## go to the row that asked for it, and what a profile does to the chords its
## overrides claim. `conflicts` picks the actions, so an alias and the other half
## of a pair move the way they do everywhere else. A profile switch passes an
## *index* it read once, which this keeps true as it rewrites.
static func release_chord(
    chord: String, keep: StringName, spare: Dictionary = {}, index: SaShortcutChordIndex = null
) -> Array[String]:
    var released: Array[String] = []
    for other: String in conflicts(chord, keep) if index == null else index.conflicts(chord, keep):
        if spare.has(other):
            continue
        var kept: Array[String] = []
        for held: String in chords_for(StringName(other)):
            if held != chord:
                kept.append(held)
        set_chords(StringName(other), kept)
        if index != null:
            index.reread_after_writing(StringName(other))
        released.append(other)
    return released


## Every action that answers to a chord another one also answers to, as
## `{action: [the others]}`. What the page marks a row with.
static func all_conflicts() -> Dictionary[String, Array]:
    return SaShortcutChordIndex.new().clashes()


# --- Profiles ------------------------------------------------------------------


## Where the profile files live.
static func dir_path() -> String:
    if not dir_override.is_empty():
        return dir_override
    return SaSettings.get_settings_dir().path_join(DIR_NAME)


## Krita's, Photoshop's and Clip Studio Paint's stock chords for the commands
## Sara shares with them, command id -> one chord text or a list of them, in the spelling
## `chord_text` writes. A command missing from a table keeps Sara's own chord,
## the same silence a saved profile keeps about an action nobody touched.
##
## **Krita's is the chord column of one table, Photoshop's is still from
## memory.** `KRITA_DEFAULTS` is `SaShortcutKritaTable.CHORDS`, which sits beside
## the Krita action each row answers, and Import from Krita reads that column,
## so the profile and an import of Krita's own file cannot part. Photoshop's is
## `SaShortcutPhotoshopTable.CHORDS`, still written from memory, because no
## Photoshop install is here to read. Clip Studio Paint's is
## `SaShortcutClipStudioTable.CHORDS`, from memory for the same reason.
const KRITA_DEFAULTS: Dictionary[String, Variant] = SaShortcutKritaTable.CHORDS
const PHOTOSHOP_DEFAULTS: Dictionary[String, String] = SaShortcutPhotoshopTable.CHORDS
## Procreate's iPad keyboard shortcuts, `SaShortcutProcreateTable.CHORDS`, also
## from memory as well.
const PROCREATE_DEFAULTS: Dictionary[String, String] = SaShortcutProcreateTable.CHORDS
const CLIP_STUDIO_DEFAULTS: Dictionary[String, String] = SaShortcutClipStudioTable.CHORDS

## The keys a shipped chord stands beside on the build's own map: the numpad's
## plus, minus, slash, asterisk, period and digits, and Plus beside Equal, since
## a table names one key per gesture. On a Czech keyboard the digit row and `/`
## need Shift, so the numpad is the way left.
const KEY_FAMILIES: Array = [
    [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD],
    [KEY_MINUS, KEY_KP_SUBTRACT],
    [KEY_SLASH, KEY_KP_DIVIDE],
    [KEY_ASTERISK, KEY_KP_MULTIPLY],
    [KEY_PERIOD, KEY_KP_PERIOD],
]


## The keys *keycode* is the same key as, itself included.
static func _same_keys(keycode: int) -> Array:
    for family: Array in KEY_FAMILIES:
        if family.has(keycode):
            return family
    var digit := keycode - KEY_KP_0 if keycode >= KEY_KP_0 and keycode <= KEY_KP_9 else keycode - KEY_0
    if digit >= 0 and digit <= 9:
        return [KEY_0 + digit, KEY_KP_0 + digit]
    return [keycode]


## The chords an action is to hold under a shipped table's entry: the entry
## first, and the build's own chords beside it where they are the same key on
## another row with the same modifiers.
##
## **The alternatives stay, the rest goes.** A table names Ctrl+Equal for the
## zoom, and the build also binds Ctrl+Plus and the numpad's plus. Replacing the
## whole list would take the numpad away from a painter the moment the profile is
## chosen, and on a keyboard whose digit row needs Shift that is the only way
## left to the zoom.
##
## Only keys of one family and one modifier set are kept, so an entry that really
## moves an action to another key leaves nothing of the old one behind. An entry
## with no chord in it clears the action, which is what Krita's table does for
## the alpha lock and Photoshop's does for the ten brush slots. A list entry is
## read chord by chord, each keeping the build's alternatives of its own key.
##
## **A key another entry of *table* names stays that entry's.** Krita's table
## gives the numpad's slash to Isolate Active Layer and `/` to the previous
## preset, so the build's `/` beside the numpad's slash is not kept. *named_by*
## is `_keys_named_by` of the table, read once for all its entries: read again
## for each, a switch to Krita spent a tenth of a second here.
static func _chords_a_shipped_entry_keeps(
    action: String, entry: Variant, shipped: Dictionary[String, Array], named_by: Dictionary = {}
) -> Array[String]:
    var out := entry_chords(entry)
    var named: Array[InputEventKey] = []
    var taken := {}
    for key: String in named_by:
        var naming: Array = named_by[key]
        if naming.size() > (1 if naming.has(action) else 0):
            taken[key] = true
    for chord: String in out:
        var event := parse_chord(chord)
        if event != null:
            named.append(event)
            taken[_key_and_modifiers(event)] = true
    for held: Variant in shipped.get(action, []):
        var event := parse_chord(str(held))
        # One key with two spellings is one chord: the table writes
        # "Ctrl+BracketLeft" where the build writes "Ctrl+[".
        if event == null or taken.has(_key_and_modifiers(event)):
            continue
        for one: InputEventKey in named:
            if _same_keys(one.keycode).has(event.keycode) and _same_modifiers(event, one):
                taken[_key_and_modifiers(event)] = true
                out.append(str(held))
                break
    return out


## Each key and modifier set *table*'s entries name -> the actions naming it.
static func _keys_named_by(table: Dictionary) -> Dictionary:
    var out := {}
    for action: String in table:
        for event: InputEventKey in entry_chords(table[action]).map(parse_chord):
            var key := _key_and_modifiers(event) if event != null else ""
            var naming: Array = out.get(key, [])
            if not key.is_empty() and not naming.has(action):
                out[key] = naming + [action]
    return out


## The chords one entry of a shipped table names, none for an empty one.
static func entry_chords(entry: Variant) -> Array[String]:
    var out: Array[String] = []
    var listed: Array = entry if entry is Array else [entry]
    for chord: Variant in listed:
        if not str(chord).strip_edges().is_empty():
            out.append(str(chord))
    return out


## Whether two events hold the same modifiers, whichever keys they name.
static func _same_modifiers(one: InputEventKey, other: InputEventKey) -> bool:
    return (
        one.ctrl_pressed == other.ctrl_pressed
        and one.shift_pressed == other.shift_pressed
        and one.alt_pressed == other.alt_pressed
        and one.meta_pressed == other.meta_pressed
    )


## One event as the chord it is, for telling two spellings of one chord apart
## from two chords.
static func _key_and_modifiers(event: InputEventKey) -> String:
    return (
        "%d/%d%d%d%d"
        % [
            event.keycode,
            int(event.ctrl_pressed),
            int(event.shift_pressed),
            int(event.alt_pressed),
            int(event.meta_pressed),
        ]
    )


## The start of every docker summon's action id, which shows a docker under
## the pointer until the pointer leaves it. Under `docker_`, so the Keyboard
## Shortcuts page files every summon in the Dockers section.
##
## No program a shipped map follows has a summon, so every shipped map leaves
## each one unbound, which is the rule `docker_maximise` follows above. By the prefix
## rather than by a row per docker in each table, because a summon is registered
## for every docker the command table knows and a row per docker would be a list
## somebody forgets to extend.
const SUMMON_PREFIX: String = "docker_summon_"

## The shipped profiles beside the build's own map, name -> its table, a
## chord or a list of them per action. What an entry leaves beside it is
## `_chords_a_shipped_entry_keeps`'s reading rather than a second column here.
const SHIPPED_PROFILES: Dictionary[String, Dictionary] = {
    "Krita": KRITA_DEFAULTS,
    "Photoshop": PHOTOSHOP_DEFAULTS,
    "Procreate": PROCREATE_DEFAULTS,
    "Clip Studio Paint": CLIP_STUDIO_DEFAULTS,
}

## What a fork of a shipped profile is called, in the spelling
## `ui/layout/docker_layout_presets.gd` already uses for the same move: a shipped thing
## a painter edits forks rather than refusing the edit or losing it.
const FORK_SUFFIX: String = " (custom)"


## A shipped profile cannot be deleted, only copied: the map the build itself
## carries, and the three shipped beside it from a table rather than a file, so
## there is nothing on disk a painter could edit out from under it either.
static func is_shipped(profile: String) -> bool:
    return profile == DEFAULT_PROFILE or SHIPPED_PROFILES.has(profile)


## Every profile there is: the shipped ones first, then what is on disk, sorted.
static func list_profiles() -> Array[String]:
    var out: Array[String] = [DEFAULT_PROFILE]
    out.append_array(SHIPPED_PROFILES.keys())
    var saved: Array[String] = []
    var dir := DirAccess.open(dir_path())
    if dir != null:
        for file: String in dir.get_files():
            if not file.ends_with(EXTENSION):
                continue
            var name := file.trim_suffix(EXTENSION)
            if not is_shipped(name):
                saved.append(name)
    saved.sort()
    out.append_array(saved)
    return out


## The overrides *profile* keeps, action -> Array of chord texts, the whole list
## the action is to answer to. The default profile keeps none, which is what
## makes it the shipped map. A shipped program's profile answers from
## its table, not a file, and each of its entries keeps the build's own chords
## beside it (`_chords_a_shipped_entry_keeps`).
static func load_profile(profile: String) -> Dictionary[String, Array]:
    if profile == DEFAULT_PROFILE:
        return {}
    if SHIPPED_PROFILES.has(profile):
        var table: Dictionary = SHIPPED_PROFILES[profile]
        var shipped: Dictionary[String, Array] = {}
        var built := defaults()
        var named_by := _keys_named_by(table)
        for action: String in table:
            shipped[action] = _chords_a_shipped_entry_keeps(action, table[action], built, named_by)
        for action: StringName in InputMap.get_actions():
            if String(action).begins_with(SUMMON_PREFIX) and not shipped.has(String(action)):
                shipped[String(action)] = [""]
        return shipped
    var config := ConfigFile.new()
    if config.load(path_for(profile)) != OK:
        return {}
    var out: Dictionary[String, Array] = {}
    for action: String in config.get_section_keys(SECTION):
        var chords: Array[String] = []
        var stored: Array = config.get_value(SECTION, action, [])
        chords.assign(stored)
        if action == "window_fullscreen" and chords.size() == 2 and chords.has("F11") and chords.has("Ctrl+Shift+F"):
            continue
        out[action] = chords
    return out


## Writes the InputMap's differences from the shipped map under *profile*, and
## answers how many actions it wrote, or -1 with a refusal when no file was.
##
## Only the differences, so a build that adds a command gives its chord to a
## painter who saved a profile before it existed. A failed save is not 0,
## because 0 is a profile with nothing changed, and the callers that name the
## profile in the settings would name one with no file under it, whose chords
## are gone at the next start. A name no file can take on some system is
## refused on all of them, so a profile made here travels to Windows.
static func save_profile(profile: String) -> int:
    var overrides := _overrides_that_keep_the_map()
    if profile.is_valid_filename() and save_overrides(profile, overrides):
        return overrides.size()
    SaProblems.refuse("SaShortcutStore", TranslationServer.translate(NOT_SAVED) % profile)
    return -1


## What a profile saved now has to hold for `apply_profile` to give the map back
## as it stands: every override, and beside one that shares its key, the chords
## of the action it shares it with.
##
## `apply_profile` takes an override's chord off whatever else answers to it,
## which is right for a table and was wrong for a map saved with a clash in it.
## Redo put on Ctrl+Z beside Undo was saved as Redo alone, so the next launch,
## or a switch back to that profile, took Ctrl+Z off Undo while the page had
## shown Undo holding it. An action the file names is one the release
## leaves alone, so naming the other holder is what keeps it.
static func _overrides_that_keep_the_map() -> Dictionary[String, Array]:
    var out := overrides_now()
    for action: String in out.keys():
        for chord: Variant in out[action]:
            for other: String in conflicts(str(chord), StringName(action)):
                if not out.has(other):
                    out[other] = chords_for(StringName(other))
    return out


## What the live map holds that the shipped map does not, action -> chords.
## A profile is exactly this, which is why a build that adds a command gives the
## painter its chord instead of leaving it unbound.
static func overrides_now() -> Dictionary[String, Array]:
    var shipped := defaults()
    var out: Dictionary[String, Array] = {}
    for action: String in current_map():
        var chords: Array = current_map()[action]
        if shipped.get(action, []) != chords:
            out[action] = chords
    return out


## The profile a fork was made from, and *profile* itself when it is not one.
##
## What a per-row Reset reads instead of the active profile. The active profile
## is often a fork holding exactly the edits a painter is asking to put back,
## and reading it would make Reset a button that does nothing.
static func source_profile(profile: String) -> String:
    return profile.trim_suffix(FORK_SUFFIX) if profile.ends_with(FORK_SUFFIX) else profile


## The shipped profile *profile* goes back to: itself when the build ships it,
## the one it was forked from when it is a fork, and Sara Default for one a
## painter saved or imported, whose file is a difference from that map.
##
## What Start again applies and names on its button. It applied the active
## profile, and after any edit that is the fork holding the edit: a painter who
## put Redo on Ctrl+Z and started again was handed the fork back, and the fork's
## own override took Ctrl+Z off Undo, which left Undo with no chord at all.
static func shipped_source(profile: String) -> String:
    var source := source_profile(profile)
    return source if is_shipped(source) else DEFAULT_PROFILE


## Where an edit made under *profile* is saved: the profile itself when a
## painter owns it, and a fork of it when the build ships it.
static func target_profile(profile: String) -> String:
    var wanted := profile.strip_edges()
    if wanted.is_empty() or wanted == "default":
        wanted = DEFAULT_PROFILE
    return wanted + FORK_SUFFIX if is_shipped(wanted) else wanted


## Writes the map as it stands into the profile an edit belongs in, points the
## settings at that profile, and answers its name.
##
## What every rebind ends in. `set_chords` writes the `InputMap` and nothing
## else, so without the save around it a chord a painter changed would be gone
## at the next launch. The docker layout store answers the same situation the
## same way, which is where the name of the fork comes from.
##
## A shipped profile with nothing changed under it is left alone rather than
## forked into an empty file, which is what a reset of a row nobody moved would
## otherwise leave in the dropdown.
static func remember_edit() -> String:
    var active := SaSettings.shortcuts_profile
    var target := target_profile(active)
    if target != active and overrides_now().is_empty():
        return active
    # A save that failed leaves the setting on the profile that has a file.
    if save_profile(target) < 0:
        return active
    SaSettings.shortcuts_profile = target
    return target


## Reads the Krita `.shortcuts` export at *path*, lays what it names over the
## Krita profile, saves that as a profile named after the file and switches to
## it. The reading answered keeps `profile` empty when nothing was saved, and
## names in `unread` each chord no key here reads, which is left out rather
## than kept as a modifier alone.
##
## **Over the Krita profile, not over Sara Default.** Laid over Sara's own map,
## an import moved only the commands the file named, and every chord the
## profile places for a Krita hand without a Krita action behind it stayed
## Sara's: the Reference solo lost Ctrl+Alt+S to Save and got nothing back, and
## the summons kept Krita's blending mode chords. Those rows are Sara's answer
## to a Krita hand, which no Krita file can carry, so an import keeps them, and
## importing Krita's stock file, or an Export Scheme of an untouched Krita with
## its `none` on every action Krita ships unbound, gives exactly the Krita
## profile.
static func import_krita(path: String) -> SaShortcutKritaNames.Reading:
    var reading := SaShortcutKritaNames.parse(path)
    var profile := path.get_file().get_basename()
    if reading.overrides.is_empty() or not save_overrides(profile, _over_the_krita_profile(reading.overrides)):
        return reading
    reading.profile = profile
    SaSettings.shortcuts_profile = profile
    apply_profile(profile)
    return reading


## The Krita profile with *read* laid over it, each command the file names
## keeping the build's own chords beside the file's the way a shipped entry
## does, so the numpad's plus stays on the zoom an import puts on Ctrl+=.
##
## A chord the file gives comes off every profile row the file did not name,
## the way `_release_chords_the_profile_took` takes it off the rest of the map.
## That step spares whatever the saved profile names, and an import names every
## row of Krita's, so a file putting Duplicate Layer on Ctrl+Alt+D left the
## Reference solo on it too and the router answered whichever it asked first.
static func _over_the_krita_profile(read: Dictionary[String, Array]) -> Dictionary[String, Array]:
    var out := load_profile("Krita")
    var built := defaults()
    for action: String in read:
        out[action] = _chords_a_shipped_entry_keeps(action, read[action], built)
    for action: String in read:
        var spared := paired_with(StringName(action)) + gesture_paired_with(StringName(action))
        for chord: String in out[action]:
            for other: String in out:
                if not read.has(other) and not spared.has(StringName(other)):
                    out[other] = _chords_without(out[other], chord)
    return out


## *chords* less every spelling of *chord*.
static func _chords_without(chords: Array, chord: String) -> Array[String]:
    var gone := parse_chord(chord)
    var out: Array[String] = []
    for held: Variant in chords:
        var event := parse_chord(str(held))
        if gone == null or event == null or _key_and_modifiers(event) != _key_and_modifiers(gone):
            out.append(str(held))
    return out


## Writes *overrides* verbatim under *profile*, action -> Array of chord
## texts, with no diff against the live InputMap. What the Krita import
## uses: it already knows exactly what a `.shortcuts` file and the Krita
## profile under it hold against Sara's own defaults, and it read that from a
## file and a table rather than from the running app.
##
## **Only the chords are rewritten.** Every other section the file holds stays,
## so the Quick Favourites kept beside a profile's chords survive the next
## rebind, and a profile with no file yet starts from the one in use, so a copy
## under a new name keeps them too.
static func save_overrides(profile: String, overrides: Dictionary[String, Array]) -> bool:
    if profile.strip_edges().is_empty() or is_shipped(profile):
        return false
    if not _ensure_dir():
        return false
    var config := ConfigFile.new()
    if config.load(path_for(profile)) != OK:
        config.load(path_for(SaSettings.shortcuts_profile))
    if config.has_section(SECTION):
        config.erase_section(SECTION)
    for action: String in overrides:
        config.set_value(SECTION, action, overrides[action])
    return config.save(path_for(profile)) == OK


## Removes a saved profile. A shipped one is refused.
static func delete_profile(profile: String) -> bool:
    if is_shipped(profile):
        return false
    return DirAccess.remove_absolute(path_for(profile)) == OK


## Puts the shipped map back and lays *profile*'s overrides over it.
##
## Only the actions that differ are rewritten, both on the way back and on the
## way out. `project.godot` binds most keys by physical keycode and this writes
## keycode events, so rewriting an action nobody changed would quietly move it
## from the key's position to the letter printed on it, for every action at
## once, on every launch.
static func apply_profile(profile: String) -> void:
    var shipped := defaults()
    var now := current_map()
    for action: String in shipped:
        # An action the shipped map remembers and the InputMap no longer has is
        # one a module took away with it, and `set_chords` would put it back. It
        # never came up while the shipped map was one sweep of the actions that
        # existed, and it does the moment a command records its own chords as it
        # registers: an action erased later stayed in the record and the next
        # profile switch recreated it, answering a key with no command behind it
        # and no Preferences section to show it in.
        if not InputMap.has_action(StringName(action)):
            continue
        if now.get(action, []) != shipped[action]:
            set_chords(StringName(action), shipped[action])
    # An action the shipped map never recorded is unbound there, the reading
    # `overrides_now` already has of it. Without this the walk above only ever
    # reached the actions the record names, and a chord on any other stayed.
    for action: String in now:
        if not shipped.has(action) and not now[action].is_empty():
            set_chords(StringName(action), [])
    for alias: String in _alias_defaults:
        _write_chords(StringName(alias), _alias_defaults[alias])
    var overrides := load_profile(profile)
    for action: String in overrides:
        if shipped.get(action, []) != overrides[action]:
            set_chords(StringName(action), overrides[action])
    _release_chords_the_profile_took(overrides)


## Every chord an override claims, taken off whatever else still answered to
## it.
##
## A profile says "this key means that here". Laid on top with nothing taken
## away, two actions held the chord and whichever `ShortcutRouter.handle` asked
## first won: Photoshop's bare Z for `tool_zoom` opened Brush Presets, which
## holds Z, with two rows on the Keyboard Shortcuts page claiming the key.
##
## **Only the chord moves, not the binding.** An action that held two keeps the
## other, so Photoshop leaves the presets docker on its S. And an action the
## profile names itself is never stripped, so a profile that swaps two chords
## round keeps both halves.
##
## `conflicts` is what reads the rest of the map, so an alias and the other half
## of a `PAIRS` gesture are left alone here the way they are everywhere else.
## The restore loop above puts every chord back before this runs, so switching
## away from a profile returns the key to whatever the shipped map gave it.
static func _release_chords_the_profile_took(overrides: Dictionary[String, Array]) -> void:
    var index := SaShortcutChordIndex.new()
    for action: String in overrides:
        for chord: Variant in overrides[action]:
            release_chord(str(chord), StringName(action), overrides, index)


## The profile the settings name, applied. Called once at startup, after the
## commands have created their actions and before anything reads a chord.
static func apply_active() -> void:
    capture_defaults()
    var profile := SaSettings.shortcuts_profile
    if profile.is_empty() or profile == "default":
        return
    apply_profile(profile)


## The file *profile* is saved in, whether or not it is there yet.
static func path_for(profile: String) -> String:
    return dir_path().path_join(profile + EXTENSION)


static func _ensure_dir() -> bool:
    var path := dir_path()
    if DirAccess.dir_exists_absolute(path):
        return true
    return DirAccess.make_dir_recursive_absolute(path) == OK
