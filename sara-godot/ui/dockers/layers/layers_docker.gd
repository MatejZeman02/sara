## Floating layers docker window for managing document layer stack.
##
## The list is `SaLayerList`, filled from the document and answered by an
## `SaLayerListKeeper`, the blend and opacity rows above it are
## `SaLayerBlendOpacityRow`, which follows the active layer itself, and the row
## of actions under the list is `SaLayerActions`, each in its own file. What stays
## here is the docker's own: the window and the order of its elements, the
## rename window, the menu a right press opens and the controls that follow the
## keeper. A ground's rows, which ground it is and how it is tuned, are
## `SaGroundRows`, in the dialog window `SaGroundDialog` the Ground button
## under the list opens, so the column is the same height whichever layer is
## active.
@tool
extends DockerWindow

class_name LayersDocker

const LayerRenameDialogScript = preload("res://ui/dockers/layers/layer_rename_dialog.gd")

## The "Layer" in front of the blend dropdown, the row's own, kept by this name
## for the readers that knew it here.
const LABEL_FONT_SCALE := SaLayerBlendOpacityRow.LABEL_FONT_SCALE

var item_list: Control
## What fills `item_list` from the document and answers its presses, drops and
## folds.
var list_keeper: SaLayerListKeeper
## The blend dropdown and the opacity slider, each on a row of its own above
## the list, which follow the active layer of the canvas handed to them.
var blend_row: SaLayerBlendOpacityRow
## The row's dropdown and slider, kept by these names for the readers that knew
## them here, the menu driver and the suites.
var blend_mode_opt: BlendModeButton
var opacity_slider: FactorSlider
## The rows of the active layer when it is a ground, the paper or the canvas,
## and the dialog window they open in from the Ground button.
var ground_rows: SaGroundRows
var ground_dialog: SaGroundDialog
## The document the grounds below were taken from, and its grounds at the last
## sync, so a ground added after it opens its dialog.
var _grounds_seen_in: SaDocument = null
var _grounds_seen: Array[SaLayer] = []
## The ground's tooth slider, the one in `ground_rows`, kept by this name for
## the readers that knew it here.
var tooth_slider: FactorSlider
var actions: SaLayerActions

## The layer types the add button offers. Null until main binds it, in which case
## the button adds a plain layer, which is what it always did.
var layer_type_registry: SaLayerTypeRegistry = null

## The keeper is handed the canvas last, because its rebuild of the rows is what
## the actions and the ground rows follow, and they need the canvas first.
var target_canvas: SaCanvas = null:
    set(val):
        target_canvas = val
        if actions != null:
            actions.target_canvas = val
        if blend_row != null:
            blend_row.target_canvas = val
        if list_keeper != null:
            list_keeper.target_canvas = val

## Where a filter row's title comes from and where its panel is shown, the
## keeper's, handed on from here for the suites that give them to a docker.
var filter_registry: SaFilterRegistry = null:
    set(val):
        filter_registry = val
        if list_keeper != null:
            list_keeper.filter_registry = val
var tool_options: ToolOptionsDocker = null:
    set(val):
        tool_options = val
        if list_keeper != null:
            list_keeper.tool_options = val

## The keeper's folded groups, the one set and not a copy, kept by this name for
## the suite that reads which groups are shut.
var _closed_groups: Dictionary

## The rename dialog on the actions menu. Null until the first rename, because a
## docker built at boot would otherwise carry a window nobody opened.
var _rename_dialog: SaLayerRenameDialog = null


func _init() -> void:
    # A floor of its own rather than DockerWindow's 80x80, under which every
    # row overflows the window. 200x200 is the width the actions row needs
    # with the corner held open, measured from the row's own rects.
    _init_docker(SaDockerIds.LAYERS, "Layers", Vector2i(260, 420), Vector2i(200, 200))

    var vbox := SaMake.column(_control_node, "VBoxContainer")
    vbox.set_anchors_preset(Control.PRESET_FULL_RECT)

    drag_handle = DockerUtils.make_drag_bar("Layers")
    vbox.add_child(drag_handle)

    var margin := SaMake.margin(vbox, "MarginContainer", SaUI.BASE_MARGIN)
    margin.size_flags_vertical = Control.SIZE_EXPAND_FILL

    var inner_vbox := SaMake.column(margin, "InnerVBox", SaUI.BASE_SEPARATOR)
    inner_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

    blend_row = SaLayerBlendOpacityRow.with_views(SaDockerIds.LAYERS)
    inner_vbox.add_child(blend_row)
    blend_mode_opt = blend_row.blend_mode_opt
    opacity_slider = blend_row.opacity_slider

    var list := SaLayerList.new()
    item_list = list
    item_list.name = "ItemList"
    item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    inner_vbox.add_child(item_list)
    item_list.unique_name_in_owner = true
    item_list.owner = self
    list_keeper = SaLayerListKeeper.new(list)
    list_keeper.followed.connect(_sync_controls_from_active_layer)
    _closed_groups = list_keeper._closed_groups

    actions = list_keeper.with_views(SaDockerIds.LAYERS, SaLayerActions.new(item_list))
    actions.rename_requested.connect(open_rename_dialog)
    actions.ground_pressed.connect(toggle_ground_dialog)
    inner_vbox.add_child(actions)

    # Not in the column: every row a ground added there came out of the list,
    # the one child that expands, and moved the buttons under it.
    # Seated beside the docker on its first open, not in it.
    ground_dialog = SaGroundDialog.new()
    ground_rows = ground_dialog.rows
    tooth_slider = ground_rows.tooth_slider

    # A right press anywhere the rows and the controls do not take opens the
    # same menu the More button holds, on the row under the pointer when
    # there is one.
    _control_node.gui_input.connect(_on_control_gui_input)


func _ready() -> void:
    assert(drag_handle != null, "DragHandle node not found")
    assert(item_list != null, "ItemList node not found")

    _setup_docker_ready()

    # The keeper answers the list from here, as the docker did, and builds the
    # rows when the canvas came first.
    list_keeper.listen()
    item_list.note_pressed.connect(_on_note_pressed)
    item_list.ground_opened.connect(_on_ground_opened)

    if not SaSettings.profile_changed.is_connected(apply_layout_settings):
        SaSettings.profile_changed.connect(apply_layout_settings)
    apply_layout_settings()


## The keeper's work under the names it had here, for the suites that drive a
## docker which never reaches the tree and so never listens: they rebuild the
## rows, fold a group, drop a row and show a filter through these, and ask
## whether the rows are the document's stack.
func sync_layer_list() -> void:
    list_keeper.sync()


func _rows_match_document() -> bool:
    return list_keeper.rows_match_document()


func _on_group_toggled(index: int) -> void:
    list_keeper.toggle_group(index)


func _on_row_dropped(from_idx: int, to_idx: int, edge: SaLayerList.Drop) -> void:
    list_keeper.drop(from_idx, to_idx, edge)


func _on_filter_selected(record: SaAttachedFilter) -> void:
    list_keeper.show_filter(record)


func _on_document_changed() -> void:
    list_keeper.follow_document()


static func drop_index(layer: SaLayer, target: SaLayer, edge: SaLayerList.Drop) -> int:
    return SaLayerListKeeper.drop_index(layer, target, edge)


## The document's active layer, or null without a document.
func active_layer() -> SaLayer:
    if target_canvas == null or target_canvas.document == null:
        return null
    return target_canvas.document.active_layer


## Opens the rename dialog on the active layer. The actions menu and a row's
## note mark are where the press comes from, and the write itself belongs to the
## dialog, so the suite proves what OK does against a real document without a
## docker on screen. Built on first use and kept, the way `MainDialogs` keeps
## the windows it opens, and centred on the main window by the dialog every
## time it opens, wherever the last one was left.
## *at_note* puts the keyboard in the note rather than the name. False when
## there is no layer to name.
func open_rename_dialog(at_note: bool = false) -> bool:
    var doc := target_canvas.document if target_canvas != null else null
    if doc == null or doc.active_layer == null:
        return false
    if _rename_dialog == null:
        _rename_dialog = LayerRenameDialogScript.new()
        add_child(_rename_dialog)
    _rename_dialog.open_for(doc, doc.active_layer, at_note)
    return true


## Rename on F2, Krita's chord for it, and the Layer menu's Rename... row,
## which draws the chord beside it. Registered from here the way the Reference
## docker's solo is, because the rename is this docker's. A command rather than
## the list's own key, so F2 renames over the canvas too and not only while
## this docker holds the keyboard.
static func register_rename(ctx: SaContext) -> void:
    var command := SaCommandDescriptor.create(SaLayerMenuRows.RENAME, "Rename the layer", _rename_in_tree)
    command.label = "Rename..."
    var key := InputEventKey.new()
    key.keycode = KEY_F2
    command.default_events = [key]
    command.category = &"layer"
    command.sentence = "Rename the layer and edit its note."
    ctx.register_command(command)


static func _rename_in_tree() -> bool:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null or tree.root == null:
        return false
    var docker := tree.root.find_child(SaDockerIds.LAYERS, true, false) as LayersDocker
    return docker != null and docker.answer_rename_key()


## What F2 does: the rename window on the active layer. False while this docker
## holds the keyboard, so the key goes on to the list, whose F2 opens the name
## in its row where the painter is looking, and false when there is no layer to
## name.
func answer_rename_key() -> bool:
    return not has_focus() and open_rename_dialog()


## A row's note mark was pressed. The mark sat on every row and answered
## nothing, so a lit one showed a note it would not open and a dimmed one looked
## like a button that was off. Its layer becomes the active one, as a plain
## press on the row makes it, and Rename Layer opens on it with the keyboard in
## the note, which is where the note is read whole and written. The list has
## aimed the brush already, because what a press aims it at is the row's.
func _on_note_pressed(index: int) -> void:
    if item_list.layer_at(index) == null or target_canvas == null or target_canvas.document == null:
        return
    list_keeper.select_row(item_list.picked.press(index, false, false))
    open_rename_dialog(true)


## The action buttons and a ground's rows follow the active layer, and the More
## list only while it is open. That list is built again on every open, so a
## closed one has nothing to follow, and building it on every
## `document_changed` cost 4 ms a change and twice on an attach, whose rows
## rebuild comes back here. The blend and opacity row follows it on its own.
func _sync_controls_from_active_layer() -> void:
    actions.sync_buttons()
    if actions.menu.visible:
        actions.sync_from_active_layer()
    var doc := target_canvas.document if target_canvas != null else null
    if doc == null:
        return
    # The dialog shows the active ground, or the document's uppermost one while
    # a paint layer is active, so a layer made active by PageDown, an undo or a
    # press on a row leaves it open and the Ground button reopens it from any
    # row ("I don't see the settings anywhere").
    ground_dialog.follow(doc, layer_type_registry, self, _ground_just_added(doc))


## Whether the active layer is a ground this document did not hold at the last
## sync, which is a ground just added from the Layer menu or the arrow beside
## the plus. Its dialog opens with it, because its tooth and colours are what a
## painter adds a ground to set. A document opened or switched to is not an
## add, so its grounds are only taken note of.
func _ground_just_added(doc: SaDocument) -> bool:
    var grounds: Array[SaLayer] = []
    for layer: SaLayer in SaLayerOps.new(doc).layers():
        if SaGroundRows.is_ground(layer, layer_type_registry):
            grounds.append(layer)
    var same_document := _grounds_seen_in == doc
    var before := _grounds_seen
    _grounds_seen_in = doc
    _grounds_seen = grounds
    return same_document and SaGroundRows.is_ground(doc.active_layer, layer_type_registry) and not before.has(doc.active_layer)


## The Ground button of *strip*, this docker's or one placed in another: the
## dialog window with the rows of the active ground, or of the document's
## uppermost one, opened beside this docker, or closed when it is open. False
## when the document has no ground, where the button is dimmed. The strip it
## came from is not asked where to open, because a window of its own is moved
## by its strip and stays where the painter leaves it.
func toggle_ground_dialog(_strip: SaLayerActions = null) -> bool:
    var doc := target_canvas.document if target_canvas != null else null
    return ground_dialog.toggle_for(doc, layer_type_registry, self)


## A double click on a ground's picture in the list: the Ground dialog opens,
## and stays open when it shows already.
func _on_ground_opened(_index: int) -> void:
    if not ground_dialog.visible:
        toggle_ground_dialog()


## The Ground dialog hangs from this docker's parent or from nothing, so the
## docker frees it when it goes. The engine calls `DockerWindow`'s own as well.
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE and is_instance_valid(ground_dialog) and ground_dialog.get_parent() != self:
        ground_dialog.free()


func _on_control_gui_input(event: InputEvent) -> void:
    var press := event as InputEventMouseButton
    if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_RIGHT:
        return
    var row: int = -1
    if item_list.has_method("row_at"):
        row = item_list.row_at(press.global_position)
    # A filter's row picks its record, so the menu is that filter's mask's, and
    # a layer's row takes the pick back from any filter, the way a left press on
    # it does.
    var record: SaAttachedFilter = item_list.record_at(row) if row >= 0 else null
    if record != null:
        item_list.picked.pick_filter(record)
    elif row >= 0:
        item_list.picked.pick_filter(null)
        item_list.picked.select(row)
        list_keeper.select_row(row)
    actions.open_menu_at(Vector2(SaPopupRect.at_press(press, _control_node)))
    _control_node.accept_event()


func apply_layout_settings() -> void:
    apply_docker_base_layout(SaDockerIds.LAYERS)

    # Every node here and the drag handle are built in `_init`.
    var inner_vbox := blend_row.get_parent()
    var margin := inner_vbox.get_parent()
    var vbox := margin.get_parent()
    var order := SaSettings.get_layout_order(SaDockerIds.LAYERS)

    var elements_before_drag := 0
    var passed_drag := false
    for elem: String in order:
        if elem == "Drag Handle":
            passed_drag = true
        elif elem != "Resizer" and not passed_drag:
            elements_before_drag += 1

    if elements_before_drag == 0:
        vbox.move_child(drag_handle, 0)
        vbox.move_child(margin, 1)
    else:
        vbox.move_child(margin, 0)
        vbox.move_child(drag_handle, 1)

    # Sort inner elements in inner_vbox. "Locks" left the list: the locks are
    # menu items now, and every row draws them.
    var mapping := {
        "Layer List": item_list,
        "Blend Mode": blend_row.blend_box,
        "Opacity": blend_row.opacity_box,
        "Actions": actions,
    }

    # Blend Mode and Opacity share one column of two rows, placed where the
    # first of the two stands, and a row placed already sits above `current_idx`.
    var current_idx := 0
    for element: String in order:
        var control: Control = mapping.get(element)
        if control != null and control.get_parent() == blend_row:
            control = blend_row
        if control and control.get_parent() == inner_vbox and control.get_index() >= current_idx:
            inner_vbox.move_child(control, current_idx)
            current_idx += 1

    drag_handle.visible = SaSettings.get_element_visible(SaDockerIds.LAYERS, "Drag Handle")
    for elem_name: String in mapping.keys():
        var control: Control = mapping[elem_name]
        control.visible = SaSettings.get_element_visible(SaDockerIds.LAYERS, elem_name)
    blend_row.visible = mapping["Blend Mode"].visible or mapping["Opacity"].visible


## Points the blend dropdown and the add-layer button at their registries and
## keeps both live. The layer type registry is optional so a host that has no
## layer types still gets a working blend dropdown.
func bind_registries(blend_registry: SaBlendModeRegistry, layer_types: SaLayerTypeRegistry = null) -> void:
    blend_row.blend_registry = blend_registry
    blend_row.refresh()
    layer_type_registry = layer_types
    actions.layer_types = layer_types
