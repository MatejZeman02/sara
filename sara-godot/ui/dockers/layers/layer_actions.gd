## The row under the layer list: plus, an arrow beside it, minus, and a dropdown
## holding the rest, which is also what a right click anywhere in the docker
## opens.
##
## Few buttons rather than a button per operation, because a layer is moved by
## dragging its row and grouped by a chord, and a row of rarely pressed buttons
## takes the space the list needs. The two locks are here as check items as
## well as on every row.
##
## Plus asks no kind: the question is behind the arrow, so one click always
## adds a paint layer, the layer a painter reaches for most.
##
## **The dropdown is `SaChoicePopup`, not the engine's own `PopupMenu`**, the
## same custom window the note and dialog use. A plain `Button` opens it, the
## way `BlendModeButton` does, and the same list serves the more button and the
## right click.
##
## **The list is built again on every open**, rather than built once and then
## written over. What a row is depends on the active layer, and the icon, the
## check and the disabled state are all `add_row` arguments, which is what
## makes them the list's own state rather than writes over its controls. An
## icon assigned straight onto a row's button is drawn at the texture's size,
## and a row dimmed by a write the list never heard about is one nothing it
## reports calls dimmed.
##
## **The arrow's list is `SaChoicePopup` as well**, because an engine
## `PopupMenu` draws a row's icon at the texture's size and is placed at the
## arrow's position inside the docker's own window, which is a point on the far
## side of the screen from the arrow once the docker is embedded.
##
## **Nothing here rebuilds the rows**. Every operation below ends in a cache
## update, and the cache update announces `document_changed`, which the docker
## answers by comparing its rows with the document and rebuilding them when the
## two differ. Calling the docker's `sync_layer_list` from here as well would
## be the docker's answer given twice.
##
## **Duplicate, Group, Merge Down and Add Mask stand on the row**, as
## `SaLayerOpButtons` in the stretch between minus and More, and a narrow docker
## folds them back into the dropdown from the right.
##
## **The dropdown's rows are the Layer menu's**, `SaLayerMenuRows`, in its order
## and under its words, less the adds and Delete that plus, the arrow and minus
## stand for.
##
## **Ground, beside minus, opens the active ground's settings** in a dialog of
## their own, so they never move this row. It stands in the fixed part of the
## row rather than folding with the four, because at the docker's floor plus,
## the arrow, minus, Ground and More still fit, so it has nothing to fold for.
class_name SaLayerActions
extends HBoxContainer

enum Item {
    DUPLICATE,
    CLEAR,
    MERGE_DOWN,
    MOVE_UP,
    MOVE_DOWN,
    GROUP,
    ISOLATE,
    LOCK_PAINT,
    LOCK_ALPHA,
    RENAME,
    MASK_ADD,
    MASK_ADD_FROM_SELECTION,
    MASK_DELETE,
    MASK_APPLY,
    MASK_INVERT,
    MASK_DISABLE,
    MASK_TO_SELECTION,
    BAKE,
    CLIP,
    FLATTEN,
}

## What the dropdown is labelled with. The word "More" would make the button
## more than twice as wide as the squares beside it, because a button sizes
## itself around its text and the neighbours are icons under a square floor. A
## horizontal ellipsis is the same affordance in one glyph, and the tooltip
## carries the word. Not an icon, because
## `assets/icons/` has no glyph for it and one drawn for this button alone would
## be the only hand-made icon in a set copied from the editor.
const MORE_GLYPH := "…"

## How wide the arrow beside the plus is, in logical pixels. Its icon fills
## what the button's margins leave, which is fourteen at this width, where the
## old width of 13 left a speck.
const KIND_ARROW_WIDTH := 22

## Each item's row id, which is its id in `SaLayerMenuRows`, the command's id
## where the row is a command, spelled as literals because a `const` naming a
## global class breaks the class cache. The enum's order is not the menu's, and
## a new item is appended rather than inserted, so no existing item moves.
const ROW_IDS: Array[StringName] = [
    &"layer_duplicate",
    &"layer_clear",
    &"layer_merge_down",
    &"layer_move_up",
    &"layer_move_down",
    &"layer_group",
    &"layer_isolate",
    &"layer_lock",
    &"layer_alpha_lock",
    &"layer_rename",
    &"layer_mask_add",
    &"layer_mask_add_from_selection",
    &"layer_mask_delete",
    &"layer_mask_apply",
    &"layer_mask_invert",
    &"layer_mask_disable",
    &"layer_mask_to_selection",
    &"layer_bake",
    &"layer_clip_to_below",
    &"layer_flatten",
    &"layer_merge_visible",
    &"layer_export_lut",
    &"layer_rasterize_impasto",
    &"layer_rasterize",
]

## The four rows of the list that carry an icon, although the Layer menu's
## rows carry none: the dropdown is a docker's, where the icons are.
const ICONS: Dictionary = {
    &"layer_duplicate": "duplicate",
    &"layer_move_up": "moveup",
    &"layer_move_down": "movedown",
    &"layer_clear": "clear",
}

## The mask's seven rows on a picked filter's menu, in `SaMaskOps.ALL`'s order.
## Their row ids are the command ids, so a row, a Layer menu entry and a chord
## run the same `SaMaskOps.run`.
const MASK_TITLES: Array[String] = [
    "Add Mask", "Add Mask from Selection", "Delete Mask", "Apply Mask", "Invert Mask", "Disable Mask", "Mask to Selection"
]

## A picked filter's row below its mask's seven: fill the mask with a colour
## range, through the dialog Select > Colour Range opens.
const MASK_FROM_COLOR_RANGE := &"layer_mask_from_color_range"

## A picked filter's first row: takes the record off its node as one step and
## leaves the node and its pixels as they were.
const FILTER_DELETE := &"filter_delete"

## The two conversions, through `SaFilterConversion`: a picked
## filter's row turning it into an adjustment layer at the top of its node, and
## an adjustment layer's row turning it back into attached filters. Each is
## dimmed with the conversion's sentence where it would change the picture.
const FILTER_TO_LAYER := &"filter_to_adjustment_layer"
const LAYER_TO_FILTER := &"adjustment_layer_to_filter"
## The row of an effect layer that opens the list of nodes it can read.
const EFFECT_INPUT := &"effect_layer_input"
## The row under Rename that opens the colours a row can be given.
const COLOUR := &"layer_color"

## The Ground button's hover, live while the document holds a Paper or a
## Canvas, whichever layer is active, and dimmed only without one, and its
## icon, the mountains a row with height shows rather than a checker board,
## because a ground's settings are what raise its tooth.
const GROUND_HINT := "Ground: which ground, its tooth, its colours and its grain"
const GROUND_DIMMED_HINT := "Add a Paper or Canvas layer from the arrow beside the plus to set a ground."
const GROUND_ICON := "relief"

## The rename dialog on the menu is the docker's, because the docker is what has
## a document to write through and a row list to put right afterwards, so the
## menu asks for it rather than opening it.
signal rename_requested

## The Ground button of *strip* was pressed on a ground. The dialog window is
## the docker's, which holds the rows and opens it beside itself.
signal ground_pressed(strip: SaLayerActions)

## The list whose picked rows the actions act on. Asked, never written.
var list: SaLayerList

## The canvas whose document the actions change, and the layer types the arrow
## offers. The docker sets both where it sets its own. A null registry means
## the plus adds a plain layer, which is what it always did.
var target_canvas: SaCanvas = null
var layer_types: SaLayerTypeRegistry = null

var add_btn: Button
var add_type_btn: Button
var del_btn: Button
## What the minus takes off and says, a picked mask before a filter or layers.
var minus: SaLayerMinus = null
var ground_btn: Button
var more_btn: Button
var menu: SaChoicePopup
## The stretch between minus and More that holds the four operation buttons.
var op_buttons: SaLayerOpButtons
var pointer := SaLayerPointerMenu.new()

var _color_range_dialog: SaColorRangeDialog = null

## Built from the layer type registry, one per kind the arrow beside the plus
## offers. A child of the arrow, so a dump files the open list under
## `AddTypeBtn` the way it files the More menu under `MoreBtn`.
var _add_type_menu: SaChoicePopup = null
## The nodes an effect layer can read, opened beside its Input row.
var input_list := SaEffectInputList.new()
## The colours, opened beside the Colour row.
var color_list := SaLayerColorList.new()


func _init(rows: SaLayerList) -> void:
    list = rows
    name = "ActionsBox"
    add_theme_constant_override("separation", SaUI.px(6))

    add_btn = _button("+", tr("Add a paint layer"), add_layer, "ToolAddNode", "AddBtn")
    # An icon rather than a down arrow in the text, which the default Inter and
    # two of the other faces have no glyph for and drew as a box.
    add_type_btn = _button("", tr("Add another kind of layer"), open_add_type_menu, "chevron_down", "AddTypeBtn")
    add_type_btn.custom_minimum_size = Vector2(SaUI.px(KIND_ARROW_WIDTH), SaUI.px(SaUI.BASE_BTN_H))
    _add_type_menu = SaChoicePopup.new()
    _add_type_menu.name = "AddLayerTypeMenu"
    add_type_btn.add_child(_add_type_menu)
    _add_type_menu.chosen.connect(_on_add_type_chosen)
    _add_type_menu.branched.connect(open_grounds.unbind(1))
    del_btn = _button("-", tr(SaLayerMinus.DELETE_LAYER_HINT), delete_picked, "Quad", "DelBtn")
    minus = SaLayerMinus.new(del_btn)
    # On the press, as a dropdown's button is, so a press on an open panel is
    # its close rather than a close and a reopen.
    ground_btn = _button("", tr(GROUND_HINT), ground_pressed.emit.bind(self), GROUND_ICON, "GroundBtn")
    ground_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
    if list != null:
        list.filter_selected.connect(sync_buttons.unbind(1))

    op_buttons = SaLayerOpButtons.new(SaUI.px(6))
    add_child(op_buttons)
    op_buttons.chosen.connect(_on_menu_choice)

    more_btn = SaMake.button(self, "MoreBtn", MORE_GLYPH, tr("More layer actions"))
    more_btn.flat = false
    more_btn.custom_minimum_size = Vector2(SaUI.px(SaUI.BASE_BTN_H), SaUI.px(SaUI.BASE_BTN_H))
    more_btn.pressed.connect(_on_more_pressed)

    # Built without the list's height cap, which a top bar menu goes without
    # too. The cap stopped this one at 520 pixels with room above it for 900,
    # so its last rows scrolled under an edge that read as the window's.
    # `SaPopupRect.under` already opens it on the side with more room and no
    # taller than that side, which is the fit the window needs.
    menu = SaChoicePopup.new(true, false)
    menu.name = "LayerActionsMenu"
    more_btn.add_child(menu)
    sync_from_active_layer()
    menu.chosen.connect(_on_menu_choice)
    menu.marked.connect(_on_menu_mark)
    menu.branched.connect(_on_menu_branch)
    menu.add_child(input_list)
    menu.add_child(color_list)
    color_list.chosen.connect(_on_color_chosen)
    menu.about_to_popup.connect(sync_from_active_layer)
    menu.popup_hide.connect(pointer.forget)
    sync_buttons()


func _button(label_text: String, tooltip: String, callback: Callable, icon_name: String, node_name: String) -> Button:
    var btn := SaMake.button(self, node_name, label_text, tooltip)
    btn.custom_minimum_size = Vector2(SaUI.px(SaUI.BASE_BTN_H), SaUI.px(SaUI.BASE_BTN_H))
    SaUI.set_button_icon(btn, icon_name, label_text)
    btn.pressed.connect(callback)
    return btn


## *item*'s row id in `menu`. A fixed table rather than a `String(Item.X)`
## conversion, because an enum's name is an editor convenience and not
## something the language promises to keep.
func row_id_of(item: Item) -> StringName:
    return ROW_IDS[item]


## Presses *item*'s row the way a pointer would, for a scenario or a test: the
## popup is a `Window` of its own, so an injected click does not reach it. A
## closed list is built first, the way opening it would build it, because the
## docker lets a closed list fall behind the layer.
##
## An item standing on the row as a button is pressed there instead, and a
## dimmed one refuses, for the reason `SaChoicePopup.press_row` gives: an
## emitted `pressed` walks past `disabled`.
func press_item(item: Item) -> bool:
    var btn := on_row(item)
    if btn != null:
        sync_buttons()
        if btn.disabled:
            return false
        btn.pressed.emit()
        return true
    if not menu.visible:
        sync_from_active_layer()
    return menu.press_row(row_id_of(item))


## *item*'s button when it stands on the row, or null when it is folded into
## the More menu or is not one of the four.
func on_row(item: Item) -> Button:
    return op_buttons.on_row(row_id_of(item))


## The menu's rows for the layer that is active now, `SaLayerMenuRows`'s: a
## group reads Ungroup and can be isolated, a layer-only row is dimmed on a
## group and says why, the locks show what the layer has, and every row that
## needs a document is dimmed without one.
##
## Built rather than written over. A row's icon, its check and its disabled state
## are `add_row` arguments, so the list knows all three: it draws the icon at the
## row's height instead of the texture's, it dims a disabled row itself,
## `press_row` refuses one, and `row_report` says so in the dump.
##
## **An open list keeps the row the keyboard is on**. A lock pressed on the list
## writes the layer, the layer's signal brings the docker back here, and a
## rebuild that left no row highlighted would make a second Enter press nothing.
## A list about to open is not visible yet and starts from nowhere, as every
## other list does.
##
## **The rows are the Layer menu's**, in its order, with its words, chords and
## sentences, read from the registry the four buttons found, `SaLayerPointerMenu`
## choosing the More list or the whole one the right click opens. The two
## conversions an adjustment or an effect layer has follow Bake, the last row
## of the block that changes what the stack holds.
func sync_from_active_layer() -> void:
    var doc := _document()
    var layer := doc.active_layer if doc != null else null
    var no_layer := layer == null
    var keep := menu.highlighted() if menu.visible else &""
    menu.clear()
    sync_buttons()
    # A picked filter row's menu is Delete Filter and its mask's rows and
    # nothing else: every other row here acts on a layer, and the row the menu
    # was opened on is not one.
    if _picked_record() != null:
        menu.add_row(FILTER_DELETE, tr("Delete Filter"), false, false, "", "", no_layer)
        var to_layer := _conversion_refusal()
        menu.add_row(FILTER_TO_LAYER, tr("Convert to Adjustment Layer"), false, false, "", "", not to_layer.is_empty())
        menu.label_button(FILTER_TO_LAYER).tooltip_text = to_layer
        menu.add_gap()
        _add_mask_rows(_picked_record())
        menu.add_gap()
        menu.add_row(MASK_FROM_COLOR_RANGE, tr("Mask from Colour Range..."))
        if not keep.is_empty():
            menu.set_highlight(keep)
        return
    for row: Variant in pointer.rows(doc, op_buttons, layer_types):
        if row is StringName:
            menu.add_gap()
            continue
        var drawn: SaLayerMenuRows.Row = row
        if drawn.id == row_id_of(Item.MERGE_DOWN):
            _merge_row_over_the_pick(drawn)
        drawn.draw(menu, drawn.id, ICONS.get(drawn.id, ""))
        if drawn.id == row_id_of(Item.RENAME):
            var words := SaLayerColorTag.words(layer.color_tag if layer != null else &"")
            menu.add_branch_row(COLOUR, tr("Colour"), tr(words), no_layer)
        if drawn.id == row_id_of(Item.BAKE):
            _add_conversions(doc, layer)
    if not keep.is_empty():
        menu.set_highlight(keep)


## The folded Merge Down row over several picked rows, dimmed by the test the
## button is and saying why. The rows ask the active layer alone, and a dimmed
## row refuses its press, so a pick ranged up from the bottom layer never merged.
func _merge_row_over_the_pick(row: SaLayerMenuRows.Row) -> void:
    var pick := SaLayerOps.MergePick.new(_document(), _picked())
    if pick.layers.size() < 2:
        return
    var descriptor := op_buttons.commands.get_descriptor(row.id) if op_buttons.commands != null else null
    row.disabled = not pick.stop.is_empty()
    row.sentence = pick.refusal() if row.disabled else (tr(descriptor.sentence) if descriptor != null else "")


## An adjustment layer's way back to an attached filter, and the list of nodes
## an effect layer reads, which are this docker's rows alone.
func _add_conversions(doc: SaDocument, layer: SaLayer) -> void:
    if layer != null and layer.is_adjustment():
        var to_filter := SaFilterConversion.new(doc).record_refusal(layer)
        menu.add_row(LAYER_TO_FILTER, tr("Convert to Attached Filter"), false, false, "", "", not to_filter.is_empty())
        menu.label_button(LAYER_TO_FILTER).tooltip_text = to_filter
    if layer != null and layer.is_effect():
        var reads := SaEffectLayer.input_of(layer)
        menu.add_branch_row(EFFECT_INPUT, tr("Input"), str(reads.name) if reads != null else tr("None"))


## The mask's rows, each dimmed when it cannot run on *mask_owner*, a layer or a
## filter's record, and Disable Mask a tick that shows a mask switched off. Add
## Mask is left to its button while that stands on the row.
func _add_mask_rows(mask_owner: Object) -> void:
    var mask: SaMask = mask_owner.get(&"mask") if mask_owner != null else null
    for index in SaMaskOps.ALL.size():
        var command_id: StringName = SaMaskOps.ALL[index]
        if command_id == SaMaskOps.ADD and on_row(Item.MASK_ADD) != null:
            continue
        var runs := SaMaskOps.can(command_id, mask_owner)
        var is_toggle := command_id == SaMaskOps.DISABLE
        var ticked := is_toggle and runs and not mask.enabled
        menu.add_row(command_id, tr(MASK_TITLES[index]), is_toggle, ticked, "", "", not runs)
        if is_toggle:
            menu.check_box(command_id).disabled = not runs


## Runs one of the mask's operations, as one step, on the picked filter's
## record when a filter row is picked and on every picked layer otherwise.
func run_mask_command(command_id: StringName) -> void:
    var doc := _document()
    if doc == null:
        return
    if _picked_record() != null:
        SaMaskOps.new(doc).run(command_id, _picked_record())
        return
    SaLayerSetStep.new(doc).run_mask(command_id, _picked(), doc.active_layer)


## The four operation buttons for the layer that is active now, each dimmed
## when its command cannot act, which is the test its folded row is dimmed by,
## Group reading Ungroup on a group and a dimmed Merge Down saying why, as their
## rows do. The minus's hover is put right here too, because a pick moving between
## a layer and a filter changes both.
func sync_buttons() -> void:
    _sync_delete_hint()
    _sync_ground()
    var live := {}
    for item: Item in [Item.DUPLICATE, Item.GROUP, Item.MERGE_DOWN, Item.MASK_ADD]:
        live[row_id_of(item)] = _acts(item)
    var doc := _document()
    var on_group := doc != null and doc.active_layer != null and doc.active_layer.is_group
    var why := {}
    if not live[row_id_of(Item.MERGE_DOWN)] and doc != null and doc.active_layer != null:
        var pick := SaLayerOps.MergePick.new(doc, _picked())
        var alone := SaLayerMenuRows.new(doc).merge_refusal(doc.active_layer, "")
        why[row_id_of(Item.MERGE_DOWN)] = pick.refusal() if pick.layers.size() > 1 else alone
    op_buttons.sync(live, {row_id_of(Item.GROUP): tr("Ungroup")} if on_group else {}, why)


## Whether *item*'s command would act now. Merge Down asks it of the picked
## rows, which is what it then merges, and Add Mask asks the `can_` function the
## Layer menu's row asks, of the picked filter's record when one is picked.
func _acts(item: Item) -> bool:
    var doc := _document()
    if doc == null or doc.active_layer == null:
        return false
    match item:
        Item.MERGE_DOWN:
            return SaLayerOps.new(doc).can_merge_down(doc.active_layer, _picked())
        Item.MASK_ADD:
            if _picked_record() != null:
                return SaMaskOps.can(SaMaskOps.ADD, _picked_record())
            return SaLayerSetStep.can_mask(SaMaskOps.ADD, _picked())
    return true


## Opens the colour range dialog for the picked filter's mask, on the
## foreground colour. Built on first use and kept, so it opens on the settings
## last applied. Answers the dialog, for a suite, or null with no filter picked.
func open_color_range_dialog() -> SaColorRangeDialog:
    if _picked_record() == null or _document() == null or not is_inside_tree():
        return null
    if _color_range_dialog == null:
        _color_range_dialog = SaColorRangeDialog.new()
        add_child(_color_range_dialog)
        _color_range_dialog.range_confirmed.connect(apply_color_range)
    var dialog := _color_range_dialog
    var machine := target_canvas.tool_machine() if target_canvas != null else null
    dialog.open(SaColors.foreground, dialog.chosen_fuzziness(), dialog.chosen_merged(), dialog.chosen_mode(), false, machine)
    return dialog


## Fills the picked filter's mask with the range, as one step, which
## `SaFilterMaskRange` works out. Here, because the dialog answers the docker.
func apply_color_range(color: Color, fuzziness: float, sample_merged: bool, _mode: int = 0) -> bool:
    var easel := target_canvas.easel if target_canvas != null else null
    return SaFilterMaskRange.new(_document(), easel).fill(_picked_record(), color, fuzziness, sample_merged)


## The record of the filter row the list has picked, or null while a layer's
## row holds the pick.
func _picked_record() -> SaAttachedFilter:
    return list.picked.selected_record if list != null else null


## The whole Layer menu from a right click, its corner at *at*, measured
## through the docker's screen transform as `SaPopupRect.of_anchor` measures
## More, and sized as `open_under` sizes it. The press read in the docker's
## coordinates opened the list at the window's top left, and `reset_size`
## sized it by its scroll box, which asks for no height, so it opened as an empty bar.
func open_menu_at(at: Vector2) -> void:
    pointer.open_at(menu, self, at, sync_from_active_layer)


## The label of a plain row, pressed, which acts at once and closes the list.
## The three check rows are not answered here: a press on a check row's label
## presses its box, so both halves of the row reach `_on_menu_mark` and nothing
## emits `chosen` for them.
func _on_menu_choice(id: StringName) -> void:
    if id == row_id_of(Item.RENAME):
        rename_requested.emit()
    elif id == row_id_of(Item.DUPLICATE):
        duplicate_layer()
    elif id == row_id_of(Item.CLEAR):
        clear_layer()
    elif id == row_id_of(Item.MERGE_DOWN):
        merge_down()
    elif id == row_id_of(Item.MOVE_UP):
        move_layer(1)
    elif id == row_id_of(Item.MOVE_DOWN):
        move_layer(-1)
    elif id == row_id_of(Item.GROUP):
        toggle_group()
    elif id == row_id_of(Item.BAKE):
        bake()
    elif id == &"layer_rasterize_impasto":
        _rasterize_impasto()
    elif id == &"layer_rasterize":
        _rasterize_layer()
    elif id == row_id_of(Item.CLIP):
        flip_clip()
    elif id == row_id_of(Item.FLATTEN):
        flatten()
    elif SaMaskOps.ALL.has(id):
        run_mask_command(id)
    elif id == MASK_FROM_COLOR_RANGE:
        open_color_range_dialog()
    elif id == FILTER_DELETE:
        delete_filter()
    elif id == FILTER_TO_LAYER:
        convert_filter_to_layer()
    elif id == LAYER_TO_FILTER:
        convert_layer_to_filter()
    elif id == SaEffectsLut.COMMAND:
        SaEffectsLut.open_on(self, _document())
    elif id == &"layer_delete":
        delete_layer()
    else:
        pointer.press(id, _document(), layer_types, op_buttons.commands, self)


## A check row pressed, on its box or on its label, which presses the box:
## writes the state the box now shows and leaves the list open, so more than one
## lock can be set in one visit.
func _on_menu_mark(id: StringName, on: bool) -> void:
    if id == row_id_of(Item.ISOLATE):
        set_isolated(on)
    elif id == row_id_of(Item.LOCK_PAINT):
        set_paint_lock(on)
    elif id == row_id_of(Item.LOCK_ALPHA):
        set_alpha_lock(on)
    elif id == row_id_of(Item.MASK_DISABLE):
        run_mask_command(id)


## A row that opens a list beside it: the effect layer's Input, filled for the
## active layer and opened as the menu's child.
func _on_menu_branch(id: StringName) -> void:
    var doc := _document()
    if id == COLOUR and doc != null and doc.active_layer != null:
        color_list.fill(doc.active_layer.color_tag)
        menu.open_child(color_list, id)
    if pointer.branch(id, menu, doc, layer_types) or id != EFFECT_INPUT or doc == null:
        return
    input_list.fill(doc, doc.active_layer)
    menu.open_child(input_list, id)


## The More button, pressed. Closes an open list the way a second press on a
## `MenuButton` would, rather than reopening under itself.
##
## **Built before it is measured.** `open_under` sizes the list from the rows it
## holds, and `about_to_popup` builds them again only after that, so a list
## built there opens at the height of whatever it held last and scrolls the
## difference.
func _on_more_pressed() -> void:
    if menu.visible:
        menu.hide()
        return
    sync_from_active_layer()
    menu.open_under(more_btn)


## Every button in the row with the size it was actually drawn at, so the claim
## that More is huge beside its neighbours is a number rather than a reading of
## a picture. `min` is the floor the code sets, `asked` is what the control
## works out for itself from its text, its icon and its style box, and `size` is
## what the container gave it. The bug was `asked` being far larger than `min`
## for one button in the row, which then set the height of all four. `at` is
## where it stands in the docker's window, so a claim that the row stays put
## when a ground is picked is a number too.
##
## The four operation buttons are listed in their place, each saying whether it
## is folded into the More menu, whether it is dimmed and what its hover says.
## More's entry carries where its list opened and whether that list scrolls,
## so a claim that the list fits the window is read off the dump.
func button_report() -> Array:
    var out: Array = []
    var buttons: Array = []
    for child in get_children():
        buttons.append_array(op_buttons.get_children() if child == op_buttons else [child])
    for child: Node in buttons:
        var btn := child as Button
        if btn == null:
            continue
        var rect := btn.get_global_rect()
        var asked := btn.get_combined_minimum_size()
        var entry := {
            "name": String(btn.name),
            "text": btn.text,
            "at": {"x": rect.position.x, "y": rect.position.y},
            "size": {"w": rect.size.x, "h": rect.size.y},
            "min": {"w": btn.custom_minimum_size.x, "h": btn.custom_minimum_size.y},
            "asked": {"w": asked.x, "h": asked.y},
            "disabled": btn.disabled,
            "tooltip": btn.tooltip_text,
        }
        if btn.get_parent() == op_buttons:
            entry["folded"] = not op_buttons.holds(btn)
        if btn == more_btn:
            entry["menu"] = _menu_fit()
        out.append(entry)
    return out


## Where the More list stands in its embedder and whether its rows scroll: the
## height it wants, in the embedder's units, against the height it was given.
func _menu_fit() -> Dictionary:
    var wanted := roundi(menu.wanted_size(0.0).y * menu.content_scale_factor)
    return {
        "open": menu.visible,
        "rect": {"x": menu.position.x, "y": menu.position.y, "w": menu.size.x, "h": menu.size.y},
        "wanted_h": wanted,
        "scrolls": menu.visible and menu.size.y < wanted,
    }


## The titles the menu offers, in order, for a test that reads the row
## without popping a window.
func menu_titles() -> PackedStringArray:
    return PackedStringArray(menu.row_labels())


func _document() -> SaDocument:
    if target_canvas == null:
        return null
    return target_canvas.document


## Adds a plain paint layer, without asking: the arrow beside this button is
## where a kind is chosen, so the plus button itself is one click, one layer,
## whatever else the registry holds.
func add_layer() -> void:
    if _document() == null:
        return
    var registry := layer_types
    if registry == null:
        # No registry bound at all: a host that does not use layer types, and a
        # plain layer is what this button means there.
        _add_layer_of_type(&"")
        return
    if registry.list_descriptors().is_empty():
        # A registry that is bound and empty is broken, not minimal. The skeleton
        # registers the plain layer through the same API a module uses, so
        # nothing here has anything to add and saying so is the point: an API
        # door only the built-ins can walk through is not a door.
        push_error("LayersDocker: no layer type is registered, so there is nothing to add.")
        return
    _add_layer_of_type(SaLayerTypeDescriptor.PLAIN)


## Every registered kind the arrow can add, `SaLayerMenuRows.addable`, which
## is the list the Layer menu's kinds are drawn from too.
func _addable_types() -> Array[SaLayerTypeDescriptor]:
    return SaLayerMenuRows.addable(layer_types)


## The registry's own kinds and nothing else. Group was the last row, and added
## nothing: it wrapped what was picked, which the Group button beside More and
## the Layer menu's Group already do.
func open_add_type_menu() -> void:
    fill_add_type_menu()
    _add_type_menu.open_under(add_type_btn)


## The rows the arrow offers, filled again on every open because a module can
## register a kind while the app runs. A kind's icon is a row argument, so the
## list draws it at the row's height rather than at the texture's, and its hint
## is the row's hover, as it is on the Layer menu's row. Public, so a test reads
## the rows without a window on screen. The grounds are one Ground row last,
## `SaGroundChoice`'s, as on the Layer menu.
func fill_add_type_menu() -> void:
    _add_type_menu.clear()
    for descriptor: SaLayerTypeDescriptor in _addable_types():
        if SaGeneratedLayer.answers_height(descriptor):
            continue
        var words := tr(SaLayerMenuRows.kind_words(descriptor))
        _add_type_menu.add_row(descriptor.id, words, false, false, descriptor.icon_name, SaLayerMenuRows.kind_hint(descriptor))
        _add_type_menu.label_button(descriptor.id).tooltip_text = tr(descriptor.hint)
    SaGroundChoice.new(_document(), layer_types).draw_row(_add_type_menu)


## Opens the Ground row's list beside the arrow's rows and answers it, a pick
## there reaching the rows' `run` as any other row of the arrow does.
func open_grounds() -> SaChoicePopup:
    return SaGroundChoice.new(_document(), layer_types).open_beside(_add_type_menu, _on_add_type_chosen)


## A row's id is the kind's own id rather than its place in the list, so a press
## answers the kind it was drawn for even if the registry moved after. Added
## through `SaLayerMenuRows.run`, the call the Layer menu's kind rows make, so
## an adjustment or an effect layer opens the filter browser from both. The
## browser is Main's child in the app, and this row's without a tree, where a
## suite reaches it.
func _on_add_type_chosen(id: StringName) -> void:
    var host: Node = get_tree().current_scene if is_inside_tree() else self
    SaLayerMenuRows.new(_document(), null, layer_types).run(id, host)


## The one place this docker adds a layer, so the button and the type menu cannot
## drift apart. An empty id is the plain layer.
func _add_layer_of_type(type_id: StringName) -> void:
    var doc := _document()
    if doc == null:
        return
    SaLayerOps.new(doc).add(type_id, layer_types)


## Every picked row, or the active layer alone when the docker has no list to
## ask. The one door the actions below go through, so a set of one behaves
## exactly the way the active layer alone would.
func _picked() -> Array[SaLayer]:
    var doc := _document()
    if doc == null:
        return []
    # Not a ternary: its untyped `[]` is a script error once the docker's
    # buttons ask this with no list, which the Merge Down button does.
    var chosen: Array[SaLayer] = []
    if list != null:
        chosen = list.selected_layers()
    if chosen.is_empty() and doc.active_layer != null:
        chosen.append(doc.active_layer)
    return chosen


## Gives every picked row the colour of the Colour list's row *key*, as one step.
func _on_color_chosen(key: StringName) -> void:
    var id: Variant = SaLayerColorList.color_of(key)
    if id != null:
        set_color(id)


## Gives every picked row the colour *id*, one of `SaLayerColorTag.IDS`, as one
## step. False when nothing changed.
func set_color(id: StringName) -> bool:
    var doc := _document()
    return doc != null and SaLayerColorTag.new(doc).write(_picked(), id)


## The minus under the list: the picked mask alone as one Delete Mask step,
## the picked filter while a filter's row holds the pick, and the picked layers
## otherwise.
func delete_picked() -> void:
    if SaLayerMinus.take_mask(_document()):
        return
    if _picked_record() != null:
        delete_filter()
    else:
        delete_layer()


## Takes the picked filter off the node it hangs under, the document's root for
## a global one, as one Detach Filter step. The node's pixels are not touched,
## which is what tells it apart from Flatten. Answers whether a record came off.
func delete_filter() -> bool:
    var doc := _document()
    var record := _picked_record()
    if doc == null or record == null:
        return false
    return SaFilterOps.new(doc).detach(SaFilterMaskRange.node_holding(doc, record), record)


## Turns the picked filter into an adjustment layer at the top of the node it
## hangs under, the document's for a global one, named after the filter, as one
## step. Answers the layer, or null when the conversion refused.
func convert_filter_to_layer() -> SaLayer:
    var doc := _document()
    var record := _picked_record()
    if doc == null or record == null:
        return null
    var holder := SaFilterMaskRange.node_holding(doc, record)
    var layer := SaFilterConversion.new(doc).to_layer(holder, record, layer_types, _title_of(record.key))
    # The record is the new layer's now and the layer is active, so the pick
    # goes back to the layer's row, and the menu offers the way back.
    if layer != null and list != null:
        list.picked.pick_filter(null)
    return layer


## Turns the active adjustment layer back into attached filters on the node it
## sits at the top of, as one step. Answers whether it did.
func convert_layer_to_filter() -> bool:
    var doc := _document()
    if doc == null:
        return false
    return SaFilterConversion.new(doc).to_record(doc.active_layer)


## Why the picked filter cannot become an adjustment layer, or empty when it
## can, which is the row's hint and its dimming.
func _conversion_refusal() -> String:
    var doc := _document()
    var record := _picked_record()
    if doc == null or record == null:
        return tr("No filter is selected.")
    if layer_types == null:
        return tr("No module registers the adjustment layer.")
    return SaFilterConversion.new(doc).layer_refusal(SaFilterMaskRange.node_holding(doc, record), record)


## The title of the filter registered under *key*, or empty when no installed
## module answers for it, and the adjustment layer is then named after its kind.
func _title_of(key: StringName) -> String:
    var main_node: Node = get_tree().current_scene if is_inside_tree() else null
    var registries: SaRegistries = null
    if main_node != null:
        registries = main_node.get("registries") as SaRegistries
    var found: SaFilter = registries.filters.get_filter(key) if registries != null else null
    return found.translated_title() if found != null else ""


## Ground live while the document has a ground and dimmed with the reason
## without one.
func _sync_ground() -> void:
    var on_ground := SaGroundRows.ground_of(_document(), layer_types) != null
    ground_btn.disabled = not on_ground
    ground_btn.tooltip_text = tr(GROUND_HINT) if on_ground else tr(GROUND_DIMMED_HINT)


## The minus's hover, for the row that holds the pick now.
func _sync_delete_hint() -> void:
    minus.follow(_document(), _picked_record())


func delete_layer() -> void:
    var doc := _document()
    if doc == null:
        return
    SaLayerOps.new(doc).remove_many(_picked())


func duplicate_layer() -> void:
    var doc := _document()
    if doc == null:
        return
    # One step for the whole set, a group and its child copied once.
    SaLayerDuplicate.new(doc).write(SaLayerStack.roots(doc, _picked()))


func clear_layer() -> void:
    var doc := _document()
    if doc == null:
        return
    SaLayerSetStep.new(doc).clear(_picked())
    target_canvas.request_composite()


## Every picked row merged into the lowest of them, and the active layer into
## the one under it when one row is picked, as it always was.
func merge_down() -> void:
    var doc := _document()
    if doc == null or doc.active_layer == null:
        return
    SaLayerOps.new(doc).merge_down(doc.active_layer, _picked())


## The three rows the dropdown took from the Layer menu, each the operation
## its command runs, on the active layer or the whole stack.
func bake() -> void:
    var doc := _document()
    if doc != null and doc.active_layer != null:
        SaLayerOps.new(doc).bake(doc.active_layer)


## The Layer menu's Rasterize Impasto on the docker's own canvas, which is the
## main easel's in the app and the suite's own in a suite.
func _rasterize_impasto() -> void:
    var easel := target_canvas.easel if target_canvas != null else null
    if easel != null and easel.document != null:
        SaRasterizeImpasto.new(easel).rasterize(easel.document.active_layer)


## The Layer menu's Rasterize Layer on the docker's own canvas, as above.
func _rasterize_layer() -> void:
    var easel := target_canvas.easel if target_canvas != null else null
    if easel != null and easel.document != null:
        SaRasterizeLayer.new(easel).rasterize(easel.document.active_layer)


func flip_clip() -> void:
    var doc := _document()
    if doc != null and doc.active_layer != null:
        SaLayerFlagStep.new(doc).write(_picked(), &"clip", not doc.active_layer.clip_to_below)


func flatten() -> void:
    var doc := _document()
    if doc != null:
        SaLayerOps.new(doc).flatten()


func move_layer(delta: int) -> void:
    var doc := _document()
    if doc == null:
        return
    var chosen := _picked()
    if chosen.size() > 1:
        SaLayerSetStep.new(doc).move(chosen, delta)
        return
    var layer := doc.active_layer
    if layer != null and layer.is_group:
        SaLayerOps.new(doc).place(layer, SaLayerStack.parent_of(layer), _group_slot(layer, delta))
    else:
        SaLayerOps.new(doc).move(layer, delta)


## Where a group lands moved by *delta*. It moves with its subtree, which is a
## placement rather than a move of one child, and a placement counts from the
## bottom of that block while the group's own node sits on top of it.
func _group_slot(group: SaLayer, delta: int) -> int:
    var block := SaLayerOps.new(_document()).subtree(group).size()
    return group.get_index() - block + 1 + delta


## Wraps the active layer in a group and makes the group active, so the next
## look at the menu offers Ungroup and Blend Group on Its Own for it, or
## dissolves the active group. The Grp button left the wrapped layer active,
## and the menu then read as if nothing had happened.
func toggle_group() -> void:
    var doc := _document()
    if doc == null or doc.active_layer == null:
        return
    var groups := SaLayerOps.new(doc)
    var chosen := _picked()
    if chosen.size() == 1 and doc.active_layer.is_group:
        groups.ungroup(doc.active_layer)
    else:
        # Several picked rows become one group. One picked row is what it always
        # was, which is the same call with a list of one.
        var group := groups.group_layers(chosen)
        if group != null:
            doc.set_active_layer(group)


## Blend Group on Its Own ticked or not, which is isolated or pass-through, for
## a group. Nothing on a layer, because it means nothing there.
func set_isolated(pressed: bool) -> void:
    var doc := _document()
    if doc == null or doc.active_layer == null or not doc.active_layer.is_group:
        return
    SaLayerOps.new(doc).set_isolated(doc.active_layer, pressed)


func set_paint_lock(pressed: bool) -> void:
    var doc := _document()
    if doc == null:
        return
    SaLayerFlagStep.new(doc).write(_picked(), &"paint", pressed)


func set_alpha_lock(pressed: bool) -> void:
    var doc := _document()
    if doc == null:
        return
    SaLayerFlagStep.new(doc).write(_picked(), &"alpha", pressed)
