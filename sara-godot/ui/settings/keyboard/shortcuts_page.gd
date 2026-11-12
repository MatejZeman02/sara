## Preferences > Keyboard Shortcuts: every chord Sara answers to, and the
## editing of it.
##
## This was `ui/shortcuts_dialog.gd`, a read-only list in a scroll whose bar
## covered the chord column, opened from Help. It is a Preferences page now,
## because that is where a painter looks for it, and the Help entry opens this
## page. The tables below came with it: a label per action whose identifier is
## not a sentence, the sections, and the gestures that have no action to read
## from.
##
## A row is the command, one button per chord it answers to, a reset and a clear.
## Click a chord and the next key you press becomes that chord, with the
## command's other chords left alone, and Escape leaves it alone. Backspace or
## Delete on its own is not a chord there but the way to take the chord off, as
## it is in Krita and Photoshop, so a default is freed without a detour through
## Reset, and Reset is the way back to it.
##
## **A key another command holds asks first**, because a key taken with nothing
## said leaves one of the two commands never firing: Redo put on Ctrl+Z leaves
## Undo's row claiming a key Redo answers, and the Brush put on E never comes
## up, because the eraser's toggle answers E first. The question names the
## holder and offers to move the key, to share it, or to leave both rows alone.
## Moving is how two chords are swapped, so a swap never passes through a clash.
## A clash that stands, shared on purpose or brought by a profile, says under
## the row who holds the key and which of them a press goes to.
##
## **Every chord, not the first**: the zoom commands answer the top row's Equal,
## Plus and the numpad's plus, and a row that prints the first of them reads as
## if the others were absent. A numpad chord is shown with the word Numpad,
## which is the name of the key and the mark that it is not the digit row. The
## wording is `SaCommandRegistry.key_text`'s, the one a menu row's chord column
## reads, so the page and the menu cannot name one key two ways.
##
## The list is read from the InputMap, never typed here, so it cannot say a key
## works when it does not.
##
## **Two declared pages in the one file, because there are two lifetimes**. The
## Profile section is the page `SaSettingsPage` declares once and never again,
## and the rows under it are declared pages of their own in `ShortcutRows`,
## [SaShortcutGroups], whose declaration is the InputMap as it stands and which
## [method refresh] rebuilds. One page would have freed the search field with
## the rows, under the hand typing in it.
class_name SaShortcutsPage
extends SaSettingsPage

## The tables and the lookups live in `ui/settings/keyboard/shortcut_rows.gd`.
## They are named through here because
## `ui/menus/tests/test_help_names_the_build_and_the_shortcuts.gd` and
## `ui/notes/tests/test_note_mode.gd` reach for `SaShortcutsPage.GROUPS` and its
## siblings. `core/registry/shortcuts/sa_shortcut_store.gd` keeps its own `ui_`
## list, because `core` may not name a class under `ui`.
##
## `const` holding another class's `const` resolves, unlike a `const` holding
## another class's enum, which does not. gdlint wants a class-scope `var` in
## snake case, so these have to be constants rather than static vars whatever
## else were true.
const GROUPS := SaShortcutRows.GROUPS
const KEYCODE_CHORDS := SaShortcutRows.KEYCODE_CHORDS
const GESTURES := SaShortcutRows.GESTURES


static func actions_for(prefix: String) -> Array[StringName]:
    return SaShortcutRows.actions_for(prefix)


static func rows_for(
    prefix: String, tools: SaToolRegistry = null, filters: SaFilterRegistry = null, commands: SaCommandRegistry = null
) -> Array:
    return SaShortcutRows.rows_for(prefix, tools, filters, commands)


static func label_for(
    action: String, tools: SaToolRegistry = null, filters: SaFilterRegistry = null, commands: SaCommandRegistry = null
) -> String:
    return SaShortcutRows.label_for(action, tools, filters, commands)


static func keys_for(action: StringName) -> String:
    return SaShortcutRows.keys_for(action)


## What a row's chord button says while it is waiting for a key.
const LISTENING_TEXT: String = "Press a key..."

## What the one chord button of a command with no chord says: what a press on it
## does, rather than "None", which reads as the answer to a question nobody
## asked and not as the button that gives the command a key.
const NO_CHORD_TEXT: String = "Set..."

## What a chord button's tooltip says. The last half is how a painter learns that
## Delete and Backspace are the clearing keys and so cannot be chords, and that
## Reset is how Delete comes back to a command that shipped on it.
const CHORD_TIP: String = "Click, then press a key to change this shortcut. Backspace or Delete clears it, and Reset restores it."

## The answers of the question a taken chord asks, by the index of their button.
## Enter moves, because the key was pressed to be given to the row, and Escape
## leaves both rows as they were.
const ANSWER_MOVE := 0
const ANSWER_SHARE := 1
const ANSWER_CANCEL := 2

## What an action's declared row is keyed by, the action after it, and what a
## row nobody can rebind is keyed by, so the first is never mistaken for it.
const CHORD_KEY := "chord_"
const FIXED_KEY := "fixed_"

var search: LineEdit
var profile_option: SaChoiceButton
var save_as_name: LineEdit

## Delete, dimmed while the active profile is a shipped one, which
## [method _on_delete] refuses. Kept in step by [method _refresh_profiles].
var delete_button: Button

## action -> the row's chord Buttons, one per chord the command answers. A row
## with a numpad chord as well as a digit row chord has two, because a rebind
## replaces the chord clicked and leaves the others.
var _chord_buttons: Dictionary = {}
var _section_boxes: Dictionary = {}
var _rows_by_action: Dictionary = {}
## action -> the box its chord buttons and its reset sit in, so a rebind can
## redraw one row rather than the page.
var _row_boxes: Dictionary = {}
var _profiles: Array[String] = []

## The action whose row is waiting for a key, empty when none is. What a
## capture prints and what a test reads.
var listening: StringName = &""

## The question a taken chord is asking, null when none is. What a test reads
## and presses a button of, and the capture door's `answer` step finds.
var question: SaMessage = null

## action -> the line under its row that says who else holds its keys, hidden
## while nobody does.
var _clash_lines: Dictionary = {}

## A fixed row's key -> its words and the keys it shows, which are what the
## search reads of it, since it has no action whose name or chords to read.
var _fixed_rows: Dictionary = {}

## The overrides of the profile Reset goes back to, read once for a whole
## rebuild and empty outside one, when a row reads them afresh.
var _reset_overrides: Dictionary = {}

## "Nothing matches", under the Profile section while a search hides every row.
var nothing_matches: Label

## Which of *listening*'s chords the key that lands replaces, or -1 for the
## whole list. Kept beside `listening` because the rebind needs both.
var _listening_index: int = -1

var _tools: SaToolRegistry = null
var _filters: SaFilterRegistry = null
## The command registry, whose titles are the words every command's row reads.
var _commands: SaCommandRegistry = null
## The rows under the Profile section, declared from the InputMap, a column per
## group.
var _rows_host: SaShortcutGroups


## The store's defaults first, because the declaration reads the map, and then
## `super()`, which declares and realizes the Profile section.
##
## The three registries name a module's tool, filter and command the way their
## own surfaces do, as [method bind_tools] says. Handed here, the rows are built
## once. Bound after, they were built twice, and the Preferences window and the
## search's catalogue build this page with the registries in hand, so the second
## build was half of a 160 ms frame.
##
## *spread* builds the rows a slice a frame once the page is on screen, which is
## what the Preferences window asks for the page it shows, and otherwise they
## are all built here, which is what the search's index and a suite read.
func _init(
    registry: SaToolRegistry = null, filters: SaFilterRegistry = null, commands: SaCommandRegistry = null, spread: bool = false
) -> void:
    _tools = registry
    _filters = filters
    _commands = commands
    SaShortcutStore.capture_defaults()
    super()

    # Added to the page itself, because the door finds the page as this host's
    # parent (`SaPreferencesDriver.open_shortcuts_page`).
    _rows_host = SaShortcutGroups.new(_on_rows_built)
    add_child(_rows_host)
    # Beside the rows rather than among them, because a rebuild empties the host.
    nothing_matches = SaMake.label(self, "NothingMatches", tr("Nothing matches"))
    nothing_matches.visible = false
    _fill(spread)


## The Profile section, declared once. Every row but the two buttons is custom:
## the dropdown's list is the store's and is refilled behind it, the profile box
## is a field and two buttons, and the search filters as it is typed in rather
## than on a commit, which is not what a text row does.
func build(ui: SaPage) -> void:
    var top := ui.section("Profile")

    # Sara's own choice button rather than the engine's dropdown. The rows carry
    # the profile's name, so the handler is handed the profile rather than a
    # position in a list it would have to hold on to.
    profile_option = SaMake.choice(null, "ProfileOpt")
    profile_option.choice_picked.connect(func(id: Variant) -> void: _on_profile_chosen(String(id)))
    top.custom("Shortcut profile", profile_option).named(&"profile").explain(
        tr("A saved set of shortcuts. A change to a built-in profile such as Sara Default is saved as a copy of it.")
    )

    var save_box := SaMake.row(null, "SaveBox", 6)
    save_as_name = SaMake.line_edit(save_box, "SaveAsName", "", tr("Name"))
    save_as_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    SaMake.button(save_box, "SaveAsButton", tr("Save As")).pressed.connect(_on_save_as)
    delete_button = SaMake.button(save_box, "DeleteButton", tr("Delete"))
    delete_button.pressed.connect(_on_delete)
    # The box keeps the width a row gives it rather than asking to fill, because
    # the layer hands a custom control its own width back, so asking would widen
    # the row.
    top.custom("Your profiles", save_box).named(&"your_profiles").explain(
        tr("Save the current shortcuts as a profile of your own.")
    )

    # One button that names where it goes, rather than a title and a button
    # saying two things, Start again and Reset All, with neither naming the map
    # it went back to. [method _refresh_profiles] writes the name, because it
    # follows the profile above.
    var back := top.action("Back to Sara Default", start_again).named(&"start_again").node("ResetAllButton")
    back.words("Start again Reset All").explain(
        tr("Restore the built-in shortcuts the button names. Your own profiles are kept.")
    )
    top.action("From another program", _on_import_krita_pressed).button("Import from Krita...").node("ImportKritaButton").explain(
        tr("Reads a Krita .shortcuts export and saves it as a new profile.")
    )

    search = SaMake.line_edit(null, "SearchField", "", tr("Search"))
    search.clear_button_enabled = true
    SaSearchField.mark(search)
    search.text_changed.connect(_on_search_changed)
    top.custom("Find a command", search).named(&"find").explain(tr("Filters the rows below by their name or their key."))


## Points the tool rows at the tool registry and the filter rows at the filter
## registry, so a module's tool is named the way its own button is and a
## module's filter the way its menu row is. Optional: without them a row is
## named from its action.
func bind_tools(registry: SaToolRegistry, filters: SaFilterRegistry = null, commands: SaCommandRegistry = null) -> void:
    _tools = registry
    _filters = filters
    _commands = commands
    refresh()


## Rebuilds every row from the InputMap as it is now.
##
## The rows page's `rebuild()`, which is the declaration from the top, and then
## the row lines read back off what it realized: a row's `line` is what the
## search hides. The chord buttons and the box they sit in are recorded on the
## way past by `_declare_row`, because a row has one button per chord and only
## the store knows how many that is.
## **The filter stays a hide** and never comes through here, because a rebuild
## on a keystroke is a page that loses the keyboard on every letter, and the
## rule pass leaves the visibility of a row no rule names alone.
func refresh() -> void:
    _fill(false)


## Every row built again from the store, at once or, *spread*, a slice a frame.
## The page's tables are emptied here and filled by [method _on_rows_built] as
## each slice lands.
func _fill(spread: bool) -> void:
    _listen_to(&"")
    _chord_buttons.clear()
    _section_boxes.clear()
    _rows_by_action.clear()
    _row_boxes.clear()
    _clash_lines.clear()
    _fixed_rows.clear()
    _refresh_profiles()

    # Every row asks what Reset would give it, and a shipped profile answers
    # that by building its whole table, so the page reads it once per fill and
    # holds it until the last slice. Read per row, a switch to Krita took 25 s
    # on Linux and half a minute on Windows.
    _reset_overrides = _read_reset_overrides()
    _rows_host.fill(_row_groups(), spread)


## The rows of each slice [SaShortcutGroups] built, entered in the tables a
## rebind, a search and the conflicts read, and the search and the conflicts
## run over the page again. *done* is the last slice.
##
## Only the slice's own rows are marked and measured, because a slice that ran
## over every row built so far grew from 27 to 45 ms a frame by the last one.
## A search typed while the rows arrive runs over them all, as it would.
func _on_rows_built(made: Array[SaPage], done: bool) -> void:
    var actions: Array[StringName] = []
    for part: SaPage in made:
        # A fixed row as well, so a search reaches a gesture the way it reaches
        # a command.
        for declared in part.rows():
            var action := StringName(String(declared.key).trim_prefix(CHORD_KEY))
            _rows_by_action[action] = declared.line
            actions.append(action)
    for title: String in _rows_host.columns:
        _section_boxes[title] = _rows_host.columns[title]
    _mark_conflicts_of(actions, SaShortcutStore.all_conflicts())
    if search != null and not search.text.strip_edges().is_empty():
        _apply_search(search.text)
    if done:
        _reset_overrides = {}


## Builds every row still waiting at once, for a door that lands on a row the
## page has not built yet.
func fill_now() -> void:
    _rows_host.fill_now()


## The rows page's declaration: a group per group of commands that has a row,
## a custom row per action, and a custom row per chord and gesture nobody can
## rebind, as `[title, [declaration, ...]]` for [SaShortcutGroups].
func _row_groups() -> Array:
    var groups: Array = []
    for group: Array in GROUPS:
        var rows: Array[Callable] = []
        for action: StringName in actions_for(String(group[0])):
            rows.append(_declare_row.bind(action))
        for chord: Array in KEYCODE_CHORDS:
            if String(chord[0]) == String(group[1]):
                rows.append(_declare_fixed_row.bind(String(chord[1]), String(chord[2])))
        if not rows.is_empty():
            groups.append([String(group[1]), rows])
    var gestures: Array[Callable] = []
    for gesture: Array in GESTURES:
        gestures.append(_declare_fixed_row.bind(String(gesture[1]), tr(String(gesture[0]))))
    groups.append(["Gestures", gestures])
    return groups


## The chord shown on *action*'s first button, empty when the row is not there.
##
## The first and not the only one, because a caller that wants one chord wants
## the one the command's own file names first. `chords_shown` is what a row
## answers with when it has more than one.
func chord_shown(action: StringName) -> String:
    var buttons: Array = _chord_buttons.get(action, [])
    return (buttons[0] as Button).text if not buttons.is_empty() else ""


## Every chord the row for *action* is showing, in the order the command answers
## them. What a capture and a suite read where `chord_shown` cannot say that the
## numpad chord is there too.
func chords_shown(action: StringName) -> Array[String]:
    var out: Array[String] = []
    for button: Button in _chord_buttons.get(action, []):
        out.append(button.text)
    return out


## Whether *action*'s row is one the current search leaves showing. The search
## is the only thing that hides a row, so this is what a test asks instead of
## hunting for an unnamed node.
func row_shown(action: StringName) -> bool:
    var row := _rows_by_action.get(action, null) as Control
    return row != null and row.visible


## Gives *action* a chord, repaints the rows it affects, marks whatever now
## clashes, and writes the change where the next launch will find it. What a
## click on a row ends in, and what a test drives.
##
## *index* is which of the command's chords the change is about, and is what the
## button that was clicked carries: that entry of the list is replaced and the
## others are left, because a command with a numpad chord beside a digit row
## chord answers to both and a rebind on one says nothing about the other. The
## default, -1, replaces the whole list, which is what a caller outside a click
## is asking for.
##
## A rebind is saved, rather than moving the `InputMap` alone and being gone at
## the next launch with nothing on screen to say so. It forks a shipped profile,
## the way editing a shipped docker layout forks that.
##
## *move* takes the chord off whatever else answers it first, which is the
## question's first answer. Without it the chord is shared, and both rows say so.
func rebind(action: StringName, chord: String, index: int = -1, move: bool = false) -> void:
    var chords: Array[String] = SaShortcutStore.chords_for(action)
    if index < 0 or chords.is_empty():
        chords = []
        if not chord.is_empty():
            chords.append(chord)
    elif chord.is_empty():
        if index < chords.size():
            chords.remove_at(index)
    elif index < chords.size():
        chords[index] = chord
    var losers := SaShortcutStore.conflicts(chord, action)
    if move:
        SaShortcutStore.release_chord(chord, action)
    SaShortcutStore.set_chords(action, chords)
    _repaint(action)
    for other: String in losers:
        _repaint(StringName(other))
    # A declared pair moves as one, so the partner's row is showing the old
    # chord until it is repainted.
    for partner: StringName in SaShortcutStore.paired_with(action):
        _repaint(partner)
    mark_conflicts()
    _remember()
    _announce()


## The key that landed on *action*'s row, given to it at once when nobody else
## holds it, and otherwise asked about first, naming who does.
##
## Public because a capture step and a suite send a chord the way a key would,
## and the question is the part they are there to see. The row shows the chord
## the store holds while the question is up, because nothing has moved yet.
func offer(action: StringName, chord: String, index: int = -1) -> void:
    _dismiss_question()
    var taken := SaShortcutStore.conflicts(chord, action)
    if chord.is_empty() or taken.is_empty():
        rebind(action, chord, index)
        return
    _repaint(action)
    var holders := SaShortcutStore.holders(chord, action)
    var who := SaShortcutRows.listed(holders, _tools, _filters, _commands)
    var mover := label_for(String(action), _tools, _filters, _commands)
    var text := tr("%s is already used by %s. Use it for %s instead?") % [chord, who, mover]
    question = SaMessage.confirm(
        self,
        tr("%s is already used") % chord,
        text,
        PackedStringArray([tr("Use for %s") % mover, tr("Share"), tr("Cancel")]),
        _on_offer_answered.bind(action, chord, index),
        ANSWER_CANCEL,
        ANSWER_MOVE
    )


## What the question heard. Escape and the close button answer Cancel, which is
## the row left as it was.
func _on_offer_answered(answer: int, action: StringName, chord: String, index: int) -> void:
    question = null
    match answer:
        ANSWER_MOVE:
            rebind(action, chord, index, true)
        ANSWER_SHARE:
            rebind(action, chord, index)
        _:
            _repaint(action)


## Takes the chord *index* of *action* off it, or every chord for the default
## -1, repaints the row and writes the change where the next launch will find it.
## What Backspace or Delete does in a capture and what the row's Clear does.
##
## A command with no chord is left as it is and nothing is written: a clear that
## changed nothing would fork a shipped profile into a copy of itself.
func clear(action: StringName, index: int = -1) -> void:
    if SaShortcutStore.chords_for(action).is_empty():
        _repaint(action)
        return
    rebind(action, "", index)
    SaMessage.notice(tr("Cleared the shortcut of %s.") % label_for(String(action), _tools, _filters, _commands))


## Answers a question that is still up Cancel, which is the row left as it was.
##
## A second capture and a second question both begin while the first is on
## screen, because the question is a window of its own and not a modal one. The
## page held only the last, so the first was a window nothing referred to, and
## Escape answered whichever had the keyboard: a press of Backspace and then
## Delete left "Delete is taken" still up in `open_dialogs` after it.
##
## Through the Cancel button, the press Escape and the close button answer with,
## rather than by hiding the window: a window outside a tree does not say it was
## hidden, and the answer is what clears `question`.
func _dismiss_question() -> void:
    if question != null and is_instance_valid(question):
        question.buttons[ANSWER_CANCEL].pressed.emit()


## Puts *action* back to what the profile the active one was forked from says,
## or to the shipped chord when that is silent about it, and writes the result
## where the next launch will find it, the way a rebind does.
##
## The source rather than the active profile, because the active one is usually
## a fork holding the very edit this button is offering to undo.
func reset_action(action: StringName) -> void:
    SaShortcutStore.set_chords(action, _reset_chords(action))
    _repaint(action)
    mark_conflicts()
    _remember()
    _announce()


## The chords [method reset_action] puts *action* back to. The one check both
## Reset and its dimming read, so a row whose chords already are these offers no
## Reset that would do nothing.
func _reset_chords(action: StringName) -> Array:
    var overrides := _reset_overrides if not _reset_overrides.is_empty() else _read_reset_overrides()
    var action_name := String(action)
    return overrides.get(action_name, SaShortcutStore.defaults().get(action_name, []))


## The overrides of the profile the active one comes from, what Reset reads.
func _read_reset_overrides() -> Dictionary:
    return SaShortcutStore.load_profile(SaShortcutStore.source_profile(active_profile()))


## Whether *action* already holds the chords Reset would give it.
func at_reset(action: StringName) -> bool:
    var now: Array = []
    for chord: String in SaShortcutStore.chords_for(action):
        now.append(chord)
    var then: Array = []
    for chord: Variant in _reset_chords(action):
        then.append(String(chord))
    return now == then


## Saves the edit into the profile it belongs in and puts the dropdown on it.
##
## Called after a change a painter made rather than after one they chose from
## the dropdown: switching profiles and Reset All both put the map back to what
## a profile already says, and forking there would name a profile after an edit
## nobody made.
func _remember() -> void:
    # Read before the store writes: `remember_edit` moves the setting, so
    # asking afterwards is asking what it just set.
    var was := active_profile()
    if SaShortcutStore.remember_edit() != was:
        _refresh_profiles()


## Colours the rows whose chord another command also answers to, and clears the
## rest. The line under the row says who else holds the key and which of them a
## press goes to, because "conflict" without a name is not something a painter
## can act on, and a tooltip was the only place the name was.
##
## Two commands the router answers in one branch are not a clash and are not
## marked, which is `SaShortcutStore.PAIRS`. The Eraser tool and the brush's
## eraser toggle were once both painted in the drag colour on a page opened to
## rebind something else entirely.
func mark_conflicts() -> void:
    _mark_conflicts_of(_chord_buttons.keys(), SaShortcutStore.all_conflicts())


## [method mark_conflicts] for *actions* alone, with *clashes* read once.
func _mark_conflicts_of(actions: Array, clashes: Dictionary) -> void:
    for action: StringName in actions:
        if not _chord_buttons.has(action):
            continue
        var others: Array = clashes.get(String(action), [])
        var names: Array[String] = []
        for other: String in others:
            names.append(label_for(other, _tools, _filters, _commands))
        for button: Button in _chord_buttons[action]:
            if names.is_empty():
                button.remove_theme_color_override("font_color")
                button.tooltip_text = tr(CHORD_TIP)
                continue
            button.add_theme_color_override("font_color", SaTheme.palette.border_drag)
            button.tooltip_text = tr("Also used by %s.") % ", ".join(names)
        var line := _clash_lines.get(action, null) as Label
        if line != null:
            line.text = clash_line(action) if not names.is_empty() else ""
            line.visible = not line.text.is_empty()


## What the line under *action*'s row says: for each of its chords another
## command also answers to, every holder, a pair's two halves included, and
## which of them a press goes to. Empty when nothing clashes.
##
## Every holder rather than `conflicts`' clashing ones, because the Brush put on
## E clashes with the Eraser and its toggle, and the two are one gesture that
## `conflicts` leaves out of each other's list.
func clash_line(action: StringName) -> String:
    var lines: Array[String] = []
    for chord: String in SaShortcutStore.chords_for(action):
        if SaShortcutStore.conflicts(chord, action).is_empty():
            continue
        var holders := SaShortcutStore.holders(chord, action)
        var line := tr("%s is also used by %s.") % [chord, SaShortcutRows.listed(holders, _tools, _filters, _commands)]
        var everyone: Array = [String(action)]
        everyone.append_array(holders)
        var first := SaShortcutRows.first_to_answer(everyone, _commands, _tools)
        if first == action:
            line += " " + tr("%s runs this command.") % chord
        elif not String(first).is_empty():
            line += " " + tr("%s runs %s.") % [chord, label_for(String(first), _tools, _filters, _commands)]
        lines.append(line)
    return "\n".join(lines)


## The actions the page is showing a conflict on. What a test reads.
func conflicting_actions() -> Array[StringName]:
    var out: Array[StringName] = []
    for action: StringName in _chord_buttons:
        for button: Button in _chord_buttons[action]:
            if button.has_theme_color_override("font_color"):
                out.append(action)
                break
    return out


## The profile the settings name, as a name this page knows. An older settings
## file says "default", which is the shipped map under its old name.
func active_profile() -> String:
    var stored := SaSettings.shortcuts_profile
    if stored.is_empty() or stored == "default" or not _profiles.has(stored):
        return SaShortcutStore.DEFAULT_PROFILE
    return stored


## The row's box of chord buttons and its reset, filled from the store.
func _declare_row(block: SaPageSection, action: StringName) -> void:
    # A flow rather than a row, so a command with several long chords wraps
    # them under each other instead of widening the page past its pane. The
    # four chords of Increase Interface Scale made the page 851 wide in a pane
    # of 747, with a sideways bar and the profile and search fields cut.
    var box := HFlowContainer.new()
    box.name = "ChordRow"
    box.add_theme_constant_override(&"h_separation", SaUI.px(6))
    box.add_theme_constant_override(&"v_separation", SaUI.px(6))
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _fill_row(action, box)
    # The chords and, under them, the line a clash writes, in the one control
    # the row is handed, so the line sits under the keys it is about.
    var column := VBoxContainer.new()
    column.name = "ChordColumn"
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_child(box)
    var clash := SaMake.label(column, "ClashLine", "")
    clash.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    clash.add_theme_color_override("font_color", SaTheme.palette.border_drag)
    clash.visible = false
    _clash_lines[action] = clash
    block.custom(label_for(String(action), _tools, _filters, _commands), column).named(StringName(CHORD_KEY + String(action)))


## Fills *box* with one button per chord *action* answers and its reset, and
## records them under the action.
##
## A function rather than the body of the declaration, because a rebind changes
## how many chords a command has: the row is redrawn from the store wherever it
## changes rather than keeping the shape it was first declared with.
##
## **No fixed width per chord.** The buttons are as wide as the chords they
## name, and a command with three of them would overflow the column if each one
## asked for the width of a lone chord.
func _fill_row(action: StringName, box: HFlowContainer) -> void:
    for child: Node in box.get_children():
        box.remove_child(child)
        child.queue_free()
    var buttons: Array[Button] = []
    var chords := SaShortcutStore.chords_for(action)
    if chords.is_empty():
        # A command nobody has bound keeps a button that reads so, and is what
        # a rebind from the row writes into. Indexing an empty array is what
        # made dropping the chordless actions look necessary rather than tidy.
        buttons.append(_chord_button(action, -1, tr(NO_CHORD_TEXT), box))
    else:
        for index in chords.size():
            buttons.append(_chord_button(action, index, String(chords[index]), box))
    var reset := SaMake.button(box, "Reset_" + String(action), tr("Reset"))
    reset.pressed.connect(reset_action.bind(action))
    reset.disabled = at_reset(action)
    var clear_word := tr("Clear", "clear a command's shortcuts")
    var clear_button := SaMake.button(box, "Clear_" + String(action), clear_word, tr("Remove all shortcuts from this command."))
    clear_button.pressed.connect(clear.bind(action, -1))
    clear_button.disabled = chords.is_empty()
    _chord_buttons[action] = buttons
    _row_boxes[action] = box


## One chord's button. *index* is the chord's place in the list the row is
## showing and is what a click hands back, so the key that lands replaces that
## chord and leaves the others. -1 is the button of a command that answers to
## nothing, which a rebind treats as the whole list, an empty one.
func _chord_button(action: StringName, index: int, text: String, box: HFlowContainer) -> Button:
    var button := SaMake.button(box, "Chord_" + String(action) + ("" if index < 0 else "_%d" % (index + 1)), text)
    button.pressed.connect(_on_chord_pressed.bind(action, index))
    return button


## A row for something that cannot be rebound: Tab, and the gestures.
func _declare_fixed_row(block: SaPageSection, label_text: String, chord_text: String) -> void:
    var shown := SaMake.label(null, "FixedChord", chord_text)
    shown.custom_minimum_size = Vector2(SaUI.px(140), 0)
    var key := StringName(FIXED_KEY + label_text.to_snake_case())
    _fixed_rows[key] = [label_text, chord_text]
    block.custom(label_text, shown).named(key)


## Starts the capture on *action*, the way a click on its chord button does.
##
## Public because Preferences is an embedded subwindow and an injected click
## does not route into one, so a capture has no other way to put a row into the
## state where the next key it sends becomes that row's chord.
func begin_capture(action: StringName, index: int = -1) -> void:
    if _chord_buttons.has(action):
        _on_chord_pressed(action, index)


## Starts the capture from a click on *action*'s button for chord *index*, which
## is the index the button carries and the entry the key that lands replaces.
func _on_chord_pressed(action: StringName, index: int = -1) -> void:
    _dismiss_question()
    if not String(listening).is_empty():
        _repaint(listening)
    _listen_to(action, index)
    var btn := _chord_button_at(action, index)
    if btn == null:
        return
    btn.text = tr(LISTENING_TEXT)
    # A page not yet in a tree has nothing to take the focus, and asking anyway
    # is an engine error rather than a no-op.
    if btn.is_inside_tree():
        btn.grab_focus()


## The button showing *action*'s chord at *index*, or the one button of a
## command that answers to nothing. Null when the action has no row.
func _chord_button_at(action: StringName, index: int) -> Button:
    var buttons: Array = _chord_buttons.get(action, [])
    if buttons.is_empty():
        return null
    return buttons[index] if index >= 0 and index < buttons.size() else buttons[0]


## The one place `listening` is written, because the router has to stand down
## for exactly as long as a row is waiting. A window emits `window_input` before
## it pushes the event into its own tree, so without this the chord being
## captured fires its own action on the way past.
func _listen_to(action: StringName, index: int = -1) -> void:
    listening = action
    _listening_index = index
    ShortcutRouter.capture_in_progress = not String(action).is_empty()


## A Preferences window closed while a row was waiting must not leave the app
## deaf to every chord.
func _exit_tree() -> void:
    _listen_to(&"")


## The key that lands while a row is listening becomes that row's chord.
##
## `_input` rather than the button's own `gui_input`, because a chord with Ctrl
## or Alt in it is eaten by the shortcut router before a focused Button sees it,
## and a page that cannot take Ctrl+Z is not an editor.
##
## Standing the router down is not this function's job either, and cannot be:
## a window emits `window_input` before it pushes the event into its own tree,
## so the router has already answered the chord by the time this runs. That is
## what `_listen_to` is for.
func _input(event: InputEvent) -> void:
    if String(listening).is_empty():
        return
    var key := event as InputEventKey
    if key == null or not key.pressed or key.echo:
        return
    var viewport := get_viewport()
    if viewport != null:
        viewport.set_input_as_handled()
    var action := listening
    var index := _listening_index
    if key.keycode in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]:
        # A modifier on its own is the painter still reaching for the key.
        return
    _listen_to(&"")
    if key.keycode == KEY_ESCAPE:
        _repaint(action)
        return
    if _clears_a_chord(key):
        clear(action, index)
        return
    offer(action, SaShortcutStore.chord_of_event(key), index)


## Whether *key* is Backspace or Delete with nothing held, the two that take a
## chord off a row instead of becoming one. With a modifier they are chords like
## any other, so Ctrl+Delete can still be bound.
static func _clears_a_chord(key: InputEventKey) -> bool:
    var code := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
    if key.ctrl_pressed or key.shift_pressed or key.alt_pressed or key.meta_pressed:
        return false
    return code == KEY_BACKSPACE or code == KEY_DELETE


## Redraws *action*'s row from the store, so its buttons match what the command
## answers to now. A rebind can add or drop a chord in the middle of the list,
## which is why this refills the box rather than writing one button's text.
func _repaint(action: StringName) -> void:
    var box := _row_boxes.get(action, null) as HFlowContainer
    if box == null:
        return
    _fill_row(action, box)


## A chord moved, so every surface that prints one has to say so again. The
## menus follow the command registry, the toolbox tooltips follow the bus.
func _announce() -> void:
    EventBus.shortcuts_changed.emit()
    if SaSettings.shortcuts_profile != active_profile():
        SaSettings.shortcuts_profile = active_profile()


func _refresh_profiles() -> void:
    if profile_option == null:
        return
    _profiles = SaShortcutStore.list_profiles()
    var choices: Array = []
    for profile: String in _profiles:
        choices.append({"id": profile, "label": profile})
    profile_option.set_choices(choices)
    if not profile_option.select_value(active_profile()) and not _profiles.is_empty():
        profile_option.select_value(_profiles[0])
    if delete_button != null:
        delete_button.disabled = SaShortcutStore.is_shipped(active_profile())
    var back_row := page.row(&"start_again") if page != null else null
    if back_row != null and back_row.control is Button:
        (back_row.control as Button).text = tr("Back to %s") % SaShortcutStore.shipped_source(active_profile())


func _on_profile_chosen(profile: String) -> void:
    if not _profiles.has(profile):
        return
    var timer := SaShortcutSwitchTimer.new(profile)
    timer.part("the setting")
    SaSettings.shortcuts_profile = profile
    timer.part("the input map")
    SaShortcutStore.apply_profile(profile)
    timer.part("the menus and tooltips")
    EventBus.shortcuts_changed.emit()
    timer.part("the page's rows")
    _redraw_after_switch()
    timer.done()


## The rows redrawn in place after a switch, each row refilled only where its
## chords changed, since a switch moves chords and leaves the commands. Rebuilt
## whole, the page made its 312 rows again for every switch, a second of the
## app's frame on a busy machine. A switch that brought a
## command in or took one away rebuilds the page as before.
func _redraw_after_switch() -> void:
    var actions: Array[StringName] = []
    for group: Array in GROUPS:
        actions.append_array(actions_for(String(group[0])))
    if actions.size() != _row_boxes.size() or actions.any(func(action: StringName) -> bool: return not _row_boxes.has(action)):
        refresh()
        return
    _listen_to(&"")
    _refresh_profiles()
    _reset_overrides = _read_reset_overrides()
    for action: StringName in actions:
        var box := _row_boxes[action] as HFlowContainer
        var chords := SaShortcutStore.chords_for(action)
        if chords_shown(action) != (chords if not chords.is_empty() else [tr(NO_CHORD_TEXT)] as Array[String]):
            _fill_row(action, box)
            continue
        var reset := box.get_node_or_null(NodePath("Reset_" + String(action))) as Button
        if reset != null:
            reset.disabled = at_reset(action)
    _reset_overrides = {}
    mark_conflicts()
    _apply_search(search.text if search != null else "")


func _on_save_as() -> void:
    var wanted := save_as_name.text.strip_edges()
    if wanted.is_empty() or SaShortcutStore.is_shipped(wanted):
        return
    if SaShortcutStore.save_profile(wanted) >= 0:
        SaSettings.shortcuts_profile = wanted
        save_as_name.text = ""
        refresh()


func _on_delete() -> void:
    var current := active_profile()
    if SaShortcutStore.is_shipped(current):
        return
    SaShortcutStore.delete_profile(current)
    SaSettings.shortcuts_profile = SaShortcutStore.DEFAULT_PROFILE
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    EventBus.shortcuts_changed.emit()
    refresh()


## Start again: the shipped profile the active one comes from, applied and made
## the active one, with every profile of the painter's left on disk. Public
## because Preferences is an embedded window and a capture step cannot click
## into one.
##
## Not the active profile, which after any edit is the fork holding that edit.
## Applying the fork gave the edit back and took the chord it claimed off the
## command that ships with it, so Start again after Redo was put on Ctrl+Z left
## Undo with no chord at all.
func start_again() -> void:
    var shipped := SaShortcutStore.shipped_source(active_profile())
    SaSettings.shortcuts_profile = shipped
    SaShortcutStore.apply_profile(shipped)
    EventBus.shortcuts_changed.emit()
    refresh()


## Switches to *profile* the way choosing it in the dropdown would. Public so
## a capture step can drive it: Preferences is an embedded subwindow and an
## injected click cannot open the popup inside one.
func select_profile(profile: String) -> void:
    _on_profile_chosen(profile)


func _on_import_krita_pressed() -> void:
    var filters := PackedStringArray(["*.shortcuts ; Krita Shortcuts"])
    SaFilePicker.open(self, SaFilePicker.Mode.OPEN_FILE, filters, import_krita_file)


## Imports *path*, a Krita `.shortcuts` export, as a profile named after the
## file, and names in the corner each chord it left out because no key here
## reads it. Public so the picker's `file_selected` and a capture step both
## reach it, since a native file dialog is as unreachable from a scenario.
func import_krita_file(path: String) -> void:
    var reading := SaShortcutStore.import_krita(path)
    var left_out := PackedStringArray()
    for action: String in reading.unread:
        left_out.append("%s (%s)" % [label_for(action, _tools, _filters, _commands), ", ".join(reading.unread[action])])
    if not left_out.is_empty():
        EventBus.corner_notice.emit(tr("Some Krita shortcuts use keys Sara does not support: %s.") % ", ".join(left_out))
    if reading.profile.is_empty():
        push_warning("SaShortcutsPage: '%s' gave no profile this build could save." % path)
        return
    EventBus.shortcuts_changed.emit()
    refresh()


## Filters the rows to *text*. Public because the field cannot be typed into
## from a capture: Preferences is an embedded subwindow and an injected key
## does not route into one.
func filter(text: String) -> void:
    search.text = text
    _apply_search(text)


func _on_search_changed(text: String) -> void:
    _apply_search(text)


## Hides the rows that do not match, and the sections left with none. A search
## that matches nothing leaves the page empty rather than showing everything,
## because "no results" is an answer and "all of them" is not, and says so: an
## empty page under "ctrl+j" read as a page that had not finished drawing.
func _apply_search(text: String) -> void:
    var needle := text.strip_edges().to_lower()
    var any := false
    for action: StringName in _rows_by_action:
        var row := _rows_by_action[action] as Control
        row.visible = needle.is_empty() or _row_matches(action, needle)
        any = any or row.visible
    for title: String in _section_boxes:
        var section := _section_boxes[title] as Control
        section.visible = needle.is_empty() or _section_has_visible_row(section)
    nothing_matches.visible = not any and not needle.is_empty()


## Whether a row answers *needle*, which is already lowercase and trimmed, by its
## words or by the keys it shows (`SaShortcutRows.chord_answers`).
##
## The action id is searched beside the label, because the label is what the row
## is called and not what a painter looks for: the brush size keys are labelled
## "Larger brush" and "Smaller brush", so a search for "size" or "brush size" by
## label alone empties a page that has both rows on it. The underscores come out
## so "brush size" reaches `brush_size_increase`. A fixed row has no action, and
## is read by its words alone, so "fixed" does not find every one of them.
##
## **A lone character is a key and not a word**: "m" read as a word lists every
## row whose name has an m in it, when a painter typing one letter asks what
## that key does.
func _row_matches(action: StringName, needle: String) -> bool:
    var fixed: Array = _fixed_rows.get(action, [])
    var chords: Array = SaShortcutStore.chords_for(action) if fixed.is_empty() else [fixed[1]]
    if SaShortcutRows.chord_answers(chords, needle):
        return true
    if needle.length() == 1:
        return false
    if not fixed.is_empty():
        return String(fixed[0]).to_lower().contains(needle)
    if label_for(String(action), _tools, _filters, _commands).to_lower().contains(needle):
        return true
    return String(action).replace("_", " ").to_lower().contains(needle)


func _section_has_visible_row(section: Control) -> bool:
    for action: StringName in _rows_by_action:
        var row := _rows_by_action[action] as Control
        if row.visible and section.is_ancestor_of(row):
            return true
    return false
