## A right click on a layer's row gives it a colour, as Photoshop does.
##
## A layer can be given a colour inside the Layers docker, on a right click on
## the layer. The right click menu carries a Colour row under Rename,
## its list holds No Colour and Photoshop's seven, a choice colours every picked
## row as one step, and the row shows the colour behind its eye.
##
## The docker stands in a host that embeds its windows, the way
## `test_rename_layer_opens_in_the_middle_of_the_main_window.gd` stands it, so
## its rows are laid out and the right press is an `InputEventMouseButton`
## pushed into the docker's window at the row's own middle, which the engine
## carries up to `LayersDocker._on_control_gui_input`. The save's half is
## `core/sad-file/tests/test_a_layer_s_colour_is_saved_with_the_document.gd`,
## and the running app's is `scenarios/a-right-click-on-a-layer-s-row-gives-it-a-colour-as-photoshop-does.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")

var _host: SubViewport = null
var _docker: LayersDocker = null
var _doc: SaDocument = null
var _lower: SaLayer = null
var _upper: SaLayer = null


func before_each() -> void:
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = SubViewport.new()
    _host.name = "ColourHost"
    _host.size = Vector2i(1200, 900)
    _host.gui_embed_subwindows = true
    _host.render_target_update_mode = SubViewport.UPDATE_DISABLED
    EventBus.add_child(_host)
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(128, 128)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    _host.add_child(canvas)
    _docker = LayersDockerScript.new()
    _docker.name = "LayersDocker"
    _docker.target_canvas = canvas
    canvas.add_child(_docker)
    _docker.size = Vector2i(360, 600)
    _docker.position = Vector2i(400, 100)
    _doc = canvas.document
    _lower = _doc.active_layer
    _upper = SaLayerOps.new(_doc).add()
    _docker.sync_layer_list()
    _lay_out()


func after_each() -> void:
    if _host != null:
        _host.free()
    _host = null
    _docker = null
    _doc = null
    _lower = null
    _upper = null


## Sorts every container in the docker, which a frame would, so each row stands
## where it is drawn.
func _lay_out() -> void:
    for container: Node in _docker.find_children("*", "Container", true, false):
        (container as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)


func _list() -> SaLayerList:
    return _docker.item_list


func _row_of(layer: SaLayer) -> SaRowFrame:
    for i in _list().rows.size():
        if _list().layer_at(i) == layer:
            return _list().rows[i]
    return null


func _report(layer: SaLayer) -> Dictionary:
    var row := _row_of(layer)
    return row.report() if row != null else {}


## A right press at the middle of *layer*'s name, pushed into the docker's
## window as the display server hands it one.
func _right_click(layer: SaLayer) -> void:
    _docker.show()
    _lay_out()
    var row := _row_of(layer)
    var at := row.lbl.get_global_rect().get_center()
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_RIGHT
    event.button_mask = MOUSE_BUTTON_MASK_RIGHT
    event.pressed = true
    event.position = at
    event.global_position = at
    _docker.push_input(event)


## The Colour row pressed and *id*'s row of the list beside it.
func _choose(id: StringName) -> void:
    var menu := _docker.actions.menu
    assert_true(menu.press_row(SaLayerActions.COLOUR), "The menu holds a Colour row")
    var colours := _docker.actions.color_list
    assert_true(colours.visible, "which opens the colours beside the menu")
    assert_eq(colours.row_ids().size(), 8, "No Colour and Photoshop's seven")
    assert_true(colours.press_row(SaLayerColorList.row_id(id)), "and %s is pressed" % id)


func test_a_right_click_and_green_colours_the_row_as_one_step() -> void:
    _doc.set_active_layer(_upper)
    _docker.sync_layer_list()
    _lay_out()
    _right_click(_lower)
    var menu := _docker.actions.menu
    assert_true(menu.visible, "The right press opens the menu")
    assert_eq(_doc.active_layer, _lower, "on the row it landed on")
    assert_eq(menu.row_labels().find("Colour"), menu.row_labels().find("Rename...") + 1, "Colour stands under Rename")

    var steps := _doc.history.step_count()
    _choose(&"green")
    assert_eq(_lower.color_tag, &"green", "The layer is green")
    assert_eq(_upper.color_tag, &"", "and the one above it is not")
    assert_eq(_doc.history.step_count(), steps + 1, "one new history step")
    assert_false(menu.visible, "and the choice closes the menu")
    var report := _report(_lower)
    assert_eq(report.get("color_tag"), "green", "The row says green")
    assert_eq(report.get("tint"), SaLayerRowView.tint_of(&"green").to_html(), "and is tinted green behind its eye")
    assert_true(_row_of(_lower).color_tint.color.a > 0.0, "a tint that shows")
    var row := _row_of(_lower)
    var tint_box := row.color_tint.get_global_rect()
    assert_true(
        tint_box.size.x >= row.size.x - 16.0 and tint_box.size.y >= row.size.y - 8.0,
        "and it covers the whole row, not the eye's square (%s in %s)" % [tint_box.size, row.size]
    )
    assert_true(row.color_tint.get_parent() == row, "as a layer of the row itself")

    assert_true(_doc.undo(), "Ctrl+Z has the step")
    assert_eq(_lower.color_tag, &"", "and undoes it to No Colour")
    assert_eq(_row_of(_lower).color_tint.color.a, 0.0, "with no tint on the row")


func test_the_list_ticks_the_colour_the_row_has() -> void:
    SaLayerColorTag.new(_doc).write([_lower], &"orange")
    _right_click(_lower)
    var menu := _docker.actions.menu
    menu.press_row(SaLayerActions.COLOUR)
    var colours := _docker.actions.color_list
    assert_true(colours.is_checked(SaLayerColorList.row_id(&"orange")), "Orange is ticked")
    assert_false(colours.is_checked(SaLayerColorList.row_id(&"")), "and No Colour is not")
    menu.hide()


func test_a_colour_on_a_picked_pair_is_one_step() -> void:
    _doc.set_active_layer(_upper)
    _docker.sync_layer_list()
    _list().picked.select(_list().rows.find(_row_of(_upper)))
    _list().picked.select_extra(_list().rows.find(_row_of(_lower)))
    assert_eq(_list().selected_layers().size(), 2, "Both rows are picked")
    SaLayerColorTag.new(_doc).write([_upper], &"red")
    var steps := _doc.history.step_count()
    assert_true(_docker.actions.set_color(&"blue"), "Blue is given")
    assert_eq([_upper.color_tag, _lower.color_tag], [&"blue", &"blue"], "to both picked rows")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_true(_doc.undo(), "and one Ctrl+Z")
    assert_eq([_upper.color_tag, _lower.color_tag], [&"red", &""], "gives each its own colour back")


func test_a_group_takes_a_colour_too() -> void:
    var group := SaLayerOps.new(_doc).group_layers([_upper])
    _docker.sync_layer_list()
    _lay_out()
    _right_click(group)
    assert_eq(_doc.active_layer, group, "The right press picks the group")
    _choose(&"violet")
    assert_eq(group.color_tag, &"violet", "and the group is violet")
    assert_eq(_report(group).get("tint"), SaLayerRowView.tint_of(&"violet").to_html(), "on its row too")


## Every colour's tint is thin enough for the eye to read over it, and no two
## of the seven are the same.
func test_the_seven_tints_are_seven() -> void:
    var seen := {}
    for id: StringName in SaLayerColorTag.IDS:
        var tint := SaLayerRowView.tint_of(id)
        if id.is_empty():
            assert_eq(tint.a, 0.0, "No Colour draws nothing")
            continue
        assert_true(tint.a > 0.0 and tint.a < 1.0, "%s is a tint, not a fill" % id)
        seen[tint.to_html()] = true
    assert_eq(seen.size(), 7, "Seven colours, seven tints")
