## A layer name the row cuts short reads whole on hover.
##
## At the docker's default width a row cuts the name "Layer row reads Brightness
## Contrast" to "Brightness ...", and nothing on the row let a painter read the
## rest. The three locks keep their place on every row, so the remedy is reading the
## name, not widening its column: while the name is wider than its label the row's
## tooltip is the whole name, with the note below it when there is one, and a
## name that fits keeps the tooltip it always had.
##
## The row is built through `SaLayerRowView` and laid out by hand, because a
## docker is a `Window` and adding one in a headless run hangs.
## `scenarios/a-layer-name-cut-short-in-its-row-reads-whole-on-hover.json`
## puts the pointer on the row in the running app.
extends "res://tests/test_framework.gd"

## The row carries a thumbnail, which is a compute dispatch.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const RowView = preload("res://ui/dockers/layers/list/layer_row_view.gd")

const NAME := "Brightness Contrast"
const NOTE := "Lifted by hand, so the sky does not sink"

## Narrow enough that the name is cut at any interface scale, and wide enough
## that the name is not.
const NARROW := 150.0
const WIDE := 480.0


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(128, 128))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


## Sorts every container under *node*, outside in, so the label has the width
## the running app would give it. A test cannot await a frame.
func _sort_children(node: Node) -> void:
    if node is Container:
        (node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child: Node in node.get_children():
        _sort_children(child)


## A row for *layer* in the tree, *width* wide.
func _row(layer: SaLayer, document: SaDocument, width: float) -> SaLayerRowView:
    var item: SaLayerRowView = RowView.new(str(layer.name), 0, false, 0, layer)
    EventBus.add_child(item)
    item.refresh(document)
    _widen(item, width)
    return item


func _widen(item: SaLayerRowView, width: float) -> void:
    item.size = Vector2(width, item.custom_minimum_size.y)
    _sort_children(item)


func _tip(item: SaLayerRowView) -> String:
    return item.get_tooltip(Vector2(4.0, 4.0))


func test_a_cut_name_reads_whole_then_over_the_note_then_the_note_alone() -> void:
    var easel := _easel()
    var layer := easel.document.active_layer
    layer.name = NAME
    var item := _row(layer, easel.document, NARROW)

    var font := item.lbl.get_theme_font(&"font")
    var wide := font.get_string_size(NAME, HORIZONTAL_ALIGNMENT_LEFT, -1, item.lbl.get_theme_font_size(&"font_size")).x
    assert_true(item.lbl.size.x < wide, "The row is narrow enough to cut the name, %.1f of %.1f" % [item.lbl.size.x, wide])
    assert_eq(item.lbl.text, NAME, "and the label holds the whole name under its ellipsis")
    assert_eq(_tip(item), NAME, "so the tooltip is the whole name")

    layer.comment = NOTE
    item.refresh(easel.document)
    assert_eq(_tip(item), "%s\n%s" % [NAME, NOTE], "and with a note it is the name over the note")

    _widen(item, WIDE)
    assert_true(item.lbl.size.x >= wide, "Widened, the label has room for the name, %.1f of %.1f" % [item.lbl.size.x, wide])
    assert_eq(_tip(item), NOTE, "so the tooltip is the note alone")
    assert_eq(item.tooltip_text, NOTE, "which is also what the row's own tooltip text has always been")

    item.free()
    easel.free()


func test_a_name_that_fits_keeps_the_tooltip_it_had() -> void:
    var easel := _easel()
    var layer := easel.document.active_layer
    layer.name = "Sky"
    var item := _row(layer, easel.document, WIDE)
    assert_eq(_tip(item), "", "A short name with no note has no tooltip at all")

    layer.comment = NOTE
    item.refresh(easel.document)
    assert_eq(_tip(item), NOTE, "and with a note it is the note alone")
    item.free()
    easel.free()


func test_a_name_cut_and_a_note_cleared_goes_back_to_the_name_alone() -> void:
    var easel := _easel()
    var layer := easel.document.active_layer
    layer.name = NAME
    layer.comment = NOTE
    var item := _row(layer, easel.document, NARROW)
    assert_eq(_tip(item), "%s\n%s" % [NAME, NOTE], "A cut name with a note reads both")

    layer.comment = ""
    item.refresh(easel.document)
    assert_eq(_tip(item), NAME, "and the note taken off leaves the name, with no empty line under it")
    item.free()
    easel.free()


## While the row is renamed the field shows the name and the label is not on
## show, so the tooltip has nothing to complete.
func test_a_row_being_renamed_says_the_note_alone() -> void:
    var easel := _easel()
    var layer := easel.document.active_layer
    layer.name = NAME
    layer.comment = NOTE
    var item := _row(layer, easel.document, NARROW)
    item.lbl.visible = false
    assert_eq(_tip(item), NOTE, "The note and nothing else")
    item.free()
    easel.free()
