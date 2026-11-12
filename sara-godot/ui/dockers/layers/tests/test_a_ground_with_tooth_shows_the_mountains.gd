## A ground whose tooth stands in relief carries the mountains mark in its row,
## the mark a layer with impasto shows. A ground stores no height, so the
## mark must not ask only `carries_height()`, which a ground never has.
extends "res://tests/test_framework.gd"

## The rows carry a thumbnail each, which is a compute dispatch.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _registries: SaRegistries = null


func before_each() -> void:
    _registries = Fixtures.make_registries()


func after_each() -> void:
    _registries = null


## A docker over a Canvas ground and the layers a new document holds.
func _docker() -> LayersDocker:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(128, 128)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    var ground := SaLayerOps.new(canvas.easel.document).add(&"canvas", _registries.layer_types)
    ground.name = "Canvas"
    var docker := LayersDocker.new()
    canvas.add_child(docker)
    docker.target_canvas = canvas
    docker._ready()
    docker.bind_registries(_registries.blend_modes, _registries.layer_types)
    docker.sync_layer_list()
    return docker


func _row_of(docker: LayersDocker, name: String) -> SaRowFrame:
    var list: SaLayerList = docker.item_list
    for i in list.row_count():
        var layer: SaLayer = list.layer_at(i)
        if layer != null and str(layer.name) == name:
            return list.rows[i]
    return null


func test_a_ground_with_tooth_shows_the_mountains_and_a_flat_one_does_not() -> void:
    var docker := _docker()
    var row := _row_of(docker, "Canvas")
    var ground: SaLayer = row.layer
    assert_true(SaGeneratedLayer.tooth_of(ground) > 0.0, "the Canvas opens with a tooth")
    assert_true(row.height_mark.visible, "so its row shows the mountains")
    assert_true(row.height_mark.tooltip_text.contains("tooth"), "which say it is the tooth: %s" % row.height_mark.tooltip_text)

    ground.generator_params[SaGeneratedLayer.PARAM_TOOTH] = 0.0
    docker.sync_layer_list()
    row = _row_of(docker, "Canvas")
    assert_false(row.height_mark.visible, "a flat ground shows none")

    var paint := _row_of(docker, "Layer 1")
    assert_false(paint.height_mark.visible, "nor does a paint layer with no height")
    docker.target_canvas.free()
