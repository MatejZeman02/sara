## The Select menu: all, deselect, reselect, invert, colour range, feather, border, grow,
## shrink, transform and the quick mask, a list of commands. The first four and the quick mask are the
## skeleton's, with their chords, and the other five are commands that open a dialog this menu
## holds: feather, border, grow and shrink each a small one for the radius in pixels, one
## instance apiece so each remembers its own last value rather than sharing another's, and
## colour range one that remembers its settings the same way.
class_name SaSelectMenu
extends SaMenu

const RadiusDialogScript = preload("res://ui/dialogs/select_radius_dialog.gd")
const ColorRangeDialogScript = preload("res://ui/dialogs/color_range_dialog.gd")

const ID_ALL := 200
const ID_NONE := 201
const ID_INVERT := 202
const ID_QUICK_MASK := 203
const ID_COLOR_RANGE := 204
const ID_RESELECT := 205
## Transform Selection, the base module's command, left out when no module registered it.
const ID_TRANSFORM := 206
const ID_FEATHER := 300
const ID_BORDER := 400
const ID_GROW := 500
const ID_SHRINK := 600
## The first id of the rows a module asked for.
const MODULE_ROW_BASE := 700

## The radius commands by the key `SaMenuCommands` opens each with, and the
## word its dialog is titled with.
const RADIUS_WORDS: Dictionary[StringName, String] = {
    &"feather": "Feather",
    &"border": "Border",
    &"grow": "Grow",
    &"shrink": "Shrink",
}

## The name each one's window answers to in the tree. Feather's is the one all
## of them had at first, which older scenarios still ask for. The
## others have their own, because a second window of one name joins the tree
## under a name Godot makes up, and a step aimed at the name found Feather's.
const RADIUS_WINDOWS: Dictionary[StringName, String] = {
    &"feather": "RadiusDialog",
    &"border": "BorderDialog",
    &"grow": "GrowDialog",
    &"shrink": "ShrinkDialog",
}

## The undo step each records, by the name the Undo History docker lists.
const RADIUS_TITLES: Dictionary[StringName, String] = {
    &"feather": SaSelection.FEATHER_TITLE,
    &"border": SaSelection.BORDER_TITLE,
    &"grow": SaSelection.GROW_TITLE,
    &"shrink": SaSelection.SHRINK_TITLE,
}

## The radius each opens at before the painter has set one.
const DEFAULT_RADII: Dictionary[StringName, int] = {
    &"feather": 5,
    &"border": 4,
    &"grow": 2,
    &"shrink": 2,
}

var _radius_dialogs: Dictionary[StringName, SaRadiusDialog] = {}
var _radii: Dictionary[StringName, int] = DEFAULT_RADII.duplicate()

## Colour range, which remembers its last settings the way the radius dialogs
## do. The colour is not remembered: it opens on the foreground, which
## is the colour a painter just picked. Apply acts on the canvas it opened over.
var _color_range_dialog: SaColorRangeDialog = null
var _color_range_canvas: SaCanvas = null
var _color_range_fuzziness: float = SaColorRange.DEFAULT_FUZZINESS
var _color_range_merged: bool = true
var _color_range_mode: int = SaSelection.Mode.REPLACE


func _add_items() -> void:
    add_commands(
        [
            [ID_ALL, &"select_all"],
            [ID_NONE, &"select_none"],
            [ID_RESELECT, &"select_reselect"],
            [ID_INVERT, &"select_invert"],
            [ID_COLOR_RANGE, &"select_color_range"],
            LINE,
            [ID_FEATHER, &"select_feather"],
            [ID_BORDER, &"select_border"],
            [ID_GROW, &"select_grow"],
            [ID_SHRINK, &"select_shrink"],
            [ID_TRANSFORM, &"select_transform"],
            LINE,
            [ID_QUICK_MASK, &"select_quick_mask"],
        ]
    )
    _add_module_rows()


## A row for every command a module asked to have in Select, after the quick
## mask. A command whose module is not loaded was never registered, so a Sara
## without that module has none of its rows.
func _add_module_rows() -> void:
    if commands == null:
        return
    var rows := commands.list_select_commands()
    if rows.is_empty():
        return
    add_separator()
    var next_id := MODULE_ROW_BASE
    for descriptor: SaCommandDescriptor in rows:
        add_command(next_id, descriptor.id)
        next_id += 1


## Builds the dialog on first use, one per kind, and reopens it at the radius
## that kind was last set to. *which* is a key of [constant RADIUS_WORDS].
func open_radius_dialog(which: StringName) -> void:
    if not in_tree() or not RADIUS_WORDS.has(which):
        return
    var dialog: SaRadiusDialog = _radius_dialogs.get(which, null)
    if dialog == null:
        dialog = RadiusDialogScript.new(RADIUS_WINDOWS[which])
        host().add_child(dialog)
        dialog.radius_confirmed.connect(_on_radius_confirmed.bind(which))
        _radius_dialogs[which] = dialog
    dialog.configure(RADIUS_WORDS[which], _radii[which])
    dialog.popup_centered()


func _on_radius_confirmed(radius: int, which: StringName) -> void:
    var doc := main_document()
    if doc == null:
        return
    _radii[which] = radius
    var filters: Dictionary[StringName, Callable] = {
        &"feather": doc.selection.feather.apply,
        &"border": SaSelectionFilters.border,
        &"grow": SaSelectionFilters.grow,
        &"shrink": SaSelectionFilters.shrink,
    }
    var selection := doc.selection
    # A Feather sets the selection's live amount, laid over its hard mask, so it
    # replaces the one before it and 0 gives the hard edge back.
    var work: Callable = filters[which].bind(selection, radius, doc.canvas_size, doc.projection.wrapping)
    selection.change(RADIUS_TITLES[which], work)


## Builds the colour range dialog on first use and opens it over *canvas*, the
## main one when null, on the foreground colour and the settings last applied.
## Public so a capture step and a suite can open it without a press.
func open_color_range_dialog(canvas: SaCanvas = null) -> SaColorRangeDialog:
    if not in_tree():
        return null
    if _color_range_dialog == null:
        _color_range_dialog = ColorRangeDialogScript.new()
        host().add_child(_color_range_dialog)
        _color_range_dialog.range_confirmed.connect(_on_color_range_confirmed)
    # The canvas the preview and the hold are on, so Apply chooses on it too.
    _color_range_canvas = canvas if canvas != null else main_canvas()
    var machine := _color_range_canvas.tool_machine() if _color_range_canvas != null else null
    _color_range_dialog.open(SaColors.foreground, _color_range_fuzziness, _color_range_merged, _color_range_mode, true, machine)
    return _color_range_dialog


## Chooses the range in the mode the dialog set, over the merged picture or the
## active layer alone.
func _on_color_range_confirmed(color: Color, fuzziness: float, sample_merged: bool, mode: int) -> void:
    _color_range_fuzziness = fuzziness
    _color_range_merged = sample_merged
    _color_range_mode = mode
    var canvas := _color_range_canvas
    var doc := canvas.document if is_instance_valid(canvas) else null
    if doc == null:
        return
    # A range over the merged picture reads all of it. A document is an easel's.
    canvas.easel.flush()
    var merged: SaTexture = canvas.easel.output if sample_merged or doc.active_layer == null else null
    SaColorRange.new(doc).select(color, fuzziness, mode, merged, doc.active_layer)
