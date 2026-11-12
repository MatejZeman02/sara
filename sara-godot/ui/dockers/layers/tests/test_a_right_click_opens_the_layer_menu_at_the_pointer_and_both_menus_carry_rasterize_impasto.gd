## A right click on a layer's row opens the layer menu at the pointer with its
## rows, and that menu and the docker's More menu are one list that carries
## Rasterize Impasto.
##
## A right click on a layer made an empty background bar at the top-left
## instead of the list that chooses to rasterize the layer or set a colour for
## it. The press was handed to the menu
## in the docker window's own coordinates, where the list is placed in its
## embedder's, so a docker anywhere but the embedder's corner opened the list
## off the pointer, and `reset_size` sized the list by its scroll box, which
## asks for no height, so it opened as an empty bar.
##
## The docker stands in a host that embeds its windows at (400, 100), so its own
## coordinates and the list's are as far apart as a floating docker's and the
## screen's. A docker let out into a window of the system cannot be shown here,
## because a window mapped while the root does not embed stalls the runner
## (`render/cursor/tests/test_cursor_modes.gd`), so the let-out half is a
## scenario in `scenarios/`, named after it and run under mutter, which
## reads the list at the pointer in screen pixels.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")

const RASTERIZE := &"layer_rasterize_impasto"
const DOCKER_AT := Vector2i(400, 100)

var _host: SubViewport = null
var _docker: LayersDocker = null
var _doc: SaDocument = null
var _lower: SaLayer = null
var _upper: SaLayer = null


func before_each() -> void:
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = SubViewport.new()
    _host.name = "MenuHost"
    _host.size = Vector2i(1400, 1300)
    _host.gui_embed_subwindows = true
    _host.render_target_update_mode = SubViewport.UPDATE_DISABLED
    EventBus.add_child(_host)
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    _host.add_child(canvas)
    _docker = LayersDockerScript.new()
    _docker.name = "LayersDocker"
    _docker.target_canvas = canvas
    canvas.add_child(_docker)
    _docker.size = Vector2i(360, 600)
    _docker.position = DOCKER_AT
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


func _row_of(layer: SaLayer) -> SaRowFrame:
    for i: int in _docker.item_list.rows.size():
        if _docker.item_list.layer_at(i) == layer:
            return _docker.item_list.rows[i]
    return null


## A right press at the middle of *layer*'s name, pushed into the docker's
## window as the display server hands it one, and answered with the point it
## landed on in the host's space, the docker's corner added.
func _right_click(layer: SaLayer) -> Vector2:
    _docker.show()
    _lay_out()
    var at := _row_of(layer).lbl.get_global_rect().get_center()
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_RIGHT
    event.button_mask = MOUSE_BUTTON_MASK_RIGHT
    event.pressed = true
    event.position = at
    event.global_position = at
    _docker.push_input(event)
    return Vector2(DOCKER_AT) + at


## Ridges of height over *layer*'s first cell, so it has a relief to rasterise.
func _raise_relief(layer: SaLayer) -> void:
    SaHeightOps.new(_doc).gain(layer)
    var texture := layer.get_or_create_field(Vector2i.ZERO, SaFieldSpec.HEIGHT)
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * 2)
    for y in texture.size.y:
        for x in texture.size.x:
            bytes.encode_half((y * texture.size.x + x) * 2, 1.5 * (0.5 + 0.5 * sin(TAU * float(x) / 24.0)))
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)


func test_the_right_click_menu_opens_at_the_pointer_with_its_rows() -> void:
    var pointer := _right_click(_lower)
    var menu := _docker.actions.menu
    assert_true(menu.visible, "The right press opens the menu")
    assert_true(menu.is_embedded(), "in the host, the way a docked docker's list opens")
    assert_true(menu.row_ids().size() > 10, "with its rows built: %s" % [menu.row_ids()])
    var rect := Rect2i(menu.position, menu.size)
    assert_true(rect.has_point(Vector2i(pointer)), "and its rectangle %s holds the press at %s" % [rect, pointer])
    assert_true(menu.size.y > 300, "tall enough for its rows, not the empty bar: %s" % menu.size)
    var docker_local := pointer - Vector2(DOCKER_AT)
    assert_false(rect.has_point(Vector2i(docker_local)), "which the press in the docker's own coordinates would miss")
    menu.hide()


## The right click carries the whole Layer
## menu, so what is held now is the More button's rows in their order among it.
func test_the_right_click_reads_the_more_buttons_rows_in_their_order() -> void:
    var menu := _docker.actions.menu
    # Laid out first, as a right press lays it out, so the four operation
    # buttons stand on the row for both opens and neither folds them in.
    _docker.show()
    _lay_out()
    _docker.actions.more_btn.pressed.emit()
    assert_true(menu.visible, "The More button opens the menu")
    var from_more := menu.row_ids()
    menu.hide()
    _right_click(_doc.active_layer)
    assert_true(menu.visible, "and so does a right press")
    var at_pointer := menu.row_ids()
    var shared := at_pointer.filter(func(id: StringName) -> bool: return from_more.has(id))
    assert_eq(shared, from_more, "with the More button's rows in the same order among its own")
    assert_true(at_pointer.has(&"layer_delete"), "and the rows the buttons stand for, Delete Layer among them")
    assert_true(from_more.has(RASTERIZE), "Rasterize Impasto among them")
    assert_eq(from_more.find(RASTERIZE), from_more.find(&"layer_bake") + 1, "beside Bake")
    menu.hide()


func test_rasterize_impasto_is_dimmed_on_a_layer_with_no_relief() -> void:
    _right_click(_lower)
    var menu := _docker.actions.menu
    assert_true(menu.is_disabled(RASTERIZE), "A layer with no relief has the row dimmed")
    assert_false(menu.press_row(RASTERIZE), "and a press does nothing")
    menu.hide()


func test_rasterize_impasto_on_the_right_click_menu_clears_the_height() -> void:
    _raise_relief(_upper)
    assert_true(_upper.carries_height(), "The layer has a relief")
    _right_click(_upper)
    var menu := _docker.actions.menu
    assert_eq(_doc.active_layer, _upper, "The right press picks the row it landed on")
    assert_false(menu.is_disabled(RASTERIZE), "and the row is lit for its relief")
    var steps := _doc.history.step_count()
    assert_true(menu.press_row(RASTERIZE), "Rasterize Impasto is pressed")
    assert_false(_upper.carries_height(), "and the height is gone")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step, the Layer menu's")
    assert_true(_doc.undo(), "which Ctrl+Z has")
    assert_true(_upper.carries_height(), "and gives the relief back")
