## A module with a generated layer type whose kernel and view
## shader are the module's own, a procedural noise ground, the proof that a
## generator a module ships paints, composites, saves and opens the way a
## built-in one does.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Not under `res://modules`, so no ordinary launch sees it. The scenario
## reaches it with `--modules-dir=res://tests/fixtures/noise-ground/modules`,
## and the suite beside the generated layer's code registers it through a
## context of its own. The path keeps a `modules` segment, so the shader index
## files `noise_ground.gmacs` under this folder's name, and the descriptor
## names its generator qualified by it, as the descriptor's header asks.
extends SaModule

const ID: StringName = &"noise-ground-fixture"
## The type a layer of this module records in a `.sad`.
const TYPE: StringName = &"noise_ground"
## The kernel file and the view shader, both beside this script.
const KERNEL: String = "noise_ground"
const VIEW: String = "noise_ground.gdshader"

## The module's own two parameters, which its kernel declares by these names:
## how many octaves of noise the grain sums, and where on the lattice it is
## read, so two layers of it can differ.
const PARAM_OCTAVES := "octaves"
const PARAM_SEED := "seed"


func get_id() -> StringName:
    return ID


func get_name() -> String:
    return "Noise Ground Fixture"


func get_version() -> String:
    return "1.0.0"


func register(ctx: SaContext) -> void:
    ctx.register_layer_type(descriptor())


## The type this module registers, a ground of deep blue and orange noise
## forty pixels to a cell, five octaves deep, standing a fifth of a virtual
## millimetre, so a look tells it from the paper at a glance.
func descriptor() -> SaLayerTypeDescriptor:
    var made := SaLayerTypeDescriptor.create(TYPE, SaFieldSpec.default_schema())
    made.display_name = "Noise Ground"
    made.icon_name = "guiminicheckerboard"
    made.hint = "A ground of procedural noise a module ships, set under the layer list. It holds no paint."
    made.generator = "%s/%s" % [ID, KERNEL]
    made.generator_view = (get_script() as Script).resource_path.get_base_dir().path_join(VIEW)
    made.generator_defaults = {
        "color": Color(0.12, 0.2, 0.42, 1.0),
        "second": Color(0.95, 0.62, 0.25, 1.0),
        "scale": 40.0,
        "tooth": 0.2,
        PARAM_OCTAVES: 5.0,
        PARAM_SEED: 0.0,
    }
    return made
