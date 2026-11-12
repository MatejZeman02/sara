## A module that adds a field with a kernel of its own to the noise brush
## through the door and nothing else, so a suite and a scenario can watch a
## stranger's GLSL paint a stroke.
##
## It names no file of the noise module, the way the weave fixture names none:
## the engine's id is a string any module could write from the noise brush's
## spec, and the field is a `SaBrushFieldRegistry.Field` on the context, which
## carries the path of the `.gmacs` file its kernel is in.
##
## **Bands across the stroke.** `bands_field.gmacs` answers the contract with a
## band every [constant PERIOD] pixels of path, through `bands_period`, a key
## the noise brush's settings do not have, so the stroke reads the fallback.
## `broken_field.gmacs` is the same function with a name nothing declares, which
## only a suite registers, through [method broken], since the door refuses it.
##
## Its own root rather than `tests/fixtures/modules/`, so the scenarios that
## load that folder do not gain a Texture choice they never asked for.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends SaModule

## The field's id, which a preset's `texture_field` names.
const FIELD_ID: String = "bands"
## The engine it names, the noise brush's own word for it.
const ENGINE: StringName = &"noise"
## How many pixels of path one band and the gap after it span.
const PERIOD: float = 12.0
## The two files, beside this one.
const BANDS_PATH: String = "res://tests/fixtures/banded-field/modules/banded-field-fixture/bands_field.gmacs"
const BROKEN_PATH: String = "res://tests/fixtures/banded-field/modules/banded-field-fixture/broken_field.gmacs"
## The line of the broken file that reads the undeclared name.
const BROKEN_LINE: int = 12


func get_id() -> StringName:
    return &"banded_field_fixture"


func get_name() -> String:
    return "Banded field fixture"


func get_dependencies() -> PackedStringArray:
    return PackedStringArray(["sara-noise-brush"])


func register(ctx: SaContext) -> void:
    ctx.register_brush_field(bands())


## The banded field, a new one each call.
static func bands() -> SaBrushFieldRegistry.Field:
    return SaBrushFieldRegistry.Field.new(
        FIELD_ID, "Bands", ENGINE, SaBrushFieldRegistry.OWN, 1, [&"bands_period"], [], PackedFloat32Array([PERIOD]), BANDS_PATH
    )


## The broken field, a new one each call, under an id of its own.
static func broken() -> SaBrushFieldRegistry.Field:
    return SaBrushFieldRegistry.Field.new(
        "broken_bands",
        "Broken bands",
        ENGINE,
        SaBrushFieldRegistry.OWN,
        1,
        [&"bands_period"],
        [],
        PackedFloat32Array([PERIOD]),
        BROKEN_PATH
    )
