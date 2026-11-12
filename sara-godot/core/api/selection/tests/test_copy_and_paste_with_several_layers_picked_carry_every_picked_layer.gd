## Copy and Paste with several
## layers picked carry every picked layer, each as a layer of its own, and with
## one layer picked the clipboard does what it always did.
##
## Every layer is painted a colour of its own over the whole canvas, so a pasted
## layer that holds another layer's paint, or paint outside the rectangle,
## reads wrong.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 512)

## A rectangle that crosses the seam between chunks, so each layer's copy is
## cut from several chunks.
const RECT := Rect2i(200, 180, 140, 120)

const EXACT := 1.0e-3

var _surface: SaSurface = null
var _doc: SaDocument = null
var _low: SaLayer = null
var _high: SaLayer = null


func before_each() -> void:
    _surface = Fixtures.make_surface(SIZE)
    _doc = _surface.easel.document
    _low = _doc.active_layer
    _low.name = "Low"
    _low.fill(Color(0.8, 0.1, 0.1, 1.0))
    _low.blend_mode = &"multiply"
    _low.opacity = 0.6
    _high = SaLayerOps.new(_doc).add()
    _high.name = "High"
    _high.fill(Color(0.1, 0.2, 0.9, 1.0))
    _high.opacity = 0.4


func after_each() -> void:
    if _surface != null and _surface.easel != null and is_instance_valid(_surface.easel):
        Fixtures.teardown(_surface)
    _surface = null
    _doc = null
    _low = null
    _high = null


## The texel of *layer* at document pixel *at*, transparent where no chunk is.
static func _texel(layer: SaLayer, at: Vector2i) -> Color:
    var side := SaChunk.SIZE
    var grid_pos := Vector2i(floori(float(at.x) / side), floori(float(at.y) / side))
    var texture := layer.get_field(grid_pos)
    if texture == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    var local := at - grid_pos * side
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * side + local.x)


static func _off(got: Color, want: Color) -> float:
    var off := 0.0
    for i in 4:
        off = maxf(off, absf(got[i] - want[i]))
    return off


func _layers() -> Array[SaLayer]:
    return SaLayerOps.new(_doc).layers()


func test_two_paint_layers_copied_through_a_rectangle_each_paste_only_the_rectangle() -> void:
    var want := {"Low": _texel(_low, RECT.position), "High": _texel(_high, RECT.position)}
    _doc.selection.select_rect(RECT)
    var held := SaClipboard.new()
    held.clear()
    assert_eq(held.layers.copy(_doc, [_high, _low] as Array[SaLayer]), 2, "Both picked layers are held")
    assert_true(held.is_empty(), "The single copy's chunks are left empty, so Paste reads the held layers")
    _doc.selection.deselect()
    _doc.set_active_layer(_high)
    var before := _layers().size()
    var pasted := held.layers.paste(_doc)
    assert_eq(pasted.size(), 2, "Two layers are pasted")
    assert_eq(_layers().size(), before + 2, "The stack grew by two")
    if pasted.size() != 2:
        return
    assert_eq(String(pasted[0].name), "Low 2", "The lower one is the copy of Low, numbered since Low stands")
    assert_eq(String(pasted[1].name), "High 2", "The upper one is the copy of High")
    assert_eq(pasted[0].get_index(), _high.get_index() + 1, "They land above the active layer")
    assert_eq(pasted[0].blend_mode, &"multiply", "Low's blend mode comes along")
    assert_almost_eq(pasted[0].opacity, 0.6, 1.0e-6, "Low's opacity comes along")
    assert_almost_eq(pasted[1].opacity, 0.4, 1.0e-6, "High's opacity comes along")
    assert_eq(_doc.active_layer, pasted[1], "The top pasted layer is active")
    assert_eq(_doc.picked.acted_on(_doc).size(), 2, "The pasted layers are the picked set")
    for layer: SaLayer in pasted:
        var source := "Low" if String(layer.name).begins_with("Low") else "High"
        var inside := [RECT.position, RECT.end - Vector2i.ONE, RECT.get_center()]
        for at: Vector2i in inside:
            assert_true(_off(_texel(layer, at), want[source]) <= EXACT, "%s holds its paint at %s" % [layer.name, at])
        var outside := [RECT.position - Vector2i.ONE, RECT.end, Vector2i(10, 10), Vector2i(500, 500)]
        for at: Vector2i in outside:
            assert_true(_texel(layer, at).a <= EXACT, "%s holds nothing outside the rectangle at %s" % [layer.name, at])
    _doc.undo()
    assert_eq(_layers().size(), before, "One undo takes both pasted layers away")


func test_two_paint_layers_cut_with_no_selection_go_and_one_undo_brings_them_back() -> void:
    var spare := SaLayerOps.new(_doc).add()
    spare.name = "Spare"
    var before := _layers().size()
    var staying := _layers().filter(func(layer: SaLayer) -> bool: return layer != _low and layer != _high)
    var held := SaClipboard.new()
    held.clear()
    assert_true(held.layers.cut(_doc, [_high, _low] as Array[SaLayer]), "The cut takes the picked layers")
    assert_eq(_layers(), staying, "Both picked layers are gone and the rest stay")
    assert_eq(held.layers.size(), 2, "Both are held")
    _doc.undo()
    assert_eq(_layers().size(), before, "One undo brings both back")
    assert_true(_layers().has(_low) and _layers().has(_high), "The very layers come back")
    var pasted := held.layers.paste(_doc)
    assert_eq(pasted.size(), 2, "What was cut pastes as two layers")


func test_a_group_and_its_members_paste_nested_as_they_were() -> void:
    _doc.set_active_layer(_high)
    var group := SaLayerOps.new(_doc).group_layers([_low, _high])
    assert_not_null(group, "The two layers are grouped")
    if group == null:
        return
    var held := SaClipboard.new()
    held.clear()
    assert_eq(held.layers.copy(_doc, [group] as Array[SaLayer]), 3, "The group and its two members are held")
    _doc.set_active_layer(group)
    var pasted := held.layers.paste(_doc)
    assert_eq(pasted.size(), 3, "Three layers are pasted")
    if pasted.size() != 3:
        return
    var top := pasted[-1]
    assert_true(top.is_group, "The group's copy stands on top of its members")
    assert_eq(SaLayerStack.parent_of(top), null, "The group's copy is top level, as the group is")
    assert_eq(SaLayerStack.parent_of(pasted[0]), top, "A member's copy is inside the group's copy")
    assert_eq(SaLayerStack.parent_of(pasted[1]), top, "So is the other")


func test_one_layer_copied_pastes_as_a_single_paste_does() -> void:
    _doc.selection.select_rect(RECT)
    var held := SaClipboard.new()
    assert_true(held.copy(_doc, _high) > 0, "One layer is copied as before")
    assert_true(held.layers.is_empty(), "No layers are held for a single copy")
    _doc.selection.deselect()
    var layer := held.paste(_doc)
    assert_not_null(layer, "The single paste makes a layer")
    if layer == null:
        return
    assert_eq(String(layer.name), "Pasted Layer", "Named as a single paste always was")
    assert_true(_off(_texel(layer, RECT.get_center()), _texel(_high, RECT.get_center())) <= EXACT, "It holds High's paint")
    assert_true(_texel(layer, Vector2i(10, 10)).a <= EXACT, "And nothing outside the rectangle")
