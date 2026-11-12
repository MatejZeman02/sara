## The door's attach of a filter says when the selection became its mask.
##
## A script attaching a Mirror through `filter_rows` with a sky
## selection left over from earlier read "attached" and found the
## reflection kept inside the sky. Attach takes the selection as the record's
## mask on purpose, as the Filter dialog's Attach does,
## and the door's answer now names it in the dialog's words. The first case
## attaches under a rectangle and reads the sentence and a mask equal to the
## selection, the second clears the selection, attaches again and reads
## neither.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## The mask is made and read back on the GPU.
const REQUIRES_GPU := true

const SIZE := Vector2i(512, 256)
const LEFT := Vector2i(0, 0)
const MARQUEE := Rect2i(0, 0, 128, 256)
const LAYER := "Layer 1"
const SENTENCE := "The selection becomes the filter's mask."

var _easel: SaEasel = null
var _doc: SaDocument = null
var _paint: SaLayer = null
var _key: StringName = &""


func before_each() -> void:
    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    _paint = _doc.get_node(LAYER) as SaLayer
    _paint.get_or_create_chunk(LEFT).clear(Color(0.85, 0.75, 0.1, 1.0))
    var hsl := SaHueSaturationLightnessFilter.new()
    _easel.compositor.filter_chain.registry.register(hsl, &"sara-base-modules")
    _key = SaFilterRegistry.key_for(&"sara-base-modules", hsl)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _paint = null


func _attach() -> String:
    var tree := Engine.get_main_loop() as SceneTree
    return SaFilterRowsCapture.run(tree, _doc, {"attach": String(_key), "layer": LAYER})


func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


func test_an_attach_under_a_selection_says_the_selection_became_the_mask() -> void:
    _doc.selection.select_rect(MARQUEE)
    var said := _attach()

    assert_true(said.begins_with("SaCapture: attached '%s' to %s" % [_key, LAYER]), "The door attaches: %s" % said)
    assert_true(said.ends_with(SENTENCE), "and says the selection became the filter's mask: %s" % said)
    assert_eq(_paint.filters.size(), 1, "One record lands on the layer")
    var record := _paint.filters[0]
    assert_not_null(record.mask, "with a mask, which is what the answer says")
    assert_eq(record.mask.grid_positions(), [LEFT] as Array[Vector2i], "held where the selection holds a chunk")
    var selected := _bytes(_doc.selection.chunks[LEFT].field(SaSelection.FIELD))
    assert_true(_bytes(record.mask.coverage(LEFT)) == selected, "and equal to the selection, texel for texel")


func test_an_attach_with_nothing_selected_says_nothing_of_a_mask() -> void:
    _doc.selection.select_rect(MARQUEE)
    _doc.selection.deselect()
    var said := _attach()

    assert_true(said.begins_with("SaCapture: attached '%s' to %s" % [_key, LAYER]), "The door attaches: %s" % said)
    assert_false(said.contains("mask"), "and names no mask: %s" % said)
    assert_eq(_paint.filters.size(), 1, "One record lands on the layer")
    assert_null(_paint.filters[0].mask, "with no mask, as the answer says")
