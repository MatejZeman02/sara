## Filter > Invert, one minus every colour, in one click.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every output texel reads only its own input texel, so this is a point filter
## like Threshold: it records a point pass, the compositor previews it and
## Apply walks it, and it declares no radius, which is what lets an adjustment
## layer and an attached record hold it. The kernel is `invert.gmacs`.
##
## No rows. Levels with its output handles swapped and Curves drawn downhill
## could already invert a layer, and that was the trouble: three drags for the
## one adjustment a painter checks values with.
class_name SaInvertFilter
extends SaFilter

## The shader file, by the key the shader index files it under.
const SHADER := "invert"
## Where the push constant keeps the dispatched region's origin, x then y.
const ORIGIN_SLOT := 0


func title() -> String:
    return "Invert"


## Listed under Colour in the Filter menu and the browser.
func family() -> StringName:
    return &"color"


func sentence() -> String:
    return "Turn every colour into its opposite, so black becomes white, with alpha left where it was."


## No chord of its own. Ctrl+I is what a painter from another program reaches
## for, and a filter that took it here would take it from every module that
## might want it first, so the row on the Keyboard Shortcuts page is where a
## painter gives it one.
func chord() -> Array[InputEvent]:
    return []


func build(ui: SaDialog) -> void:
    ui.title(title())


func run(ctx: SaFilterContext) -> void:
    ctx.point_pass(SHADER, "invert", push_for(_space_of(ctx)), {}, ORIGIN_SLOT)


## The 112-byte push constant `invert.gmacs` reads: the region's origin, which
## the runner writes at [constant ORIGIN_SLOT], two spares, then the colour
## space tail exactly as `SaColorSpacePushConstant` writes it.
static func push_for(space: SaColorSpace) -> PackedFloat32Array:
    var push := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
    push.append_array(SaColorSpacePushConstant.to_push_constant(space if space != null else SaColorSpace.srgb()))
    return push


## The space the document stores its colours in. A context built with no document
## answers null, and the tail is gamma sRGB then.
static func _space_of(ctx: SaFilterContext) -> SaColorSpace:
    return ctx.document.color_space if ctx.document != null else null
