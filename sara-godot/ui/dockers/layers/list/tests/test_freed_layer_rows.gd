## A layer list whose rows outlived their document answers with nothing, rather
## than raising.
##
## Every `{"document": ...}` step of every scenario answered with
## `SCRIPT ERROR: Left operand of 'is' is a previously freed instance` at
## `SaLayerList.selected_layers`. Opening a document sets its active
## layer, the docker syncs on that, and the rows it reads first still hold the
## layers of the document before it, which are freed by then. `is` against a
## freed instance is an error rather than a false, so the guard meant to skip a
## bad row was the line that threw.
##
## A docker is a `Window` and adding one to the tree in a headless test hangs,
## so nothing here enters the tree: the list and the layers are enough, since
## the defect is in the list's own reading of its rows.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")


## A list of three rows, each carrying a real layer of *easel*'s document.
func _populated(easel: SaEasel) -> SaLayerList:
    var list := SaLayerList.new()
    var document := easel.document
    document.active_layer.name = "Layer 0"
    for i in range(1, 3):
        SaLayerOps.new(document).add().name = "Layer %d" % i
    for layer: SaLayer in document.get_children():
        if layer is SaLayer:
            list.add_item(String(layer.name), 0, false, layer)
    return list


## **The freed row is in the middle on purpose.** A script error is not a failed
## assertion: GDScript prints it and abandons the function, so a list whose rows
## are all freed answered with an empty array either way and a test built that
## way passed against the bug. With one freed row between two live ones the
## difference is visible in the return value, because the error abandons the
## loop and the live row after it never reaches the array.
func test_a_row_whose_layer_is_gone_is_skipped_rather_than_raising() -> void:
    var easel := SaEasel.create_default(Vector2i(128, 128))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var list := _populated(easel)
    list.picked.restore([0, 1, 2], 0)
    assert_eq(list.selected_layers().size(), 3, "Three live rows answer with three layers")

    var names := _names(list.selected_layers())

    # A layer of its own rather than one of the document's three, which is the
    # same freed instance from the row's point of view and leaks nothing: a
    # layer freed out from under its document orphans that layer's chunks, and
    # the gate counts an orphaned texture as a failure whatever the assertions
    # said. What the row holds after a document reset is an `SaLayer` that has
    # been freed, and that is what this puts in it.
    var stray := SaLayer.new()
    list.rows[1].layer = stray
    stray.free()

    var after := list.selected_layers()
    assert_eq(after.size(), 2, "A freed row in the middle leaves the two live ones")
    assert_eq(_names(after), [names[0], names[2]], "which are the rows either side of it, in order")
    assert_eq(names.size(), 3, "and the three names were read while all three were live")
    assert_eq(list.picked.selected_indices(), [0, 1, 2], "while the picked rows are still picked, for the rebuild to read")
    list.free()
    easel.free()


func _names(layers: Array[SaLayer]) -> Array:
    var out: Array = []
    for layer: SaLayer in layers:
        out.append(String(layer.name))
    return out


## The other half of the same contract, which is what the docstring on
## `selected_layers` has always claimed: a row carrying something that is not a
## layer is skipped too, and a test list carries no metadata at all.
func test_a_row_carrying_no_layer_is_skipped() -> void:
    var list := SaLayerList.new()
    for row_name: String in ["Top", "Middle", "Bottom"]:
        list.add_item(row_name)
    list.picked.restore([0, 2], 0)
    assert_eq(list.selected_layers(), [] as Array[SaLayer], "A list with no metadata answers with no layers")
    list.free()
