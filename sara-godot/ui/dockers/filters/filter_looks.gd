## The Filters docker's Looks part: the saved looks under the parameters, with
## Save Look..., Add, Rename... and Delete.
##
## **What it does.** The workflow: "A group of filter layers is a look.
## Duplicate the group, switch one member off, compare. Save the group as a
## preset the way a brush is saved." Save Look... takes the active layer when
## it is a group of filter layers and asks a name in a field over the buttons,
## the way Brush Presets' Save as... does, and Return keeps it. A look picked in
## the list is added above the active layer by Add, or by a double click on its
## row, as a new group of its filter layers in one history step. Rename... asks
## the new name in the same field, and Delete asks first, in Brush Presets'
## words, and takes the look off disk only on the painter's Delete.
##
## **What it says.** The line under the heading is the docker's sentence that a
## look keeps no mask, because masks are painted per picture, and it is always
## there. The line over the buttons says what the last press did, or why it
## did nothing: Save Look... on a paint layer is refused there in a sentence,
## and the same sentence goes to the corner, as every refusal does.
##
## **The look's file** is `filter_look.gd`, which keeps the members, refuses
## what is not a look and puts one back into a document. This part asks it and
## the store, and records the add.
@tool
extends VBoxContainer

const FilterLook := preload("res://ui/dockers/filters/filter_look.gd")

## The node name, which a scenario and the docker's dump find the part under.
const NODE_NAME := "FilterLooks"

## What the part always says, the docker's sentence on masks.
const KEEPS_NO_MASK := "A look keeps filter layers and their settings. Masks are painted per picture, so a look keeps none."

## The history row of a rename, which is the store's and not the document's.
const SAVE_TITLE := "Save Look"

## The question's buttons, Cancel first, and Cancel is both what Enter presses
## and what Escape answers, as Brush Presets' Delete has it: there is no undo
## anywhere near a look's file.
const DELETE_CANCEL := 0
const DELETE_CONFIRM := 1

## Where the looks are listed, saved, renamed and deleted.
var store: SaPresetStore = null

## The canvas whose document the part saves from and adds to, or null for
## `Main`'s, which is what the running app has. Set by a suite, as the
## parameters part's is.
var target_canvas: SaCanvas = null

## The kinds a look's members are made as, Main's, handed in by the docker.
var layer_types: SaLayerTypeRegistry = null

## One row per saved look, sorted by name.
var list: ItemList = null

## The field a name is typed in, over the buttons, shown by Save Look... and
## Rename... and gone after Return, Escape or a click elsewhere.
var name_field: LineEdit = null

var save_button: Button = null
var add_button: Button = null
var rename_button: Button = null
var delete_button: Button = null

## What the last press did or why it did nothing, over the buttons.
var said_line: Label = null

## The look the field renames, or empty while it names a look to save.
var _renaming: String = ""


func _init() -> void:
    name = NODE_NAME
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_theme_constant_override("separation", SaUI.px(6))
    store = FilterLook.store()

    SaMake.separator(self, "LooksRule")
    var heading := SaMake.label(self, "LooksHeading", tr("Looks"))
    SaSettingsRows.embolden(heading)

    # No scroll of its own, so the sentence and every look are whole and the
    # docker's scroll takes a column taller than the docker. A scroll here with
    # a floor of 48 showed a line and a half of the sentence.
    var body := SaMake.column(self, "LooksBody", SaUI.px(4))
    body.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    var sentence := SaMake.label(body, "LooksSentence", tr(KEEPS_NO_MASK))
    sentence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    sentence.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    sentence.set_meta(SaUI.FONT_SCALE_META, 0.8)
    sentence.modulate = Color(1.0, 1.0, 1.0, 0.7)

    # Its own height, every row, so the docker's scroll is the one the list
    # has.
    list = ItemList.new()
    list.name = "LooksList"
    list.auto_height = true
    list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    list.item_selected.connect(func(_index: int) -> void: _follow_pick())
    list.item_activated.connect(func(index: int) -> void: add(list.get_item_text(index)))
    body.add_child(list)

    said_line = SaMake.label(self, "LooksSaid")
    said_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    said_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    said_line.visible = false

    name_field = SaMake.line_edit(self, "LookName", "", tr("Name"))
    name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    name_field.tooltip_text = tr("Press Enter to save, Escape to cancel.")
    name_field.visible = false
    name_field.text_submitted.connect(_on_name_submitted)
    name_field.focus_exited.connect(close_name_field)
    name_field.gui_input.connect(_on_name_gui_input)

    var first := SaMake.turning_row(self, "LooksSaveRow", SaUI.px(4))
    save_button = _button(first, "LookSave", tr("Save Look..."), tr("Save the active group of filter layers as a look"))
    save_button.size_flags_stretch_ratio = 2.0
    save_button.pressed.connect(open_save)
    add_button = _button(first, "LookAdd", tr("Add"), tr("Add the selected look above the active layer, as a group."))
    add_button.pressed.connect(func() -> void: add(picked()))

    var second := SaMake.turning_row(self, "LooksEditRow", SaUI.px(4))
    rename_button = _button(second, "LookRename", tr("Rename..."), tr("Rename the selected look."))
    rename_button.pressed.connect(open_rename)
    delete_button = _button(second, "LookDelete", tr("Delete"), tr("Delete the selected look."))
    delete_button.pressed.connect(ask_delete)

    visibility_changed.connect(refresh)
    refresh()


## Lists the store's looks again, keeping the pick on the look it was on, and
## dims what needs a pick when there is none.
func refresh() -> void:
    var was := picked()
    list.clear()
    for look_name in store.list_names():
        list.add_item(look_name)
    pick(was)
    _follow_pick()


## The looks the list shows, which is the store's folder as the last write or
## show left it, sorted by name.
func listed() -> Array[String]:
    var names: Array[String] = []
    for i in list.item_count:
        names.append(list.get_item_text(i))
    return names


## The look picked in the list, or empty.
func picked() -> String:
    var rows := list.get_selected_items()
    return list.get_item_text(rows[0]) if not rows.is_empty() else ""


## Picks the row of *look_name* the way a hand's press does, and answers
## whether the list holds one.
func pick(look_name: String) -> bool:
    for i in list.item_count:
        if list.get_item_text(i) == look_name:
            list.select(i)
            _follow_pick()
            return true
    list.deselect_all()
    _follow_pick()
    return false


## Save Look...: refused in a sentence for anything but a group of filter
## layers, and otherwise the name field, holding the group's name so a press
## and a Return save it. Answers whether the field opened.
func open_save() -> bool:
    var refused := FilterLook.refusal(_active())
    if not refused.is_empty():
        close_name_field()
        _say(refused)
        SaProblems.refuse(tr(SAVE_TITLE), refused)
        return false
    _renaming = ""
    return _open_field(String(_active().name))


## Rename...: the name field holding the picked look's name. Answers whether
## there was a look to rename.
func open_rename() -> bool:
    var look_name := picked()
    if look_name.is_empty():
        return false
    _renaming = look_name
    return _open_field(look_name)


## Saves the active group as the look *typed*, over a look of that name, and
## answers the name it was stored under, or empty when nothing was written.
func save(typed: String) -> String:
    var group := _active()
    var refused := FilterLook.refusal(group)
    if not refused.is_empty():
        _say(refused)
        SaProblems.refuse(tr(SAVE_TITLE), refused)
        return ""
    var stored := SaPresetStore.sanitize_name(typed)
    if stored.is_empty():
        _say(tr("A look needs a name."))
        return ""
    # A name another look holds with its case folded is that look's, as a
    # brush preset's is, because a folder that ignores case keeps one file.
    var taken := store.taken_as(stored)
    var over := not taken.is_empty()
    if over:
        stored = taken
    stored = store.save_preset(stored, FilterLook.new(group))
    if stored.is_empty():
        _say(tr("'%s' could not be written, so it is not saved.") % typed)
        return ""
    refresh()
    pick(stored)
    _say(tr("Saved '%s' over the look of that name.") % stored if over else tr("Saved '%s'.") % stored)
    return stored


## Adds the look *look_name* above the active layer as a group of its filter
## layers, in one history step, and answers the group, or null with the reason
## said.
func add(look_name: String) -> SaLayer:
    var document := _document()
    var look := store.load_preset(look_name) as FilterLook if not look_name.is_empty() else null
    if look == null:
        _say(tr("Select a look to add.") if look_name.is_empty() else tr("There is no look called '%s'.") % look_name)
        return null
    var refused := look.place_refusal(document, layer_types)
    if not refused.is_empty():
        _say(refused)
        SaProblems.refuse(tr(FilterLook.ADD_STEP), refused)
        return null
    var block := look.place(document, layer_types, look_name)
    SaLayerOps.new(document).commit_added(tr(FilterLook.ADD_STEP), block)
    _say(tr("Added '%s'.") % look_name)
    return block[-1]


## Gives the look *from* the name *typed*, and answers the name it now has, or
## empty when it kept its own. A name another look has, with case folded, is
## refused rather than written over, because that look would be lost with no
## step to undo.
##
## A name that changes only the case is a move of the file through
## `SaPresetNames.move_case`, never a write and a delete: on a folder that
## ignores case the write lands in the old file and the delete then takes the
## look away.
func rename(from: String, typed: String) -> String:
    var stored := SaPresetStore.sanitize_name(typed)
    if stored.is_empty() or stored == from:
        return ""
    if SaPresetNames.only_case(from, stored):
        if SaPresetNames.move_case(store, from, stored).is_empty():
            _say(tr("'%s' could not be renamed.") % from)
            return ""
    else:
        var taken := store.taken_as(stored)
        if not taken.is_empty():
            _say(tr("There is a look called '%s' already. Choose another name, or delete that one first.") % taken)
            return ""
        var look := store.load_preset(from)
        if look == null or store.save_preset(stored, look).is_empty():
            _say(tr("'%s' could not be renamed.") % from)
            return ""
        store.delete_preset(from)
    refresh()
    pick(stored)
    _say(tr("Renamed '%s' to '%s'.") % [from, stored])
    return stored


## Asks whether to delete the picked look, naming it, and deletes only on the
## painter's Delete. Answers the question, or null with no look picked.
##
## Hosted on this part, a node that outlives the answer, and the look's name is
## bound rather than read again, because the answer comes on a later frame and a
## pick made in between would otherwise be the look that went.
func ask_delete() -> SaMessage:
    var doomed := picked()
    if doomed.is_empty():
        return null
    return SaMessage.confirm(
        self,
        tr("Delete look"),
        tr("Delete '%s'? This cannot be undone.") % doomed,
        PackedStringArray([tr("Cancel"), tr("Delete")]),
        _on_delete_answered.bind(doomed),
        DELETE_CANCEL,
        DELETE_CANCEL
    )


## Takes the look *look_name* off disk, and answers whether there was one. The
## call the door and the suites make once the painter has answered, and what
## the question's Delete calls.
func delete(look_name: String) -> bool:
    if look_name.is_empty() or not store.delete_preset(look_name):
        return false
    refresh()
    _say(tr("Deleted '%s'.") % look_name)
    return true


func _on_delete_answered(index: int, doomed: String) -> void:
    if index == DELETE_CONFIRM:
        delete(doomed)


## Puts the field away, which is also what its losing the keyboard does: the
## router's Escape lets go of a focused text box before the box hears the key,
## so the close follows the focus, as Brush Presets' field does.
func close_name_field() -> void:
    name_field.visible = false
    if name_field.has_focus():
        name_field.release_focus()


## What the part shows, for the state dump: the looks, the one picked, what the
## line over the buttons says, whether the field is open and the sentence.
func describe() -> Dictionary:
    return {
        "looks": listed(),
        "picked": picked(),
        "said": said_line.text if said_line.visible else "",
        "field": name_field.text if name_field.visible else "",
        "renaming": _renaming,
        "sentence": tr(KEEPS_NO_MASK),
    }


func _open_field(text: String) -> bool:
    name_field.text = text
    name_field.visible = true
    if name_field.is_inside_tree():
        name_field.grab_focus()
        name_field.select_all()
    _keep_in_view()
    return true


func _on_name_submitted(typed: String) -> void:
    var done := rename(_renaming, typed) if not _renaming.is_empty() else save(typed)
    if not done.is_empty():
        _renaming = ""
        close_name_field()


func _on_name_gui_input(event: InputEvent) -> void:
    var key := event as InputEventKey
    if key == null or not key.is_pressed() or key.is_echo() or not SaShortcutKeys.is_escape(event):
        return
    close_name_field()
    name_field.accept_event()


## Add, Rename... and Delete work on a pick, and are dimmed with none.
func _follow_pick() -> void:
    var none := picked().is_empty()
    add_button.disabled = none
    rename_button.disabled = none
    delete_button.disabled = none


## Puts *text* on the line over the buttons.
func _say(text: String) -> void:
    said_line.text = text
    said_line.visible = not text.is_empty()
    _keep_in_view()


## Scrolls the docker's column so the buttons stand in it again. The line and
## the field each push the rows down by their height when they appear, and the
## part is at the column's foot, so a press that scrolled them in would
## otherwise leave them under the docker's edge. A frame later, because the
## containers lay the taller part out a frame after it grows.
func _keep_in_view() -> void:
    var outer := get_parent()
    while outer != null and not (outer is ScrollContainer):
        outer = outer.get_parent()
    if outer == null or not is_inside_tree():
        return
    await get_tree().process_frame
    if is_instance_valid(outer) and is_instance_valid(delete_button):
        (outer as ScrollContainer).ensure_control_visible(delete_button.get_parent() as Control)


func _active() -> SaLayer:
    var document := _document()
    return document.active_layer if document != null else null


func _document() -> SaDocument:
    var canvas := target_canvas
    if canvas == null and is_inside_tree():
        canvas = SaCanvasView.front_canvas()
    return canvas.document if canvas != null and is_instance_valid(canvas) else null


## A button of the part's rows, sharing the row's width and wrapping its words
## rather than widening a docker that is 160 wide. Where its words are wider
## than its share the row stands the two one over the other, `SaTurningRow`.
static func _button(row: BoxContainer, node_name: String, text: String, tooltip: String) -> Button:
    var made := SaMake.button(row, node_name, text, tooltip)
    made.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # Wrapped rather than clipped, so words wider than the column even with
    # the row turned read whole on a second line, and the button still asks
    # for no width of its own.
    made.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    made.focus_mode = Control.FOCUS_NONE
    return made
