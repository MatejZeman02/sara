## The `layers` step answers the stack in one verdict line.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A stack of four layers is built, one inside a group and one hidden, the
## line is parsed back as a client would parse it, and every fact the row names
## is compared with the document it came from: index, name, kind, visibility,
## opacity, blend mode, which is active, the group, the allocated bounds and
## whether a live transform draws it.
## Then a ten-layer document is measured, because the line exists to be short
## where the state dump is not.
extends "res://tests/test_framework.gd"

## Chunks are allocated, which makes textures.
const REQUIRES_GPU := true

const LayersReport := preload("res://harness/report/sa_layers_report.gd")
const PREFIX := "SaCapture: layers "
## What the row asked a ten-layer line to stay under, two thousand, with room
## for each layer's largest alpha, which a script needs to find coverage above
## one and which costs about twelve characters a layer.
const TEN_LAYER_LIMIT := 2200


func _document() -> SaDocument:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(512, 256), SaCompositor.new(), SaColorSpace.srgb())
    return doc


## The line's stack, parsed the way `sara.py` reads it. JSON has one number
## type, so the bounds come back as floats.
func _read(doc: SaDocument) -> Array:
    var line := LayersReport.capture(doc)
    assert_true(line.begins_with(PREFIX), "The step answers with its verdict prefix: %s" % line.left(60))
    var parsed: Variant = JSON.parse_string(line.trim_prefix(PREFIX))
    assert_true(parsed is Array, "The line carries a JSON array")
    return parsed if parsed is Array else []


func _by_name(stack: Array, layer_name: String) -> Dictionary:
    for entry: Dictionary in stack:
        if entry.get("name", "") == layer_name:
            return entry
    return {}


func test_four_layers_one_grouped_one_hidden_read_back_as_the_same_facts() -> void:
    var doc := _document()
    var ops := SaLayerOps.new(doc)
    var ink := ops.add()
    ink.name = "Ink"
    var wash := ops.add()
    wash.name = "Wash"
    ops.set_visible(wash, false)
    ops.set_opacity(wash, 0.5)
    ops.set_blend_mode(wash, &"multiply")
    ink.get_or_create_chunk(Vector2i(1, 0))
    var group := ops.group_layers([ink])
    doc.set_active_layer(ink)

    var stack := _read(doc)
    var layers := ops.layers()
    assert_eq(stack.size(), layers.size(), "One entry a layer, the group counted")
    assert_eq(layers.filter(func(l: SaLayer) -> bool: return not l.is_group).size(), 4, "Four layers that hold paint")
    for index in layers.size():
        var entry: Dictionary = stack[index]
        var layer := layers[index]
        assert_eq(int(entry["i"]), index, "The index counts from the bottom")
        assert_eq(entry["name"], String(layer.name), "Bottom first, entry %d is %s" % [index, layer.name])
        assert_eq(entry["visible"], layer.visible, "%s's visibility" % layer.name)
        assert_almost_eq(float(entry["opacity"]), layer.opacity, 0.001, "%s's opacity" % layer.name)
        assert_eq(entry["blend"], String(layer.blend_mode), "%s's blend mode" % layer.name)
        assert_eq(entry["active"], layer == doc.active_layer, "%s's active flag" % layer.name)

    assert_eq(stack[0]["name"], "Background", "The background is index 0")
    assert_eq(stack[0]["bounds"], [0.0, 0.0, 512.0, 256.0], "The background covers the whole canvas")
    assert_eq(stack[0]["kind"], "plain", "An untyped layer reads as plain")
    assert_null(_by_name(stack, "Layer 1")["bounds"], "An empty layer has no bounds")

    var ink_entry := _by_name(stack, "Ink")
    assert_eq(ink_entry["group"], String(group.name), "Ink names the group it sits in")
    assert_eq(ink_entry["active"], true, "Ink is the active layer")
    assert_eq(ink_entry["bounds"], [256.0, 0.0, 256.0, 256.0], "Ink's one chunk is its bounds in document pixels")

    var wash_entry := _by_name(stack, "Wash")
    assert_eq(wash_entry["visible"], false, "Wash is hidden")
    assert_almost_eq(float(wash_entry["opacity"]), 0.5, 0.001, "Wash is at half opacity")
    assert_eq(wash_entry["blend"], "multiply", "Wash multiplies")
    assert_null(wash_entry["group"], "Wash is at the top level")

    var group_entry := _by_name(stack, String(group.name))
    assert_eq(group_entry["kind"], "group", "The group reads as a group")
    assert_true(int(group_entry["i"]) > int(ink_entry["i"]), "The group sits above its member")
    assert_eq(ink_entry["transformed"], false, "Ink is drawn where it was painted")
    doc.free()


## A layer drawn through a live transform says so, and its
## bounds stay where its paint is held.
func test_a_transformed_layer_is_named() -> void:
    var doc := _document()
    var ink := SaLayerOps.new(doc).add()
    ink.name = "Ink"
    ink.get_or_create_chunk(Vector2i(0, 0))
    var moved: Variant = SaLiveTransform.map_of([1.0, 0.0, 40.0, 0.0, 1.0, 20.0, 0.0, 0.0, 1.0])
    assert_true(SaLiveTransform.put(doc, ink, moved), "Ink is moved")
    var entry := _by_name(_read(doc), "Ink")
    assert_eq(entry["transformed"], true, "The line names Ink as transformed")
    assert_eq(entry["bounds"], [0.0, 0.0, 256.0, 256.0], "and its bounds are its chunk's, where the paint is held")
    assert_eq(_by_name(_read(doc), "Background")["transformed"], false, "and the background as not")
    doc.free()


func test_a_ten_layer_line_is_under_twenty_two_hundred_characters() -> void:
    var doc := _document()
    var ops := SaLayerOps.new(doc)
    var adds := 0
    while ops.layers().size() < 10 and adds < 10:
        adds += 1
        var layer := ops.add()
        layer.get_or_create_chunk(Vector2i(ops.layers().size() % 2, 0))
    assert_eq(ops.layers().size(), 10, "Ten layers")
    var line := LayersReport.capture(doc)
    print("  a ten-layer line is %d characters" % line.length())
    assert_true(line.length() < TEN_LAYER_LIMIT, "The line is %d characters, under %d" % [line.length(), TEN_LAYER_LIMIT])
    assert_eq(_read(doc).size(), 10, "and it still carries all ten")
    doc.free()


func test_no_document_is_refused_in_the_verdict_line() -> void:
    assert_true(LayersReport.capture(null).begins_with("SaCapture: layers refused"), "A missing document is said")
