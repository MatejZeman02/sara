## A module for the second reload scenario: a layer type that a reload takes away
## and gives back while a document holds a layer of it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The type stores nothing and borrows the skeleton's background kernel with a
## red of its own, so the canvas shows whether the layer resolves: red while
## its module is up, the grey under it while the layer is inert. Not under
## `res://modules`, so no ordinary launch sees it. The scenario reaches it with
## `--modules-dir=res://tests/fixtures/r2-reload/modules`, a folder of its own
## for the reason the fixture gives.
extends SaModule


func get_id() -> StringName:
    return &"r2-reload-fixture"


func get_name() -> String:
    return "R2 Reload Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    var descriptor := SaLayerTypeDescriptor.create(&"r2_tint", SaFieldSpec.default_schema())
    descriptor.display_name = "R2 Tint"
    descriptor.generator = "background"
    descriptor.generator_defaults = {"color": Color(0.85, 0.2, 0.15, 1.0)}
    descriptor.resolve = _resolve
    ctx.register_layer_type(descriptor)


## A hook into this script, which is what the unload has to let go of.
func _resolve(_layer: SaLayer, _grid_pos: Vector2i, _chunk: SaChunk) -> void:
    pass
