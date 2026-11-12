## The Layer menu's Rasterize Layer row, which the docker's
## More menu and a row's right click draw from the same list, stands beside
## Apply Mask, is dimmed on a plain paint layer and on a group with the line
## saying why, and is lit on a layer with a mask. Its command is registered
## with no key, so the keyboard settings list it to bind.
##
## The rasterize itself is `core/layers/rasterize`'s suite of the unit's name.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const RASTERIZE := &"layer_rasterize"

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(Vector2i(256, 256))
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _registries = null


## The rows as the Layer menu draws them now, and the Rasterize Layer row.
func _rows() -> Array:
    return SaLayerMenuRows.new(_doc, _registries.commands, _registries.layer_types).rows(false)


func _row() -> SaLayerMenuRows.Row:
    for row: Variant in _rows():
        if row is SaLayerMenuRows.Row and (row as SaLayerMenuRows.Row).id == RASTERIZE:
            return row
    return null


func test_the_row_stands_beside_apply_mask() -> void:
    var ids: Array[StringName] = []
    for row: Variant in _rows():
        if row is SaLayerMenuRows.Row:
            ids.append((row as SaLayerMenuRows.Row).id)
    var at := ids.find(RASTERIZE)
    assert_true(at > 0, "The Layer menu carries Rasterize Layer")
    assert_eq(ids[at - 1] if at > 0 else &"", &"layer_mask_apply", "right below Apply Mask")
    var more: Array[StringName] = []
    for row: Variant in SaLayerMenuRows.new(_doc, _registries.commands, _registries.layer_types).rows(true):
        if row is SaLayerMenuRows.Row:
            more.append((row as SaLayerMenuRows.Row).id)
    assert_true(more.has(RASTERIZE), "and so does the docker's More menu, which the right click opens too")


func test_the_row_is_dimmed_with_its_reason_on_plain_paint_and_on_a_group() -> void:
    var layer := _doc.active_layer
    var row := _row()
    assert_not_null(row, "The row is drawn")
    if row == null:
        return
    assert_eq(row.words, "Rasterize Layer", "under its words")
    assert_true(row.disabled, "dimmed on a plain paint layer")
    assert_eq(row.sentence, SaRasterizeLayer.refusal(_doc, layer), "saying why")
    assert_true(row.sentence.contains("plain paint"), "that it is plain paint already")
    var group := SaLayerOps.new(_doc).group_active()
    _doc.set_active_layer(group)
    row = _row()
    assert_true(row.disabled, "dimmed on a group")
    assert_eq(row.sentence, SaRasterizeLayer.refusal(_doc, group), "saying why")
    assert_true(row.sentence.contains("Merge"), "and that a group is left to Merge")
    _doc.set_active_layer(layer)
    assert_true(SaMaskOps.new(_doc).add(layer), "The layer takes a mask")
    row = _row()
    assert_false(row.disabled, "and the row is lit")


func test_the_command_has_no_key_and_can_be_bound() -> void:
    var command := _registries.commands.get_descriptor(RASTERIZE)
    assert_not_null(command, "The command is registered")
    if command == null:
        return
    assert_eq(command.menu_label(), "Rasterize Layer", "under the menu's words")
    assert_true(command.default_events.is_empty(), "with no key of its own, for the painter to bind")
