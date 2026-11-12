## The dimmed Merge Down says why on hover.
##
## Above a paper laid at File > New, Merge Down is dimmed, because a generated
## layer takes no merge, and its hover read the command's own sentence, what
## Merge Down does, with no word of why it would not. The rows the Layer menu
## and the docker's More menu share now put the merge's own refusal there.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(256, 256)

var _easel: SaEasel
var _doc: SaDocument


func before_each() -> void:
    _easel = SaEasel.create_default(SIZE)
    _doc = _easel.document
    var choice := {
        SaDocumentBackground.KIND: SaDocumentBackground.COLOUR,
        SaDocumentBackground.COLOR: Color.WHITE,
        SaDocumentBackground.GROUND: &"paper",
    }
    _doc.reset_to_default(SIZE, _doc.color_space, SaDocument.DEFAULT_DPI, choice, Fixtures.make_registries().layer_types)


func after_each() -> void:
    _doc = null
    _easel.free()
    _easel = null


func _merge_row() -> SaLayerMenuRows.Row:
    for row: Variant in SaLayerMenuRows.new(_doc).rows(false):
        if row is SaLayerMenuRows.Row and (row as SaLayerMenuRows.Row).id == &"layer_merge_down":
            return row
    assert_true(false, "The Layer menu has a Merge Down row")
    return SaLayerMenuRows.Row.new(&"", -1)


func test_above_a_ground_it_names_the_ground() -> void:
    assert_true(SaLayerOps.new(_doc).layers()[0].is_generated(), "The paper lies at the bottom")
    _doc.set_active_layer(_doc.get_node("Layer 1") as SaLayer)
    var row := _merge_row()
    assert_true(row.disabled, "Merge Down is dimmed above the paper")
    assert_true(row.sentence.contains("'Background' is a generated layer"), "and its hover names the paper: %s" % row.sentence)


func test_on_the_bottom_layer_it_says_there_is_nothing_below() -> void:
    _doc.set_active_layer(SaLayerOps.new(_doc).layers()[0])
    var row := _merge_row()
    assert_true(row.disabled, "Merge Down is dimmed on the bottom layer")
    assert_true(row.sentence.contains("nothing below it"), "and says there is nothing below: %s" % row.sentence)


func test_a_live_row_keeps_its_own_sentence() -> void:
    var ops := SaLayerOps.new(_doc)
    _doc.set_active_layer(_doc.get_node("Layer 1") as SaLayer)
    ops.add()
    var row := _merge_row()
    assert_false(row.disabled, "Merge Down is live on paint over paint")
    assert_eq(row.sentence, "", "and keeps its own sentence, none without a registry")
