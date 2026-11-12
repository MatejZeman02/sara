## A module that adds a fourth field to the noise brush through the door and
## nothing else, so a suite can watch a stranger's field reach a stroke.
##
## It names no file of the noise module, which the suite reads this file's
## text for: the engine's id and the kernel's name are strings any module
## could write from the noise brush's spec, and the field is a
## `SaBrushFieldRegistry.Field` on the context, the class every module sees.
##
## **Weave is Grain at a scale of its own.** Its first number is the key
## `weave_scale`, which the noise brush's settings do not have, so the stroke
## reads the fallback, [constant SCALE], and a suite can tell it from Grain at
## the settings' scale. Its second is `grain_contrast`, a key they do have.
##
## Its own root rather than `tests/fixtures/modules/`, so the scenarios that
## load that folder do not gain a Texture choice they never asked for.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends SaModule

## The field's id, which a preset's `texture_field` names.
const FIELD_ID: String = "weave"
## The engine and kernel it names, the noise brush's own words for them.
const ENGINE: StringName = &"noise"
const KERNEL: StringName = &"grain"
## What `weave_scale` reads as, in document pixels, where the noise brush's
## own Grain is five.
const SCALE: float = 12.0
## What `grain_contrast` reads as for settings that do not have it.
const CONTRAST: float = 2.0


func get_id() -> StringName:
    return &"weave_field_fixture"


func get_name() -> String:
    return "Weave field fixture"


func get_dependencies() -> PackedStringArray:
    return PackedStringArray(["sara-noise-brush"])


func register(ctx: SaContext) -> void:
    ctx.register_brush_field(field())


## The field this module registers, a new one each call.
static func field() -> SaBrushFieldRegistry.Field:
    return SaBrushFieldRegistry.Field.new(
        FIELD_ID, "Weave", ENGINE, KERNEL, 2, [&"weave_scale", &"grain_contrast"], [], PackedFloat32Array([SCALE, CONTRAST])
    )
