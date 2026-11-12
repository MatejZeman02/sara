## A stroke on a mask through a soft selection lays its paint scaled by the
## selection, never nothing.
##
## A mask holds coverage in one float channel, so its texel reads an alpha of
## one. The brush's over rule caps a dab under a selection short of one at what
## the stroke has laid so far, read off that alpha, and so on a mask it found
## the ceiling already reached and laid nothing at all through 0.6 or 0.999.
## One black dab of the real brush is laid through the machine on a layer's mask
## and on a group's, through selections of 1.0, 0.6 and 0.999, and the mask is
## read back at the dab's centre.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Where the dab lands, inside the first chunk.
const AT := Vector2(100.0, 100.0)

## Two levels of an eight bit channel, the tolerance the row was written with.
const LEVELS := 2.0 / 255.0

var _surface: SaSurface = null
var _doc: SaDocument = null
var _machine: ToolMachine = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _doc = _surface.easel.document
    _machine = Fixtures.make_bound_machine(_surface)
    _surface.view.mouse_position = AT


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _doc = null
    _machine = null


## The coverage *mask* holds at document pixel *at*, one where it holds nothing.
func _coverage(mask: SaMask, at: Vector2i) -> float:
    @warning_ignore("integer_division")
    var grid := Vector2i(at.x / SaChunk.SIZE, at.y / SaChunk.SIZE)
    var texture := mask.texture_for(grid)
    if texture == null:
        return 1.0
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x).r


## A selection over the whole document at *value* everywhere: a rectangle,
## whose one chunk is then cleared to the value, as a feather leaves a texel.
func _select(value: float) -> void:
    _doc.selection.select_rect(Rect2i(Vector2i.ZERO, _doc.canvas_size))
    for grid_pos: Vector2i in _doc.selection.grid_positions():
        _doc.selection.get_or_create_chunk(grid_pos).field(SaSelection.FIELD).clear(Color(value, value, value, value))


## One black dab of the brush, a press and a release through the machine.
func _dab() -> void:
    _machine.set_active_tool(&"brush")
    var brush := _machine.active_tool as ToolState
    brush.settings.color = Color(0.0, 0.0, 0.0, 1.0)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = AT
    _machine.handle_input(press)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    release.position = AT
    _machine.handle_input(release)


## How far one dab through a selection of *value* takes the mask *make* answers
## down from what it held, read at the dab's centre.
func _change(make: Callable, value: float) -> float:
    var mask: SaMask = make.call()
    _doc.mask_target = mask
    _select(value)
    var before := _coverage(mask, Vector2i(AT))
    _dab()
    _doc.mask_target = null
    _doc.selection.deselect()
    return before - _coverage(mask, Vector2i(AT))


## The three readings for masks *make* answers, a fresh mask for each.
func _assert_scaled(make: Callable, what: String) -> void:
    var whole := _change(make, 1.0)
    var soft := _change(make, 0.6)
    var nearly := _change(make, 0.999)
    assert_true(whole > 0.5, "one dab through a whole selection darkens %s, by %f" % [what, whole])
    assert_almost_eq(soft, 0.6 * whole, LEVELS, "through 0.6 %s changes by 0.6 of that, %f against %f" % [what, soft, whole])
    assert_almost_eq(nearly, whole, LEVELS, "through 0.999 %s changes as through 1.0, %f against %f" % [what, nearly, whole])


func test_a_dab_on_a_layers_mask_is_scaled_by_a_soft_selection() -> void:
    var layer := _doc.active_layer
    _assert_scaled(
        func() -> SaMask:
            layer.drop_mask()
            return layer.add_mask(),
        "a layer's mask"
    )


func test_a_dab_on_a_groups_mask_is_scaled_by_a_soft_selection() -> void:
    var group := SaLayerOps.new(_doc).group_active()
    _doc.set_active_layer(group)
    _assert_scaled(
        func() -> SaMask:
            group.drop_mask()
            return group.add_mask(),
        "a group's mask"
    )
