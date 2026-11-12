## Add Mask makes the mask what the brush paints.
##
## The Photoshop hour, finding 8: after Add Mask the painter's first stroke
## laid black paint on the layer, because the add left `mask_target` alone. A
## mask is added here by the Layers docker's button, by the Layer menu's row and
## by the command, a stroke is painted, and the mask is read changed and the
## layer's texels not. Undo of the add takes the aim off with the mask, a redo
## puts it back, a group's mask takes the aim as a layer's does, and a picked
## set leaves the lead row's mask aimed at. The running app's half is
## `scenarios/add-mask-makes-the-mask-what-the-brush-paints.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLACK := Color(0.0, 0.0, 0.0, 1.0)
## Where the stroke lands, inside the first chunk.
const AT := Vector2i(60, 60)

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _canvas: SaCanvas = null
var _layers: LayersDocker = null
var _bar: TopMenuBar = null
var _doc: SaDocument = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _registries = Fixtures.make_registries(_surface)
    _doc = _surface.easel.document
    _doc.fill_layer(RED, _doc.active_layer)
    _canvas = SaCanvas.new()
    _canvas.easel = _surface.easel
    _layers = LayersDocker.new()
    _layers.target_canvas = _canvas
    _layers.list_keeper.listen()
    _layers.sync_layer_list()


func after_each() -> void:
    if _bar != null:
        _bar.free()
        _bar = null
    _layers.free()
    _canvas.free()
    _registries = null
    _doc = null
    Fixtures.teardown(_surface)
    _surface = null


## The press on the docker's Add Mask button.
func _by_button() -> void:
    _layers.actions.sync_from_active_layer()
    _layers.actions.op_buttons.button(SaMaskOps.ADD).pressed.emit()


## The press on the Layer menu's Add Mask row, the menu bound as the app binds it.
func _by_menu() -> void:
    _bar = TopMenuBar.new()
    _bar._ready()
    _bar.bind_commands(_registries.commands)
    var menu := _bar.menu("Layer") as SaLayerMenu
    menu.document = _doc
    menu.populate()
    var row := SaMenu.key(SaLayerMenuRows.number_of(SaMaskOps.ADD))
    assert_true(SaMenu.list_holding(menu.popup, row).press_row(row), "the row takes the press, under Mask")


## The command, which the chord and the search run.
func _by_command() -> void:
    assert_true(_registries.commands.execute(SaMaskOps.ADD), "the command runs")


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


## The coverage *mask* holds at *at*, one where it holds nothing.
func _coverage(mask: SaMask, at: Vector2i) -> float:
    var texture := mask.texture_for(Vector2i.ZERO)
    return 1.0 if texture == null else _texel(texture, at).r


## The layer's colour at *at*.
func _paint(layer: SaLayer, at: Vector2i) -> Color:
    return _texel(layer.get_field(Vector2i.ZERO), at)


## One black stroke of one dab, opened and committed the way the brush does,
## onto whatever the document aims the brush at.
func _stroke() -> void:
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var compute := PaintKernel.compute()
    var paint := SaPaintContext.for_region(_doc, Rect2(Vector2(AT) - Vector2(10, 10), Vector2(20, 20)), false)
    paint.dispatch_batch(
        compute,
        "paint",
        func(target: SaPaintContext.Target) -> void:
            compute.set_texture(0, target.texture.rid)
            compute.set_push_constant_float_array(
                PaintKernel.pack_params(paint.local_point(target, Vector2(AT)), target.render_offset, BLACK, 10.0, 1.0, 1.0, 1.0)
            )
    )
    paint.commit_invalidation()
    _doc.commit_stroke()


## *add* gives the active layer a mask the brush paints, and a stroke changes the
## mask and leaves the layer's red.
func _adds_and_paints(add: Callable, how: String) -> void:
    var layer := _doc.active_layer
    var steps := _doc.history.step_count()
    add.call()
    assert_not_null(layer.mask, "%s gives the layer a mask" % how)
    assert_eq(_doc.mask_target, layer.mask, "%s makes the mask what the brush paints" % how)
    assert_eq(_doc.history.step_count(), steps + 1, "%s is one step" % how)
    assert_eq(_doc.undo_redo.get_current_action_name(), "Add Mask", "%s keeps the single row's name" % how)
    _stroke()
    assert_almost_eq(_coverage(layer.mask, AT), 0.0, 1e-6, "%s: the stroke hides on the mask" % how)
    assert_almost_eq(_paint(layer, AT).r, 1.0, 1e-6, "%s: the layer stays red under the stroke" % how)
    assert_almost_eq(_paint(layer, AT).a, 1.0, 1e-6, "%s: and opaque" % how)


func test_the_docker_s_button_aims_the_brush_at_the_mask() -> void:
    _adds_and_paints(_by_button, "the docker's button")


func test_the_layer_menu_s_row_aims_the_brush_at_the_mask() -> void:
    _adds_and_paints(_by_menu, "the Layer menu's row")


func test_the_command_aims_the_brush_at_the_mask() -> void:
    _adds_and_paints(_by_command, "the command")


## Undo of the add takes the mask and the aim off together, a redo puts both
## back, and a stroke once the add is undone lands on the layer.
func test_undo_takes_the_aim_off_with_the_mask_and_redo_puts_it_back() -> void:
    var layer := _doc.active_layer
    _by_button()
    assert_true(_doc.undo(), "the add undoes")
    assert_null(layer.mask, "the mask is gone")
    assert_null(_doc.mask_target, "and the brush paints no mask")
    assert_true(_doc.redo(), "the add redoes")
    assert_not_null(layer.mask, "the mask is back")
    assert_eq(_doc.mask_target, layer.mask, "and the brush paints it again")
    assert_true(_doc.undo(), "the add undoes once more")
    _stroke()
    assert_almost_eq(_paint(layer, AT).r, 0.0, 1e-6, "the stroke lands on the layer")


func test_a_group_s_new_mask_is_what_the_brush_paints() -> void:
    var group := SaLayerOps.new(_doc).group_active()
    _doc.set_active_layer(group)
    _by_command()
    assert_not_null(group.mask, "the group has a mask")
    assert_eq(_doc.mask_target, group.mask, "and the brush paints it")
    _stroke()
    assert_almost_eq(_coverage(group.mask, AT), 0.0, 1e-6, "the stroke hides on the group's mask")


## A picked set takes a mask on every row as one step and leaves the lead row's,
## the active layer's, aimed at.
func test_a_picked_set_aims_at_the_lead_row_s_mask() -> void:
    var other := SaLayerOps.new(_doc).add()
    _doc.fill_layer(RED, other)
    _layers.sync_layer_list()
    var lead := _doc.active_layer
    _doc.picked.pick([lead, other] as Array[SaLayer])
    _doc.set_active_layer(lead)
    var steps := _doc.history.step_count()
    _by_command()
    assert_not_null(other.mask, "the other row has a mask")
    assert_not_null(lead.mask, "and the lead row too")
    assert_eq(_doc.mask_target, lead.mask, "the lead row's mask is what the brush paints")
    assert_eq(_doc.history.step_count(), steps + 1, "in one step")
    assert_true(_doc.undo(), "which undoes")
    assert_null(_doc.mask_target, "taking the aim off")
