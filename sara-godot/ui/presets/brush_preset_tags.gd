## Making and unmaking a preset's tags: the cell's menu, the name field and the
## question a delete asks.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Out of `brush_presets_chooser.gd`, which owns a grid of pictures and would
## otherwise own three gestures as well. The seam is this: the chooser owns what
## is on screen and which tag it is filtered by, `SaPresetStore` owns what a tag
## is on disk, and this owns the gesture in between, which is the only part a
## painter argues with.
##
## **The gesture is `SaLayerRename`'s, deliberately.** A tag is named in a field
## that appears where the row is rather than in a window: Enter writes it,
## Escape and a lost focus throw it away, and nothing is modal. Sara already
## renames a layer that way, and a second shape for the same act would be a
## second thing to learn. The field is this class's own, so the chooser adds one
## control to its row and never learns what is being typed into it.
##
## **Assigning is a checkable row and never a press-and-close.** Marking several
## tags on one preset is the gesture, and `SaChoicePopup` keeps a list open on a
## check exactly for that. So the menu is opened once and left open while the
## painter ticks, and the library is written per tick rather than on a close: a
## popup dismissed by clicking away never answers, and a write held until then
## would be a write that never happened.
##
## **The same menu offers Convert to**, a row per engine a
## module registered a converter to from the preset's own, under a heading over
## the tags, and nothing at all when no module registers one. A convert is a press and not a
## tick, and it writes a new preset beside the original through the store,
## which is where a converted preset is decided. It is here rather than in a
## menu of its own because the right press on a cell is the one menu a preset
## has, and a second would be a second place to look.
##
## **New preset... heads it**, and it is the whole of the menu a press on the
## grid outside every cell opens, so a library emptied of every preset still has
## the menu and the door out of the empty state. The dialog it opens is
## `SaNewPresetDialog`'s.
class_name SaBrushPresetTags
extends RefCounted

## The library's tags moved: a preset was tagged or untagged, or a tag was
## renamed or deleted. The chooser rebuilds on this, filter row included.
##
## *follow* is the tag the chooser should be filtered by afterwards, or empty
## for "the filter sorts itself out". Only a rename fills it, because that is
## the one act where the tag a painter is looking at is still there under
## another word, and a chooser that dropped back to All would look like the
## rename had emptied the library.
signal changed(follow: String)

## The row that opens the field for a tag nobody has typed yet. A `StringName`
## no tag can be, because a tag is what a painter typed and this is not.
const NEW_TAG_ID: StringName = &"__sa_new_tag"

## The row that opens New preset..., an id no tag can be for the same reason.
const NEW_PRESET_ID: StringName = &"__sa_new_preset"

## The start of a Convert to row's id, the target engine after it. A prefix no
## tag can carry, for the reason the row above is one.
const CONVERT_PREFIX: String = "__sa_convert:"

## What the field is being typed into, so one field serves both acts.
enum Purpose { NONE, NEW, RENAME }

## The buttons of the delete question, in the order they are drawn. Cancel first
## and as both the default and the cancel index, so Enter and Escape both leave
## the tag alone.
const DELETE_CANCEL: int = 0
const DELETE_CONFIRM: int = 1

## Where a tag is typed. Public because the chooser puts it in its own row and a
## scenario types into it, and hidden until one of the two acts opens it.
var field: LineEdit = null

## The cell's menu. Public for the same reason `SaChoiceButton.popup` is: a
## capture presses a row and a test reads one.
var menu: SaChoicePopup = null

var _store: SaPresetStore = null

## The converters the Convert to rows are asked of. Handed in by a test, and
## otherwise null and looked up on the main scene when the menu opens, because
## the chooser that builds this has no registries to hand over and a module
## loaded after the chooser was built still has to be offered.
var _converters: SaConverterRegistry = null

## The preset the last Convert to row wrote, for the report, empty until one did.
var _converted: String = ""

## The node the question is hosted on, which outlives the answer. Never the
## chooser itself: the grid is rebuilt on every change and a dialog parented to
## a cell would go with it.
var _host: Node = null

var _purpose: Purpose = Purpose.NONE

## The preset the open menu belongs to, and the tag being renamed. One of the
## two is set while the field is open and neither is afterwards.
var _preset: String = ""
var _renaming: String = ""

## Set while the field is being taken down, because hiding it and dropping its
## focus raises `focus_exited` from inside the close and that would be read as a
## second answer to a rename already answered. `SaLayerRename` carries the same
## flag for the same reason.
var _closing: bool = false


func _init(preset_store: SaPresetStore, host: Node, converters: SaConverterRegistry = null) -> void:
    _store = preset_store
    _host = host
    _converters = converters

    field = SaMake.line_edit(null, "ChooserTagName")
    field.visible = false
    field.custom_minimum_size = Vector2(float(SaUI.px(110)), 0.0)
    field.text_submitted.connect(_on_field_submitted)
    field.focus_exited.connect(_on_field_left)

    menu = SaChoicePopup.new()
    menu.name = "ChooserTagMenu"
    menu.chosen.connect(_on_menu_chosen)
    menu.marked.connect(_on_menu_marked)


## Opens the menu for *preset_name* at *at*, a point `SaPopupRect.at_press`
## answered for the right press, or under *anchor* when no point is given, which
## is how a suite asks for it: New preset..., then one
## checkable row per tag in the library, ticked where the preset carries it, and
## a row for a new one. An empty *preset_name* is the grid outside every cell,
## whose menu is New preset... alone.
##
## Rebuilt on every open rather than kept, because the library's tags move under
## it: a tag made on one preset has to be tickable on the next without the
## chooser being closed.
func open_menu_for(preset_name: String, anchor: Control, at: Variant = null) -> void:
    if _store == null or menu == null or not (preset_name.is_empty() or _store.has_preset(preset_name)):
        return
    _preset = preset_name
    menu.clear()
    menu.add_row(NEW_PRESET_ID, tr("New Preset..."))
    var where: Variant = null
    if at is Vector2i:
        where = Vector2(at as Vector2i)
    if preset_name.is_empty():
        menu.open_under(anchor, where)
        return
    menu.add_gap()
    # Convert to first, over the tags, because a library's tags run to a list
    # that scrolls and a row under the last of them is a row nobody finds. Both
    # headings only when there is a convert row, so the menu of a build whose
    # modules register no converter is the tag list it always was.
    var targets := _store.conversions_for(preset_name, converter_registry())
    if not targets.is_empty():
        menu.add_section(tr("Convert to"))
        for engine: StringName in targets:
            menu.add_row(StringName(CONVERT_PREFIX + String(engine)), SaPresetStore.engine_label(engine))
        menu.add_gap()
        menu.add_section(tr("Tags"))
    var carried := _store.tags_for(preset_name)
    for tag: String in _store.all_tags():
        menu.add_row(StringName(tag), SaBrushPresetTagFilter.label_of(tag), true, carried.has(tag))
    menu.add_gap()
    menu.add_row(NEW_TAG_ID, tr("New tag..."))
    menu.open_under(anchor, where)


## The converter registry the menu asks: the one handed in, or the running
## app's, or null in a test that handed none, which offers no Convert to row.
func converter_registry() -> SaConverterRegistry:
    if _converters != null:
        return _converters
    var tree := Engine.get_main_loop() as SceneTree
    var main_node: Node = tree.current_scene if tree != null else null
    if main_node == null or not ("registries" in main_node):
        return null
    var registries: SaRegistries = main_node.registries
    return registries.context.converters if registries != null and registries.context != null else null


## Writes *preset_name* as a new preset of *engine* beside it, and answers the
## new name, empty when nothing was written.
func convert_to(preset_name: String, engine: StringName) -> String:
    if _store == null:
        return ""
    var written := _store.convert_preset(preset_name, engine, converter_registry())
    if not written.is_empty():
        _converted = written
        changed.emit("")
    return written


## Opens the field on *tag*, seeded with it, for a rename.
func begin_rename(tag: String) -> bool:
    if _store == null or tag.is_empty():
        return false
    _renaming = tag
    _open_field(Purpose.RENAME, tag)
    return true


## Asks before taking *tag* off every preset carrying it, and takes it off only
## on the answer.
##
## The count is in the sentence because it is the whole of what the painter is
## being asked: a tag on one preset and a tag on thirty are the same two words
## otherwise. The sentence also says the presets stay, because "delete" over a
## library of brushes reads as deleting brushes and this deletes none.
func ask_delete(tag: String) -> void:
    if _store == null or _host == null or tag.is_empty():
        return
    var carriers := _store.names_tagged(tag).size()
    # Two sentences rather than one with "(s)" on the end. A question a painter
    # reads before pressing Delete is prose, and the count is the whole of what
    # they are weighing.
    var sentence := (
        tr("Take '%s' off one preset? The presets themselves are kept.") % tag
        if carriers == 1
        else (
            tr_n(
                "Take '%s' off %d preset? The preset itself is kept.",
                "Take '%s' off %d presets? The presets themselves are kept.",
                carriers
            )
            % [tag, carriers]
        )
    )
    SaMessage.confirm(
        _host,
        tr("Delete tag"),
        sentence,
        PackedStringArray([tr("Cancel"), tr("Delete")]),
        _on_delete_answered.bind(tag),
        DELETE_CANCEL,
        DELETE_CANCEL
    )


## Whether a name is being typed, which is what tells the chooser to leave its
## own row alone while one is.
func naming() -> bool:
    return _purpose != Purpose.NONE


## Writes whatever is in the field, the way Enter does. False when nothing was
## open or the name was empty, and the field closes either way.
func commit() -> bool:
    if _purpose == Purpose.NONE:
        return false
    var typed := SaPresetStore.sanitize_tag(field.text)
    var was := _purpose
    var renaming := _renaming
    var preset := _preset
    _close_field()
    if typed.is_empty() or _store == null:
        return false
    var moved := false
    match was:
        Purpose.NEW:
            moved = _store.assign_tag(preset, typed)
        Purpose.RENAME:
            moved = _store.rename_tag(renaming, typed) > 0
    if moved:
        changed.emit(typed if was == Purpose.RENAME else "")
    return moved


## Throws away what is in the field, the way Escape does.
func cancel() -> void:
    _close_field()


## What a dump reads about this gesture, so a claim about the menu and the field
## is settled by a report rather than argued over a screenshot.
func tags_report() -> Dictionary:
    return {
        "naming": naming(),
        "typing": field.text if field != null else "",
        "preset": _preset,
        "renaming": _renaming,
        "menu_open": menu != null and menu.visible,
        "menu_rows": menu.row_labels() if menu != null else [],
        "ticked": _ticked_rows(),
        "converted": _converted,
    }


## Drives the gesture from a scenario, `{"preset": {"tags": {...}}}`, and
## answers the report.
##
## Helpers rather than clicks, for the reason every other step on this chooser
## is one: the menu is a `Window` an injected click does not route into, and the
## field is inside a docker a scenario reaches by name rather than by pointer.
##
## *filtered* is the tag the chooser is filtering by, handed in rather than
## reached for, so this class still knows nothing about the grid. *anchor* is
## the control the menu opens under, a cell or the grid, or null to open it centred.
##
## The keys are applied in the order they are written here, so one step can open
## the menu, tick a tag, put the menu away and read the result. A tag or a
## preset that is not there is a loud failure and not a quiet nothing, which is
## the rule this chooser keeps and the reason a scenario cannot photograph a
## menu it never opened.
func capture_tags(spec: Dictionary, filtered: String = "", anchor: Control = null) -> Dictionary:
    if spec.has("menu"):
        var wanted := String(spec["menu"])
        if _store == null or not (wanted.is_empty() or _store.has_preset(wanted)):
            push_warning("SaCapture: preset tag menu failed, there is no preset '%s'" % wanted)
        else:
            open_menu_for(wanted, anchor)
    # The head row, pressed as a painter presses it, which opens New preset...
    if bool(spec.get("new_preset", false)):
        if menu == null or not menu.row_ids().has(NEW_PRESET_ID):
            push_warning("SaCapture: new preset failed, the menu has no New preset... row")
        else:
            menu.press_row(NEW_PRESET_ID)
    if spec.has("tick"):
        var tag := StringName(String(spec["tick"]))
        if menu == null or not menu.row_ids().has(tag):
            push_warning("SaCapture: preset tag tick failed, the menu has no row '%s'" % tag)
        elif menu.is_checked(tag) != bool(spec.get("on", true)):
            menu.press_check(tag)
    if spec.has("convert"):
        var row := StringName(CONVERT_PREFIX + String(spec["convert"]))
        if menu == null or not menu.row_ids().has(row):
            push_warning("SaCapture: preset convert failed, the menu has no Convert to row for '%s'" % spec["convert"])
        else:
            menu.press_row(row)
    if spec.has("new"):
        _on_menu_chosen(NEW_TAG_ID)
        field.text = String(spec["new"])
        commit()
    if spec.has("rename"):
        if begin_rename(filtered):
            field.text = String(spec["rename"])
            commit()
        else:
            push_warning("SaCapture: preset tag rename failed, no tag is being filtered by")
    if spec.has("delete"):
        ask_delete(filtered if String(spec["delete"]) == "true" else String(spec["delete"]))
    # Last, so one step can open the menu, tick and put it away. A painter closes
    # it by clicking elsewhere and a scenario has no elsewhere to click, which is
    # the same hole every other step on this chooser exists to fill.
    if bool(spec.get("close", false)) and menu != null:
        menu.hide()
    return tags_report()


## What each of *names* carries, name to tags, for the chooser's report: a step
## that tags or untags a preset is then read back off the dump rather than off
## the file on disk.
func tags_of(names: Array[String]) -> Dictionary:
    var carried: Dictionary = {}
    if _store == null:
        return carried
    for stored_name: String in names:
        carried[stored_name] = Array(_store.tags_for(stored_name))
    return carried


## The tags the open menu shows as carried, which is what a scenario reads back
## after a tick rather than opening the preset's file.
func _ticked_rows() -> Array[String]:
    var ticked: Array[String] = []
    if menu == null:
        return ticked
    for id: StringName in menu.row_ids():
        if id != NEW_TAG_ID and not String(id).begins_with(CONVERT_PREFIX) and menu.is_checked(id):
            ticked.append(String(id))
    return ticked


func _open_field(purpose: Purpose, seed_text: String) -> void:
    _purpose = purpose
    _closing = false
    if field == null:
        return
    field.text = seed_text
    field.visible = true
    # Only inside a tree: a test builds this chooser bare and a `grab_focus` on
    # a control with no viewport is an error rather than a no-op.
    if field.is_inside_tree():
        field.grab_focus()
        field.select_all()


func _close_field() -> void:
    _purpose = Purpose.NONE
    _preset = ""
    _renaming = ""
    if field == null:
        return
    _closing = true
    field.text = ""
    field.visible = false
    if field.is_inside_tree() and field.has_focus():
        field.release_focus()
    _closing = false


func _on_field_submitted(_text: String) -> void:
    commit()


func _on_field_left() -> void:
    # A field left by clicking elsewhere throws the name away rather than
    # writing it. `SaLayerRename` commits on the same event, and the difference
    # is what the two acts cost to undo: a layer keeps its old name in the
    # document's history, and a tag written by accident onto a preset has to be
    # found again to be taken off.
    if not _closing:
        cancel()


func _on_menu_chosen(id: StringName) -> void:
    if id == NEW_PRESET_ID:
        SaNewPresetDialog.open_from(_host)
    elif id == NEW_TAG_ID:
        _open_field(Purpose.NEW, "")
    elif String(id).begins_with(CONVERT_PREFIX) and not _preset.is_empty():
        convert_to(_preset, StringName(String(id).trim_prefix(CONVERT_PREFIX)))


## A tick wrote the library at once, for the reason the header gives: a popup
## the painter clicks away from never answers.
func _on_menu_marked(id: StringName, on: bool) -> void:
    if _store == null or _preset.is_empty() or id == NEW_TAG_ID or String(id).begins_with(CONVERT_PREFIX):
        return
    var moved := _store.assign_tag(_preset, String(id)) if on else _store.unassign_tag(_preset, String(id))
    if moved:
        changed.emit("")


func _on_delete_answered(index: int, doomed: String) -> void:
    if index != DELETE_CONFIRM or _store == null:
        return
    if _store.delete_tag(doomed) > 0:
        changed.emit("")
