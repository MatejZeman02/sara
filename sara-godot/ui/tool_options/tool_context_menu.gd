## The canvas right-click menu: the permanent tool's options over the same
## SaOptionSpec list the bar builds from, and the commands that asked to be
## here.
##
## Every tool tests for the left button, so the tool machine announces a right
## press rather than handing it to the tool, and this popup answers, reading and
## writing through the bar so a check item here and a toggle on the bar move the
## same field. A menu has no slider, so the FLOAT and INT rows stay on the bar
## and this offers the switches and the choices: erase, the pressure toggles,
## the stabilizer, the blend mode, the eyedropper's square and merged flag, and
## the three symmetry commands.
##
## **Every selection tool shows one menu**, the rows of [SelectionMenuRows]:
## the Marquee, Ellipse Select, the Lasso, the Polygonal Lasso, the Magic Wand,
## Select Subject and Object Selection, and a module's tool that makes a
## selection the same way, offer the same rows in the same order rather than
## each its own options. The tool's Feather is the one number there, a row that
## says the value and opens a radius dialog writing through the bar, so the
## docker's slider and the row read the same pixels.
##
## **An `SaChoicePopup`** rather than a `PopupMenu`, for three of the choice
## list's rules. A choice is a heading with its rows under it rather than a
## submenu per spec, because a menu with no submenus is one column a painter can
## read down. A switch is a row whose box marks without closing the list rather
## than a check item, so several switches are several presses rather than
## several openings. And every row is a Control, so a note can be made on one
## and the dump says what a painter sees: the rows are in `choice_lists` under
## `ToolContextMenu` rather than in `open_menus`.
##
## The int ids `_on_id_pressed` takes are kept beside the row ids the popup uses,
## because they are the menu's own numbering and a caller that has one has no
## business knowing how a row is named.
@tool
class_name ToolContextMenu
extends SaChoicePopup

## Command ids sit above this, option rows below it.
const ID_COMMAND_BASE: int = 1000

## The row of the tool's own Feather.
const FEATHER_ROW: StringName = &"feather_option"

## The window the row opens, under a name of its own so a scenario step finds it
## and not Select > Feather...'s.
const FEATHER_DIALOG: String = "FeatherOptionDialog"

var bar: ToolOptionsBar = null
var commands: SaCommandRegistry = null

## What each option row writes, in menu order: {"key": StringName, "value":
## Variant}. A BOOL row's value is what pressing it writes, an ENUM row's is its
## choice. Named for the values and not for the rows, because `SaChoicePopup`
## keeps the rows themselves under `_rows` and a subclass may not take that name.
var _option_values: Array = []
## Command row id -> command id.
var _command_rows: Array[StringName] = []
## The popup's row id for each of the two lists above, in the same order, so a
## press on a row finds the number the menu knows it by.
var _option_row_ids: Array[StringName] = []
var _command_row_ids: Array[StringName] = []
var _machine: ToolMachine = null
## The spec behind the Feather row while the shown tool has one, else null.
var _feather_spec: SaOptionSpec = null
var _feather_dialog: SaRadiusDialog = null
## The frame the menu last went away in, or -1. A right press outside an open
## menu closes it before the same press reaches the tool machine, which would
## open it again at once, and the painter asked for the second right click to
## close it and open nothing.
var _hidden_at_frame: int = -1


func _init() -> void:
    super()
    name = "ToolContextMenu"
    chosen.connect(_on_row_chosen)
    marked.connect(_on_row_marked)
    popup_hide.connect(_note_hidden)


## Follows *machine*'s right presses and builds from *options_bar*.
func bind(options_bar: ToolOptionsBar, machine: ToolMachine) -> void:
    bar = options_bar
    if _machine != null and _machine.context_menu_requested.is_connected(open_at):
        _machine.context_menu_requested.disconnect(open_at)
    _machine = machine
    if machine != null and not machine.context_menu_requested.is_connected(open_at):
        machine.context_menu_requested.connect(open_at)


## Pops the menu at *global_position*, which is in the main window's logical
## coordinates the way a gui_input event reports it.
##
## A press while the menu is open, or in the frame it closed in, closes it and
## opens nothing, so the second right click puts the menu away and the third
## opens it again.
func open_at(global_position: Vector2) -> void:
    if visible:
        hide()
        return
    if _hidden_at_frame >= 0 and Engine.get_process_frames() - _hidden_at_frame <= 1:
        return
    rebuild()
    if row_ids().is_empty() or not is_inside_tree():
        return
    # The scale is taken by `open_under`, the one place a list opened at a
    # point asks the one writer of the UI scale for it (hard rule 7).
    var window := get_parent().get_window() if get_parent() != null else null
    var at := SaPopupRect.at_window_point(window, global_position) if window != null else Vector2i(global_position)
    open_under(null, Vector2(at))


func _note_hidden() -> void:
    _hidden_at_frame = Engine.get_process_frames()


## Fills the menu from the shown tool's specs and the context commands.
## Public so a test can look at the rows without popping a Window.
func rebuild() -> void:
    clear()
    _option_values.clear()
    _command_rows.clear()
    _option_row_ids.clear()
    _command_row_ids.clear()
    _feather_spec = null
    if bar == null:
        return
    var descriptor := _shown_descriptor()
    if SelectionMenuRows.makes_a_selection(descriptor):
        _add_selection(descriptor)
        _mark_the_chosen_rows()
        return
    for spec: SaOptionSpec in bar.shown_specs():
        match spec.kind:
            SaOptionSpec.Kind.BOOL:
                _add_switch(spec)
            SaOptionSpec.Kind.ENUM:
                _add_choices(spec, spec.choices)
            SaOptionSpec.Kind.BLEND_MODE:
                _add_choices(spec, _blend_choices())
            _:
                pass
    _add_commands()
    _mark_the_chosen_rows()


## The descriptor of the tool the bar shows, or null.
func _shown_descriptor() -> SaToolDescriptor:
    var machine := bar.target_tool_machine
    return machine.get_descriptor(bar.shown_tool_id()) if machine != null else null


## A switch: one row carrying the option's own icon, whose box says where the
## option stands. The box marks and leaves the list open, because a painter
## turning two switches on is one opening of the menu and not two, and a press on
## the label presses the box, so it flips and leaves the list open too.
func _add_switch(spec: SaOptionSpec) -> void:
    var stands_at := bool(_read(spec.key))
    var row_id := StringName(spec.key)
    add_row(row_id, tr(spec.label), true, stands_at, spec.icon)
    _option_values.append({"key": spec.key, "value": not stands_at})
    _option_row_ids.append(row_id)


## A choice: the spec's label as a heading and its choices as the rows under it,
## where a `PopupMenu` had a submenu per spec. The group's rule is no submenus,
## and the reason is the blend list's: a long column with headings is read down
## once, and a submenu is a second gesture per look.
func _add_choices(spec: SaOptionSpec, choices: Array) -> void:
    if choices.is_empty():
        return
    if not row_ids().is_empty():
        add_gap()
    add_section(tr(spec.label))
    for choice: Dictionary in choices:
        var row_id := StringName("%s_%s" % [spec.key, str(choice.get("id"))])
        add_row(row_id, tr(String(choice.get("label", ""))))
        _option_values.append({"key": spec.key, "value": choice.get("id")})
        _option_row_ids.append(row_id)


## The blend registry's list, labelled for the document the bar shows.
func _blend_choices() -> Array:
    var out: Array = []
    var registry := bar.options.binding.blend_registry
    if registry == null:
        return out
    var doc := bar.options.binding.document()
    for descriptor: SaBlendModeDescriptor in registry.list_ui_entries(true):
        out.append({"id": descriptor.id, "label": descriptor.label_for(doc.color_space if doc != null else null)})
    return out


## The menu every selection tool shares, in [SelectionMenuRows]' order: under
## a Selection heading the four modes and the Feather the next shape is drawn
## with, and under a line the commands that act on the selection that stands.
## A mode or a Feather the tool in hand does not declare is a dimmed row, and
## every command is dimmed while there is no selection, so the rows stand where
## they stood under every selection tool.
func _add_selection(descriptor: SaToolDescriptor) -> void:
    var feather := SelectionMenuRows.spec_of(descriptor, SelectionMenuRows.FEATHER_KEY)
    _feather_spec = feather if feather != null and feather.kind == SaOptionSpec.Kind.FLOAT else null
    var no_mode := SelectionMenuRows.spec_of(descriptor, SelectionMenuRows.MODE_KEY) == null
    add_section(tr("Selection"))
    for entry: Array in SelectionMenuRows.MODES:
        var row_id := StringName("%s_%d" % [SelectionMenuRows.MODE_KEY, entry[0]])
        add_row(row_id, tr(entry[1]), false, false, "", "", no_mode)
        _option_values.append({"key": SelectionMenuRows.MODE_KEY, "value": entry[0]})
        _option_row_ids.append(row_id)
    if _feather_spec != null:
        var pixels := feather_pixels()
        var words := tr_n("Feather for the next selection: %d px...", "Feather for the next selection: %d px...", pixels)
        add_row(FEATHER_ROW, words % pixels)
    else:
        add_row(FEATHER_ROW, tr("Feather for the next selection..."), false, false, "", "", true)
    add_gap()
    var idle := not _selection_stands()
    for command: SaCommandDescriptor in SelectionMenuRows.commands_in(commands):
        _add_command(command, true, idle)


## Whether the document the bar shows has a selection for a command to act on.
func _selection_stands() -> bool:
    var document := bar.options.binding.document()
    return document != null and document.selection != null and document.selection.active


## The commands that asked for this menu, under a line of their own, each with
## the chord it answers to at the row's right. The chord comes from the store
## rather than from the menu files, so a rebind moves what this row shows
## without a line here.
func _add_commands() -> void:
    var listed := _listed_commands()
    if listed.is_empty():
        return
    if not row_ids().is_empty():
        add_gap()
    for descriptor: SaCommandDescriptor in listed:
        _add_command(descriptor)


func _listed_commands() -> Array:
    return commands.list_context_commands() if commands != null else []


## One command's row, dimmed and refusing the press while its `enabled` says a
## press would do nothing, the way its row on the menu bar is, or while *idle*
## says the menu knows it would. *under_heading* reads the menu words where there
## are some, "Feather...", because the row stands under the Selection heading
## the way a menu bar row stands under its menu.
func _add_command(descriptor: SaCommandDescriptor, under_heading: bool = false, idle: bool = false) -> void:
    var row_id := StringName("cmd_%s" % descriptor.id)
    var dimmed := idle or (descriptor.enabled.is_valid() and not SaTyped.flag(descriptor.enabled.call()))
    var words := descriptor.label if under_heading and not descriptor.label.is_empty() else descriptor.title
    add_row(row_id, tr(words), false, false, "", _chord_of(descriptor), dimmed)
    _command_rows.append(descriptor.id)
    _command_row_ids.append(row_id)


## The tool's own Feather in the document's pixels, as the docker's slider shows
## it, or 0 while the shown tool has none.
func feather_pixels() -> int:
    if _feather_spec == null or bar == null:
        return 0
    return roundi(float(_read(SelectionMenuRows.FEATHER_KEY)) * _pixels_per_unit())


## What one unit of the stored fraction is in the document's pixels.
func _pixels_per_unit() -> float:
    return _feather_spec.display_scale * bar.canvas_min_dimension()


## Opens the radius dialog on the tool's own Feather. Public so a scenario step
## and a suite open it as the row's press does, without a Window to click.
func open_feather_dialog() -> SaRadiusDialog:
    if _feather_spec == null or bar == null or get_parent() == null:
        return null
    if _feather_dialog == null:
        _feather_dialog = SaRadiusDialog.new(FEATHER_DIALOG)
        get_parent().add_child(_feather_dialog)
        _feather_dialog.radius_confirmed.connect(write_feather_pixels)
    var ceiling := _feather_spec.max_value * _pixels_per_unit()
    _feather_dialog.configure("Feather for the Next Selection", feather_pixels(), tr("Feather"), ceiling)
    _feather_dialog.popup_centered()
    return _feather_dialog


## Writes *pixels* as the tool's own Feather, through the bar so the docker's
## slider moves with it and the next selection is drawn with it.
func write_feather_pixels(pixels: int) -> void:
    if _feather_spec == null or bar == null:
        return
    var unit := _pixels_per_unit()
    if unit <= 0.0:
        return
    _write(SelectionMenuRows.FEATHER_KEY, clampf(float(pixels) / unit, _feather_spec.min_value, _feather_spec.max_value))


## The first chord *descriptor*'s action answers to, or "" when it answers to
## none. First and not all of them, because a row's right-hand hint is one line
## and a command with three chords would push the label out of the list.
static func _chord_of(descriptor: SaCommandDescriptor) -> String:
    if String(descriptor.action).is_empty():
        return ""
    var chords := SaShortcutStore.chords_for(descriptor.action)
    return chords[0] if not chords.is_empty() else ""


## The mark on every choice row standing where its own option stands. One pass
## over all of them rather than one call per spec: `set_current_where` writes
## every row on every call, so a second call would clear the first one's mark.
## `current` is left empty on purpose, because a menu of several options has no
## single chosen row for it to name.
func _mark_the_chosen_rows() -> void:
    set_current_where(&"", _row_stands_where_its_option_stands)


func _row_stands_where_its_option_stands(row_id: StringName) -> bool:
    var index := _option_row_ids.find(row_id)
    if index < 0 or bar == null:
        return false
    var row: Dictionary = _option_values[index]
    # A switch's stored value is the flip pressing it writes, so it never equals
    # what the option reads and the mark on it would always be wrong. The box is
    # what says where a switch stands.
    return not (row["value"] is bool) and _read(row["key"]) == row["value"]


## The rows the menu offers, for a test: [{"key", "value"}] in menu order.
func option_rows() -> Array:
    return _option_values.duplicate(true)


func command_rows() -> Array[StringName]:
    return _command_rows.duplicate()


func _on_row_chosen(row_id: StringName) -> void:
    if row_id == FEATHER_ROW:
        open_feather_dialog()
        return
    var command := _command_row_ids.find(row_id)
    if command >= 0:
        _on_id_pressed(ID_COMMAND_BASE + command)
        return
    var option := _option_row_ids.find(row_id)
    if option >= 0:
        _on_id_pressed(option)


## A switch's box moved. The list stays open, and what is written is where the
## box now stands rather than the flip the label would have made, because the
## two disagree the moment a painter presses the box twice.
func _on_row_marked(row_id: StringName, on: bool) -> void:
    var index := _option_row_ids.find(row_id)
    if index < 0 or bar == null:
        return
    var row: Dictionary = _option_values[index]
    if not (row["value"] is bool):
        return
    _write(row["key"], on)
    _option_values[index]["value"] = not on


func _on_id_pressed(id: int) -> void:
    if id >= ID_COMMAND_BASE:
        var index := id - ID_COMMAND_BASE
        if index < _command_rows.size() and commands != null:
            commands.execute(_command_rows[index])
        return
    if id < 0 or id >= _option_values.size() or bar == null:
        return
    var row: Dictionary = _option_values[id]
    _write(row["key"], row["value"])


## Where *key* stands on the tool that owns it, the one way every row of this
## menu reads its option, so a switch, a choice and the Feather read as the bar.
func _read(key: StringName) -> Variant:
    return bar.read_option(key)


## Writes *value* behind *key* through the bar, the one way every row of this
## menu writes, so the bar and the docker show what a press here set.
func _write(key: StringName, value: Variant) -> void:
    bar.write_option(key, value)
