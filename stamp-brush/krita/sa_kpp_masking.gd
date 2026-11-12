## Krita's masking brush, the second brush it runs over every dab, onto
## `SaMaskingBrush`: its own tip, its size multiplier, its spacing and its own
## size and opacity dynamics.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Its own file because it is a whole brush of its own.** The mask is a
## complete preset nested under `MaskingBrush/Preset/` inside the preset being
## imported: its own `<Brush>` element, its own tip, its own size and its own
## curves. It is the one part of the mapping table that reads a preset inside a
## preset.
##
## **The nested definition goes through the reader's own tip door.** Krita
## writes the mask's whole preset under `MaskingBrush/Preset/`, so the mask's
## tip is a preset's tip in miniature: the same `<Brush>` element, with a
## `<MaskGenerator>` inside it or a file name pointing into the same
## `<resources>` the painted tip is looked up in. A preset of one option is
## handed to the reader instead of a second parser being written here, so a
## mask and a painted tip cannot come to disagree about what a tip is.
##
## **Three things Krita's mask has and Sara's has not, each named on its own.**
## A composite op other than the five `SaMaskingBrush.Op` has arithmetic for,
## multiply, subtract, darken, burn and overlay, tagged with the op's own id. An
## absolute size in pixels, because Sara's is a multiple of the dab's, for the
## reason that file's header gives. And a tip the preset names and does not
## embed. The mask's own dynamics carry: its size, opacity, flow, rotation,
## scatter and mirror curves land on the block's options of those names, and
## each stem Sara has no home for wears a tag naming it. One phrase for the
## whole feature would leave a painter unable to see which of the three this
## preset actually lost, so each field that does not carry gets a tag of its own
## naming it.
class_name SaKppMasking
extends RefCounted

## Krita's masking brush. The mask's whole preset is written under
## `MaskingBrush/Preset/`, `brush_definition` and all.
const MASKING_PREFIX: String = "MaskingBrush/"
const MASKING_ENABLED: String = "MaskingBrush/Enabled"
const MASKING_COMPOSITE_OP: String = "MaskingBrush/MaskingCompositeOp"
const MASKING_USE_MASTER_SIZE: String = "MaskingBrush/UseMasterSize"
const MASKING_MASTER_COEFF: String = "MaskingBrush/MasterSizeCoeff"
const MASKING_PRESET_PREFIX: String = "MaskingBrush/Preset/"
const MASKING_DEFINITION: String = "MaskingBrush/Preset/brush_definition"

## The mask's own curve options, Krita's stem onto the name
## `SaMaskingBrush.option_for` answers. Opacity lands on the strength, which is
## what the mask calls its opacity. Every other stem of
## `SaKppSensors.OPTION_STEMS` has no home on the mask and is tagged by name.
const MASKING_STEMS: Dictionary = {
    "Size": "size",
    "Opacity": "strength",
    "Flow": "flow",
    "Rotation": "rotation",
    "Scatter": "scatter",
    "Mirror": "mirror",
}

## What a lost stem is called in its tag, "masking dynamics: <stem>".
const LOST_DYNAMICS: String = "masking dynamics: "


## The masking brush onto *settings*' mask block, with what did not carry
## appended to *not_carried* and every param read marked in *taken*.
static func apply(preset: Dictionary, settings: Resource, taken: Dictionary, not_carried: Array[String]) -> void:
    var options: Dictionary = preset.get("options", {})
    for name: String in options:
        if String(name).begins_with(MASKING_PREFIX):
            taken[name] = true
    if not options.has(MASKING_ENABLED) or not SaKppSensors.bool_of(options, MASKING_ENABLED):
        return
    var block: Resource = settings.get("masking") if "masking" in settings else null
    var definition := SaKppSensors.string_of(options, MASKING_DEFINITION).strip_edges()
    if block == null or definition.is_empty():
        not_carried.append("masking brush")
        return
    var mask: Dictionary = (
        SaKppReader
        . tip_of(
            {
                "options": {SaKppReader.BRUSH_DEFINITION: {"type": "string", "value": definition}},
                "resources": preset.get("resources", {}),
                "source": preset.get("source", ""),
            }
        )
    )
    # Before the tip, so a preset whose mask tip is not carried still keeps its
    # op for the day it is, and an op Sara has no arithmetic for is named
    # whatever became of the tip.
    _op(options, block, not_carried)
    var target: Resource = block.tip
    if target == null:
        target = SaKppReader.SaBrushTipScript.new()
        block.tip = target
    var diameter := _tip_onto(target, mask, not_carried)
    if diameter <= 0.0:
        return
    block.enabled = true
    block.spacing = clampf(SaKppReader.attr_float(mask.get("brush", {}), "spacing", block.spacing), 0.01, 5.0)
    block.size = _size(options, settings, diameter, not_carried)
    _dynamics(options, block, taken)
    for stem: String in _lost_dynamics(options):
        not_carried.append(LOST_DYNAMICS + stem)


## The mask's composite op onto *block*, from Krita's id.
##
## The five `SaMaskingBrush.Op` has arithmetic for carry, and any other stays
## multiply and is tagged with its own id, "masking composite op <id>", so a
## painter reading the tags sees which op the preset lost rather than that one
## was lost. An absent op is Krita's default, which is multiply.
static func _op(options: Dictionary, block: Resource, not_carried: Array[String]) -> void:
    var id := SaKppSensors.string_of(options, MASKING_COMPOSITE_OP).strip_edges()
    var op := SaMaskingBrush.op_of(id) if not id.is_empty() else int(SaMaskingBrush.Op.MULTIPLY)
    if op < 0:
        not_carried.append("masking composite op %s" % id)
        op = SaMaskingBrush.Op.MULTIPLY
    block.op = op


## The mask's own shape onto *target*, answering its diameter in Krita's
## pixels, or zero when the preset names a tip it does not carry.
##
## Beside `SaKppImport._apply_tip` rather than folded into it, because the two
## write to different places from the same attributes: the painted tip's
## diameter sets the brush radius and its fades are overwritten by the bar's
## Hardness row on every dab, while the mask's diameter is a multiplier's
## numerator and its fades are the only ones nothing writes over, which is the
## promise `sa_masking_brush.gd` makes about a mask drawn soft staying soft.
static func _tip_onto(target: Resource, mask: Dictionary, not_carried: Array[String]) -> float:
    var brush: Dictionary = mask.get("brush", {})
    target.angle = SaKppReader.attr_float(brush, "angle", 0.0)
    target.randomness = clampf(SaKppReader.attr_float(brush, "randomness", 0.0), 0.0, 1.0)
    target.density = clampf(SaKppReader.attr_float(brush, "density", 1.0), 0.0, 1.0)
    match String(mask.get("kind", "")):
        SaKppReader.TIP_GENERATED:
            var generator: Dictionary = mask.get("generator", {})
            target.diameter = SaKppReader.attr_float(generator, "diameter", 40.0)
            target.ratio = clampf(SaKppReader.attr_float(generator, "ratio", 1.0), 0.01, 1.0)
            target.spikes = maxi(int(SaKppReader.attr_float(generator, "spikes", 2.0)), 2)
            target.antialias_edges = SaKppSensors.truthy(String(generator.get("antialiasEdges", "1")))
            target.generator = int(SaKppReader.GENERATORS.get(String(generator.get("id", "default")), 0))
            target.shape = int(
                SaKppReader.SHAPES.get(String(generator.get("type", "circle")), SaKppReader.SaBrushTipScript.Shape.CIRCLE)
            )
            target.kind = SaKppReader.SaBrushTipScript.Kind.PROCEDURAL
            target.image_path = ""
            target.horizontal_fade = clampf(SaKppReader.attr_float(generator, "hfade", 1.0), 0.0, 1.0)
            target.vertical_fade = clampf(SaKppReader.attr_float(generator, "vfade", 1.0), 0.0, 1.0)
            return target.diameter
        SaKppReader.TIP_IMAGE:
            var size: Vector2i = mask.get("size", Vector2i.ZERO)
            var diameter := maxf(float(maxi(size.x, size.y)) * SaKppReader.attr_float(brush, "scale", 1.0), 1.0)
            var written := SaBrushTipMask.save(String(mask.get("file_name", "")).get_file(), mask.get("bytes", PackedByteArray()))
            if written.is_empty() or not SaBrushTipMask.select(target, written).error.is_empty():
                not_carried.append("masking tip")
                return 0.0
            target.diameter = diameter
            return diameter
        _:
            not_carried.append("masking tip")
            return 0.0


## The mask's diameter as a multiple of the dab's.
##
## Krita has that multiple already when the mask follows the master size, which
## is what a preset with a mask almost always does. When it does not, Krita
## holds the mask at an absolute size in pixels, which Sara has nowhere to put:
## the multiple that matches at the imported size is written so the preset looks
## right the moment it lands, and the field is named as not carried because the
## painter dragging the size row will see the mask follow where Krita's would
## have stood still.
static func _size(options: Dictionary, settings: Resource, diameter: float, not_carried: Array[String]) -> float:
    if not options.has(MASKING_USE_MASTER_SIZE) or SaKppSensors.bool_of(options, MASKING_USE_MASTER_SIZE):
        return maxf(SaKppSensors.float_of(options, MASKING_MASTER_COEFF, 1.0), 0.0)
    not_carried.append("masking size in pixels")
    var dab: float = settings.tip.diameter if settings.tip != null else 0.0
    return diameter / dab if dab > 0.0 else 1.0


## The mask's own curves onto the block's options, the way
## `SaKppSensors.apply` carries the painted tip's, and the axes the scatter and
## the mirror options are allowed to move.
##
## Krita writes the mask's whole preset under `MaskingBrush/Preset/` again, so
## the names are the same stems with the prefix in front, and a stripped copy is
## what `SaKppSensors.apply` reads.
static func _dynamics(options: Dictionary, block: Resource, taken: Dictionary) -> void:
    if block == null or not block.has_method("option_for"):
        return
    var mask_options := _option_dictionary(options)
    for stem: String in MASKING_STEMS:
        var option: SaCurveOption = block.call("option_for", MASKING_STEMS[stem]) as SaCurveOption
        if option != null:
            SaKppSensors.apply(option, mask_options, stem, taken)
    _axes(mask_options, block)


## Krita's Scatter and Mirror checkboxes under the mask's preset onto the
## block's axes, read exactly as `SaKppImport` reads the painted tip's.
##
## A mirror with its option off is the mask tip's own standing mirror rather
## than the option's axes, which is Sara's reading for the painted tip and the
## reason that importer's comment gives: dropping the checkbox would quietly
## unmirror a mask Krita drew mirrored.
static func _axes(mask_options: Dictionary, block: Resource) -> void:
    if "scatter_axis_x" in block and (mask_options.has("Scatter/AxisX") or mask_options.has("Scatter/AxisY")):
        block.scatter_axis_x = SaKppSensors.bool_of(mask_options, "Scatter/AxisX", true)
        block.scatter_axis_y = SaKppSensors.bool_of(mask_options, "Scatter/AxisY", true)
    if not "mirror_axis_x" in block:
        return
    if not (mask_options.has("Mirror/HorizontalMirror") or mask_options.has("Mirror/VerticalMirror")):
        return
    var mirror_h := SaKppSensors.bool_of(mask_options, "Mirror/HorizontalMirror")
    var mirror_v := SaKppSensors.bool_of(mask_options, "Mirror/VerticalMirror")
    if SaKppSensors.bool_of(mask_options, "PressureMirror"):
        block.mirror_axis_x = mirror_h
        block.mirror_axis_y = mirror_v
    elif block.tip != null:
        block.tip.mirror_horizontal = mirror_h
        block.tip.mirror_vertical = mirror_v


## The mask's own options with the `MaskingBrush/Preset/` prefix stripped, so
## the shared reader sees the same names it sees for the painted tip.
static func _option_dictionary(options: Dictionary) -> Dictionary:
    var stripped: Dictionary = {}
    for name: String in options:
        if name.begins_with(MASKING_PRESET_PREFIX):
            stripped[name.trim_prefix(MASKING_PRESET_PREFIX)] = options[name]
    return stripped


## The stems the mask's own preset switched on that Sara's mask has no option
## for, each by the name the painted tip's option has, so the tag reads
## "masking dynamics: ratio" rather than a Krita stem.
##
## Each is lost for one reason: the mask is a coverage and nothing else. Ratio,
## softness and spacing would each want an option the mask has not got, the
## rate is the airbrush's and the mask lays no dabs of its own, and a texture or
## a colour curve has no paper or colour under the mask to move.
static func _lost_dynamics(options: Dictionary) -> Array[String]:
    var lost: Array[String] = []
    for stem: String in SaKppSensors.OPTION_STEMS:
        if MASKING_STEMS.has(stem):
            continue
        if SaKppSensors.bool_of(options, MASKING_PRESET_PREFIX + "Pressure" + stem):
            lost.append(String(SaKppSensors.OPTION_STEMS[stem]).trim_suffix("_option").replace("_", " "))
    return lost
