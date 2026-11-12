## A module that registers three scene types: Marks,
## whose root marks where the pen pressed it, Lines, whose root draws a line
## wherever a brush's stroke passed, and Still, whose root takes no input.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it. A scenario reaches
## it with `--modules-dir=res://tests/fixtures/modules`, as the point fixture's
## does, and a suite registers it through a context of its own. It registers
## through the same door a student's module would, `SaContext`, and names no
## class of the skeleton's but the door's.
extends SaModule

## The type a layer of this module's is, and the scene that type names.
const TYPE := &"scene-fixture.marks"
const SCENE := "res://tests/fixtures/modules/scene-fixture/marks_scene.tscn"
## The type whose root defines no `sara_pointer`, a still picture, so a suite
## can show such a root handed nothing and its layer refusing the brush.
const STILL_TYPE := &"scene-fixture.still"
const STILL_SCENE := "res://tests/fixtures/modules/scene-fixture/still_scene.tscn"
## The type whose root defines `sara_stroke`, so a brush's strokes on its layer
## reach it rather than being refused.
const LINES_TYPE := &"scene-fixture.lines"
const LINES_SCENE := "res://tests/fixtures/modules/scene-fixture/lines_scene.tscn"
## The ground the scene draws under its marks, a dark slate so a bright mark
## reads in a shot and in a texel.
const GROUND := Color(0.08, 0.1, 0.16, 1.0)


func get_id() -> StringName:
    return &"scene-fixture"


func get_name() -> String:
    return "Scene Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    var marks := SaLayerTypeDescriptor.scene_layer(TYPE, SCENE, {"ground": GROUND})
    marks.display_name = "Marks"
    ctx.register_layer_type(marks)
    var still := SaLayerTypeDescriptor.scene_layer(STILL_TYPE, STILL_SCENE)
    still.display_name = "Still"
    ctx.register_layer_type(still)
    var lines := SaLayerTypeDescriptor.scene_layer(LINES_TYPE, LINES_SCENE, {"ground": GROUND})
    lines.display_name = "Lines"
    ctx.register_layer_type(lines)
