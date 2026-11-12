## The Layers docker follows a reorder it did not make itself.
##
## `SaLayerOps._place` moves the child and invalidates chunks, and the document
## does announce it through `document_changed`. The docker answers that signal
## with `item_list.refresh_all()`, which redraws each row where it already is.
## The order was only re-read by `sync_layer_list()`, which runs when a layer is
## added, removed or activated, and a `move_child` is none of the three. The
## drag inside the docker looked right only because the docker reordered its own
## rows on the drop, so every other route into a reorder left the panel showing
## the old stack: an undo, a redo, a command, a module. `_on_document_changed`
## asks whether the rows are still in the document's order now, and rebuilds
## when they are not.
##
## Seen on the running app: `scenarios/tour-layers.json` step 14 dragged Sky under
## Layer 1 and step 15 undid it. The canvas read (28, 106, 210) at (700, 384),
## which is Sky's blue back on top, while the dump still listed the rows as
## Layer 1 above Sky.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")


func test_the_docker_follows_a_reorder_it_did_not_make() -> void:
    var easel := SaEasel.create_default(Vector2i(128, 128))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var document := easel.document
    var upper := SaLayerOps.new(document).add()
    upper.name = "Sky"
    document.set_active_layer(upper)

    var canvas := SaCanvas.new()
    canvas.easel = easel
    var docker := LayersDocker.new()
    docker.target_canvas = canvas
    docker.sync_layer_list()
    assert_eq(_row_names(docker), ["Sky", "Layer 1", "Background"], "the rows start as the document has them")

    assert_true(SaLayerOps.new(document).move(upper, -1), "Sky moves down one place")
    assert_eq(_row_names(docker), ["Layer 1", "Sky", "Background"], "A reorder made outside the docker reaches its rows")

    assert_true(document.undo_redo.undo(), "and the move is one undo step")
    assert_eq(_row_names(docker), ["Sky", "Layer 1", "Background"], "so does undoing one")

    docker.free()
    canvas.free()
    easel.free()


## The docker's rows, top of the stack first.
func _row_names(docker: LayersDocker) -> Array:
    var out: Array = []
    for row: Dictionary in docker.item_list.row_report():
        out.append(row["name"])
    return out
