## The brush paints a group's mask.
##
## `SaLayer.is_locked` answers true for a group whatever a painter set, because
## a group holds no paint of its own to lock, and the guard at the top of
## `handle_input` read that before it asked what the stroke writes. So a mask a
## painter gave a group, through Layer > Add Mask, could be inverted,
## disabled, applied and deleted from the menu and never painted: the press on
## its picture in the Layers docker aimed the brush at it and the very next
## stroke said "This layer is locked", with the group's lock button lit although
## nobody locked it.
##
## What the guard asks now is the lock over what the stroke writes. Onto the
## paint it is the layer's own `is_locked`, which is what it has always read, and
## onto a mask it is the flag a painter switches on the mask's owner. The third
## case below is the first of those, because the case this row fixes is the one
## where the two answers differ.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Where the dab lands, inside the first chunk.
const AT := Vector2(100.0, 100.0)

var _surface: SaSurface = null
var _doc: SaDocument = null
var _machine: ToolMachine = null
var _group: SaLayer = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _doc = _surface.easel.document
    _machine = Fixtures.make_bound_machine(_surface)
    # A group over the one layer the default document has, and the group left
    # active: what a painter has under them when they mask it.
    _group = SaLayerOps.new(_doc).group_active()
    _doc.set_active_layer(_group)
    _surface.view.mouse_position = AT


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _doc = null
    _machine = null
    _group = null


## The coverage *mask* holds at a document pixel, one where it holds nothing,
## which is the same reading `test_mask_painting.gd` takes.
func _coverage(mask: SaMask, at: Vector2i) -> float:
    @warning_ignore("integer_division")
    var grid := Vector2i(at.x / SaChunk.SIZE, at.y / SaChunk.SIZE)
    var texture := mask.texture_for(grid)
    if texture == null:
        return 1.0
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x).r


## A press and a release through the machine with *tool* active, which is one
## dab, read back through the tool rather than dispatched by hand so the guard
## the row is about is the one under test.
func _stroke(tool_name: StringName) -> void:
    _machine.set_active_tool(tool_name)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    _machine.handle_input(press)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    _machine.handle_input(release)


## Collects what the stroke said on the bus, which is where a refusal is said.
func _refusals(stroke: Callable) -> Array[String]:
    var said: Array[String] = []
    var ear := func(text: String) -> void: said.append(text)
    EventBus.paint_refused.connect(ear)
    stroke.call()
    EventBus.paint_refused.disconnect(ear)
    return said


## The case the row was filed from: the eraser on a group's mask hides what it
## crosses, and the group was never locked by anyone.
func test_the_eraser_paints_a_groups_mask() -> void:
    var mask := _group.add_mask()
    _doc.mask_target = mask
    assert_true(_group.is_locked, "A group reports locked, which is what refused this stroke")
    assert_false(_group._locked, "with no lock of its own set")

    _stroke(&"eraser")

    var covered := _coverage(mask, AT)
    assert_true(covered < 0.5, "The eraser wrote into the group's mask, which reads %f at the dab" % covered)


## The brush as well as the eraser, because both ends of the route reach the
## same guard and only one of them was in the note.
func test_the_brush_paints_a_groups_mask() -> void:
    var mask := _group.add_mask()
    # A mask holding nothing everywhere reads as one, so what the brush writes
    # is read at a texel the eraser of the case above has not taken away: the
    # coverage it leaves is the whole of what a white dab covers.
    var texture := mask.get_or_create(Vector2i.ZERO)
    texture.clear(Color(0.0, 0.0, 0.0, 1.0))
    _doc.mask_target = mask

    _stroke(&"brush")

    var covered := _coverage(mask, AT)
    assert_true(covered > 0.5, "The brush wrote into the group's mask, which reads %f at the dab" % covered)


## A group the painter did lock is still locked, and the stroke says why.
func test_a_locked_group_refuses_the_stroke_on_its_mask() -> void:
    var mask := _group.add_mask()
    _doc.mask_target = mask
    _group.is_locked = true

    var said := _refusals(func() -> void: _stroke(&"eraser"))

    assert_eq(_coverage(mask, AT), 1.0, "The mask holds nothing, so it reads as one")
    assert_false(mask.chunks.has(Vector2i.ZERO), "and no chunk was allocated under the stroke")
    assert_eq(said.size(), 1, "The press said one thing")
    assert_true(said[0].contains("locked"), "which is the lock line, and it reads: %s" % said[0])


## A locked layer still refuses a stroke on its paint. This is the case the
## guard exists for, and the one the fix above must not cost.
func test_a_locked_layer_still_refuses_the_stroke() -> void:
    # A paint layer of its own, since a stroke on the group itself names the
    # group whatever its lock says.
    var layer := SaLayerOps.new(_doc).add()
    _doc.set_active_layer(layer)
    layer.is_locked = true
    assert_true(layer.chunks.is_empty(), "Nothing has been painted yet")

    var said := _refusals(func() -> void: _stroke(&"brush"))

    assert_true(layer.chunks.is_empty(), "A locked layer's paint is still left alone")
    assert_eq(said.size(), 1, "The press said one thing")
    assert_true(said[0].contains("locked"), "which is the lock line, and it reads: %s" % said[0])
