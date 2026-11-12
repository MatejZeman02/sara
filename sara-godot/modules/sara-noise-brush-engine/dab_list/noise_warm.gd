## What the noise brush builds ahead of its first stroke, so the first stroke
## waits for none of it: the kernel and the smudge pickup built at the depth of
## the document, and the stand-ins a stretch binds where it has no field picture,
## no height, no carry and no tip.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The cost is the variant.** Sara opens on Oklab P3 at 16-bit float, and a
## kernel is built once per storage format, on the first request for that
## format. Without this, the kernel's first dispatch on such a document builds
## `noise_dab` at F16 there and then, milliseconds of the first stroke where a
## pipeline made from a build costs a tenth of one, so that stroke lags and no
## stroke after it does, whatever preset is picked. The stamp brush's `warm` is
## the same cure.
##
## **Made through objects of their own**, since a build is the compiler's for the
## session however it was asked for, and the space may be another easel's, the
## scratchpad's. The tool points its own `compute` at the depth itself.
extends RefCounted

const NoiseHeightCarryScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_height_carry.gd")


## Builds *kernel* and the smudge pickup at *format*, and makes the stand-ins the
## stroke would make as it went. Held by the classes that own them, so asking
## again builds nothing twice.
static func build(kernel: String, format: int) -> void:
    if GlobalShaderCompiler.get_rd() == null:
        return
    SaCompute.new(kernel).use_storage_format(format)
    SaSmudgeReservoir.warm(format)
    NoiseHeightCarryScript.warm()
    SaStrokeHeights.held(null)
    SaSmudgeReservoir.stand_in()
    SaBrushTipMask.stand_in()
