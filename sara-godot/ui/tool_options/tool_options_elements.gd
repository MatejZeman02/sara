## The tool options bar's element table: the name a profile stores each of the
## skeleton's own controls under, and the group of the bar each one sits in.
##
## A table rather than a class with a job, apart from `tool_options_bar.gd`
## because the elements' groups are a list and not the bar's work. The bar
## keeps the controls and forwards the names under the ones every caller uses.
##
## A tool's option names its group on its own spec, `SaOptionSpec.bar_group`,
## and `groups` reads them through the registry, so a module's row joins a
## group the way the brush's does and the skeleton names no module's key.
class_name SaToolOptionsElements
extends RefCounted

const PRESETS := "Brush Presets"
const KEEP_BLEND := "Keep Blend Mode"
const MIRROR_H := "Mirror H"
const MIRROR_V := "Mirror V"
const RADIAL := "Radial"
## The stabiliser's quick toggle. Its own element rather than the
## `stabilizer_mode` dropdown's, because the two are different controls for one
## value and a painter may want the toggle on the bar and the dropdown off it.
const STABILIZER := "Stabilizer Toggle"
## The Edit Brush button, a layout element like the rest so a painter who never
## opens the editor can take it off the bar in Preferences.
const EDIT_BRUSH := "Edit Brush"

## The group of each of the skeleton's own elements. The preset button, Keep
## and Edit Brush are about which brush is in the hand, so they are the brush's.
## The symmetry three and the stabiliser toggle say how a line is laid down
## whatever the brush, which is a stroke's.
const GROUPS := {
    PRESETS: SaOptionSpec.BAR_GROUP_BRUSH,
    KEEP_BLEND: SaOptionSpec.BAR_GROUP_BRUSH,
    EDIT_BRUSH: SaOptionSpec.BAR_GROUP_BRUSH,
    MIRROR_H: SaOptionSpec.BAR_GROUP_STROKE,
    MIRROR_V: SaOptionSpec.BAR_GROUP_STROKE,
    RADIAL: SaOptionSpec.BAR_GROUP_STROKE,
    STABILIZER: SaOptionSpec.BAR_GROUP_STROKE,
}


## Stored element name -> group, for the skeleton's own elements and every
## option a tool in *registry* put on the bar with a group. The first spec that
## names one for a key decides it, since the tools that share a key share its
## control, and a key no spec groups is not in it.
static func groups(registry: SaToolRegistry) -> Dictionary:
    var out: Dictionary = GROUPS.duplicate()
    if registry == null:
        return out
    for descriptor: SaToolDescriptor in registry.list_descriptors():
        for spec: SaOptionSpec in descriptor.options:
            if spec == null or not spec.bar or String(spec.bar_group).is_empty():
                continue
            if not out.has(String(spec.key)):
                out[String(spec.key)] = spec.bar_group
    return out
