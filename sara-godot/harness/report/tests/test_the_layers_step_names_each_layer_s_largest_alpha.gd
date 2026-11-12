## The `layers` step carries each layer's largest alpha, so a script finds a
## layer that holds alpha above one without a dump.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A layer with alpha above one looks like any dark silhouette on the screen,
## and a painting's layer held 2.8 along its contours through several passes
## before a dump of the layer found it. Four layers here: one opaque,
## one holding a chunk of alpha two beside an opaque one, one with no paint and
## a group, and the line is read back as a client reads it.
extends "res://tests/test_framework.gd"

## Chunks are allocated and reduced, which takes the card.
const REQUIRES_GPU := true

const LayersReport := preload("res://harness/report/sa_layers_report.gd")
const PREFIX := "SaCapture: layers "


func _entry(doc: SaDocument, layer_name: String) -> Dictionary:
    var line := LayersReport.capture(doc)
    var parsed: Variant = JSON.parse_string(line.trim_prefix(PREFIX))
    for entry: Dictionary in parsed if parsed is Array else []:
        if entry.get("name", "") == layer_name:
            return entry
    return {}


func test_each_layer_reads_the_largest_alpha_it_stores() -> void:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(512, 256), SaCompositor.new(), SaColorSpace.srgb())
    var ops := SaLayerOps.new(doc)
    var opaque := ops.add()
    opaque.name = "Opaque"
    opaque.get_or_create_chunk(Vector2i(0, 0)).clear(Color(0.2, 0.3, 0.4, 1.0))
    var heavy := ops.add()
    heavy.name = "Heavy"
    heavy.get_or_create_chunk(Vector2i(1, 0)).clear(Color(0.1, 0.1, 0.1, 1.0))
    heavy.get_or_create_chunk(Vector2i(0, 0)).clear(Color(0.1, 0.1, 0.1, 2.0))
    var empty := ops.add()
    empty.name = "Empty"
    var held := ops.add()
    held.name = "Held"
    ops.group_layers([held])

    assert_almost_eq(float(_entry(doc, "Opaque").get("alpha", -1.0)), 1.0, 0.0001, "Opaque paint reads one")
    assert_almost_eq(
        float(_entry(doc, "Heavy").get("alpha", -1.0)), 2.0, 0.0001, "A chunk of alpha two is found beside an opaque one"
    )
    assert_true(_entry(doc, "Empty").has("alpha"), "A layer with no paint carries the key")
    assert_eq(_entry(doc, "Empty").get("alpha", 0), null, "as null, since it stores no alpha")
    var groups := LayersReport.stack(doc).filter(func(e: Dictionary) -> bool: return e["kind"] == "group")
    assert_eq(groups.size(), 1, "The group is listed")
    if not groups.is_empty():
        assert_eq(groups[0]["alpha"], null, "and carries null, a group stores no paint of its own")
    var cheap: Array = LayersReport.stack(doc, false)
    assert_true(cheap.all(func(e: Dictionary) -> bool: return not e.has("alpha")), "The cheap listing leaves the key out")
    doc.free()
