## A Krita preset onto a Sara preset: the reader's dictionary walked
## through the mapping table into the settings, saved by the store, with
## what did not carry said in the console and worn as a tag.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Every Krita option either lands or is named as not carried.** There is no
## third answer: an option read but dropped in silence is the one failure a
## painter cannot see, so `tests/test_kpp_import.gd` walks the two fixtures and
## holds every option in them to one of the two. The curve options are
## `SaKppSensors`' half and the masking brush is `sa_kpp_masking.gd`'s. What is
## here is the tip, the numbers, the texture, the blend, the mode, and the
## bookkeeping of what was read.
##
## **Three things are said about a preset, in three places.** The settings carry
## what carried. The console line names every option that did not, by its Krita
## name, and every option nobody read, so a painter running the import from a
## terminal sees per preset what changed. And the preset wears a tag per feature
## that did not carry, `not carried: masking brush`, so the presets docker's tag
## row can show every import with a masking brush at once, which is the only way
## a painter sorts a folder of imports into the ones that need a second look.
## The licence is metadata on the preset, read back by `SaPresetStore.meta_for`.
##
## **Sizes are pixels in Krita and a fraction of the document in Sara.** A
## diameter of 40 lands as a radius of 20 over 1080, the lower dimension of
## the default document, which is the number `state_brush.gd` multiplies by
## when no document is open, so a preset imported and then painted on the
## default document is the size it was in Krita.
##
## **Nothing here touches the canvas or the GPU.** An image tip is written to
## the tips folder and selected through the tip mask's own door, and a pattern
## is written to the painter's patterns folder, where the pattern store lists
## it.
class_name SaKppImport
extends RefCounted

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")
const SaLayerScript = preload("res://core/api/document/sa_layer.gd")

## What `_base_radius` multiplies by with no document open, and so what a
## pixel diameter is divided by here.
const DOCUMENT_LOWER: float = 1080.0

## The tag every import wears, so the docker's tag row lists them together.
const IMPORTED_TAG: String = "imported"

## Krita's `paintopid` for its colour smudge engine, and the tag a preset of it
## wears here. A tag rather than a kind of brush of its own, because the stage
## is a switch on the stamp brush and the chooser already shows presets by what
## they are tagged.
const SMUDGE_ENGINE: String = "colorsmudge"
const SMUDGE_TAG: String = "smudge"
const NOT_CARRIED_PREFIX: String = SaNotCarried.PREFIX

## What the console line of a preset left as it was ends with. The presets page
## no longer counts by it, `SaKppImportCapture.report` counts from the results.
const KEPT_PHRASE: String = "already in the presets"

## The report's sentence for a preset painting through a gradient its file
## does not hold, a gradient map tip's or a gradient colour source's.
const GRADIENT_FROM_THE_PAINTER: String = "gradient from the painter's colour to the background colour, the file holding none"

## The metadata keys a preset keeps beside its tags.
const LICENCE_META: StringName = &"licence"
const SOURCE_META: StringName = &"imported_from"
const BUNDLE_META: StringName = &"bundle"

## Krita's composite op ids onto Sara's blend modes. An id not here is not
## carried and the preset paints Normal.
const BLEND_MODES: Dictionary = {
    "normal": "normal",
    "multiply": "multiply",
    "screen": "screen",
    "overlay": "overlay",
    "add": "add",
    "linear_dodge": "add",
    "erase": "erase",
    "dodge": "color_dodge",
    "divide": "divide",
    "darken": "darken",
    "lighten": "lighten",
    "soft_light": "soft_light",
    "soft_light_svg": "soft_light",
    "hard_light": "hard_light",
    "diff": "difference",
    "grain_merge": "signed_add",
}

## The params that carry nothing a painter would miss: version stamps, the
## md5 of a pattern the file also embeds, and the ceiling a random offset
## would use. Read so they are not reported, and written nowhere.
const READ_AND_DROPPED: Array[String] = [
    "Texture/Pattern/PatternMD5",
    "Texture/Pattern/MaximumOffsetX",
    "Texture/Pattern/MaximumOffsetY",
    "Texture/Pattern/Pattern",
]

## The colour stems Sara has no option for, each with the phrase it wears when
## it is switched on.
##
## Seven stems wore one tag, "colour dynamics", until the colour options gave
## five of them a home. `h`, `s`, `v` and `Darken` read through
## `SaKppSensors.OPTION_STEMS` like every other option, `Mix` through
## `_apply_colour`, and these are left.
##
## **`LightnessStrength` was the second of them and it carries now**, under the
## id `KisStandardOptionData.h` gives it and not `Lightness`, which is the Color
## Smudge engine's option of that name. It lands on the painted tip's own
## `lightness_strength` in `_apply_lightness` below and no preset wears its tag
## any more. `Gradient` is kept under the name the table gave it, because
## Krita's current option data defines no gradient option to check it against
## and an older preset may still carry it.
const UNCARRIED_COLOUR_STEMS: Dictionary = {
    "Gradient": "colour gradient",
}


## Reads *path*, a `.kpp`, a folder or a `.bundle`, and imports every preset
## in it into *store*, each started from a fresh settings resource of
## *template*'s script. Answers one result per preset, in the order read.
## *replace* is whether a preset the store already holds under the same name
## is written over, see [method import_preset]. *kritarc* is the Krita
## settings file whose pressure curve the presets were tuned under, the
## machine's own when empty, read once for the lot.
static func import_path(
    path: String, store: SaPresetStore, template: Resource = null, replace: bool = true, kritarc: String = ""
) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var krita := SaKritarc.read(kritarc)
    for preset: Dictionary in SaKppReader.read_path(path):
        out.append(import_preset(preset, store, template, replace, krita))
    return out


## One read preset into *store*. The result carries `name`, the name it was
## stored under, `not_carried`, one phrase per feature, `unread`, the params
## nothing read, `notes`, what came from elsewhere than the file, `tags`, what
## the preset wears, and `error` when it could not be stored at all.
##
## A bundle of brush tips and no preset is not a preset and stores nothing: the
## reader hands its tips over instead, they go to the tip folder, and the result
## carries `tips`, how many were written, and `tips_skipped`, the ones the tip
## loader would not read.
##
## **A preset the store already holds** is the same file read
## again, most often a bundle imported a second time after the importer learnt
## to carry more. With *replace* off it is left as it is and the result carries
## `kept`, the name it is held under. With *replace* on its settings and its
## tags are written afresh, so a "not carried" tag an older importer wrote goes
## with the loss it named, and the result carries `replaced`. The tags the
## painter gave it are the ones kept, every tag the importer does not write,
## because a refresh is the importer's business and a painter's own tag is not.
## A preset the painter saved under another name is another file and is never
## touched.
##
## **The preset is stamped with Krita's pressure curve**,
## *krita* as `SaKritarc.read` answers it and the machine's `kritarc` read
## afresh when empty, because its option curves were drawn under that curve and
## not under the importing painter's. The result carries `pressure`, which
## curve it was and from where.
static func import_preset(
    preset: Dictionary, store: SaPresetStore, template: Resource = null, replace: bool = true, krita: Dictionary = {}
) -> Dictionary:
    var result := {
        "name": "", "source": String(preset.get("source", "")), "not_carried": [], "unread": [], "tags": [], "error": ""
    }
    var error := String(preset.get("error", ""))
    if not error.is_empty():
        result["error"] = error
        return result
    var tips: Array = preset.get("tips", [])
    if not tips.is_empty():
        result["tips"] = _write_tips(tips)
        result["tips_skipped"] = Array(preset.get("tips_skipped", PackedStringArray()))
        return result
    var held := store != null and store.has_preset(String(preset.get("name", "")))
    if held and not replace:
        result["kept"] = SaPresetStore.sanitize_name(String(preset.get("name", "")))
        return result
    var settings := _fresh(template)
    if settings == null:
        result["error"] = TranslationServer.translate("no settings resource to import into.")
        return result
    var applied := apply(preset, settings)
    var curve := krita if not krita.is_empty() else SaKritarc.read()
    if SaPressureStamp.FIELD in settings:
        settings.set(SaPressureStamp.FIELD, (curve["table"] as PackedFloat32Array).duplicate())
        result["pressure"] = String(curve["said"])
    result["not_carried"] = applied["not_carried"]
    result["unread"] = applied["unread"]
    result["notes"] = applied["notes"]
    var tags := PackedStringArray(preset.get("tags", PackedStringArray()))
    tags.append(IMPORTED_TAG)
    if String(preset.get("engine", "")) == SMUDGE_ENGINE:
        tags.append(SMUDGE_TAG)
    for phrase: String in applied["not_carried"]:
        tags.append(NOT_CARRIED_PREFIX + phrase)
    if held:
        for tag: String in _painter_tags(store.tags_for(String(preset.get("name", "")))):
            if not tags.has(tag):
                tags.append(tag)
    var metadata: Dictionary = {SOURCE_META: String(preset.get("source", "")).get_file()}
    var bundle: Variant = preset.get("bundle", null)
    if bundle is Dictionary and not String((bundle as Dictionary).get("title", "")).is_empty():
        metadata[BUNDLE_META] = String((bundle as Dictionary).get("title", ""))
    var licence := String(preset.get("licence", ""))
    if not licence.is_empty():
        metadata[LICENCE_META] = licence
    var stored := store.save_preset(String(preset.get("name", "")), settings, tags, metadata) if store != null else ""
    if stored.is_empty():
        result["error"] = TranslationServer.translate("'%s' could not be saved.") % String(preset.get("name", ""))
        return result
    result["name"] = stored
    result["tags"] = Array(store.tags_for(stored))
    if held:
        result["replaced"] = true
    return result


## The tags of *tags* the importer never writes, which are the painter's own.
## Krita's own tags from the file are written again by the import and so need
## no keeping here.
static func _painter_tags(tags: PackedStringArray) -> PackedStringArray:
    var own := PackedStringArray()
    for tag: String in tags:
        if tag != IMPORTED_TAG and tag != SMUDGE_TAG and not tag.begins_with(NOT_CARRIED_PREFIX):
            own.append(tag)
    return own


## Writes *preset*'s options onto *settings*, and answers `not_carried`, the
## features Sara has no home for, `unread`, the params no row of the table
## reads, and `notes`, what carried from somewhere other than the file. The
## settings are written in place, so a caller with its own resource keeps it.
static func apply(preset: Dictionary, settings: Resource) -> Dictionary:
    var options: Dictionary = preset.get("options", {})
    var taken: Dictionary = {}
    var not_carried: Array[String] = []
    var notes: Array[String] = []
    _apply_tip(preset, settings, taken, not_carried, notes)
    _apply_numbers(options, settings, taken, not_carried)
    _apply_texture(preset, settings, taken, not_carried)
    SaKppMasking.apply(preset, settings, taken, not_carried)
    for stem: String in SaKppSensors.OPTION_STEMS:
        SaKppSensors.apply(settings.get(SaKppSensors.OPTION_STEMS[stem]) as SaCurveOption, options, stem, taken)
    _apply_colour(options, settings, taken, not_carried, notes)
    _apply_smudge(preset, settings, taken)
    _apply_not_carried_features(options, taken, not_carried)
    for name: String in READ_AND_DROPPED:
        taken[name] = true
    var unread: Array[String] = []
    for name: String in options:
        if not taken.has(name):
            unread.append(name)
    unread.sort()
    return {"not_carried": not_carried, "unread": unread, "notes": notes}


## The console's line for one result, in the language Sara is shown in. The
## sentences are [SaKppReport]'s.
static func describe(result: Dictionary) -> String:
    return SaKppReport.line(result)


## Every tip a bundle of brushes carries, into `user://brush_tips`, where
## `SaBrushTipMask.available()` lists it for the Tip row and the editor. How
## many were written.
static func _write_tips(tips: Array) -> int:
    var written := 0
    for tip: Dictionary in tips:
        if not _write_tip(tip).is_empty():
            written += 1
    return written


## A settings resource of *template*'s script, or this module's when none is
## handed in, so the import starts from what a new brush has.
##
## **A template this module's fields do not fit is passed over rather than
## written into**. The presets group hands the settings of the tool in front of
## the painter, and the gradient keeps an `SaGradientEnds`, so importing a
## bundle with the gradient picked wrote a brush's tip, opacity and texture
## onto a resource that has no such member: five `SCRIPT ERROR` lines, and the
## preset stored from the wrong object. Falling back to this module's own
## script is what makes the import land on the brush exactly as it does with
## the brush tool picked, which is what a painter importing a brush bundle
## means by it whatever tool is selected.
static func _fresh(template: Resource) -> Resource:
    var script := template.get_script() as Script if template != null else null
    if script != null and _is_brush_settings(script):
        var made: Variant = script.new()
        if made is Resource:
            return made
    return SettingsScript.new()


## Whether *script* makes a resource these fields land on: this module's
## settings itself, or a subclass of it some module has made.
##
## The base script is walked rather than an instance made and typed, because a
## foreign script's `_init` may want arguments this importer has none of, and
## asking it about itself would run it.
static func _is_brush_settings(script: Script) -> bool:
    var walk := script
    while walk != null:
        if walk == SettingsScript:
            return true
        walk = walk.get_base_script()
    return false


## The tip: the generator's own attributes for a generated one, the embedded
## picture written to the tips folder and selected for an image, a pipe written
## to the tips folder and selected the same way, and a tip the loader refused
## wearing its refusal as a feature not carried. *notes* takes the report's
## sentences about what came from somewhere other than the file.
static func _apply_tip(
    preset: Dictionary, settings: Resource, taken: Dictionary, not_carried: Array[String], notes: Array[String]
) -> void:
    var options: Dictionary = preset.get("options", {})
    if not options.has(SaKppReader.BRUSH_DEFINITION):
        return
    taken[SaKppReader.BRUSH_DEFINITION] = true
    var tip: Dictionary = preset.get("tip", {})
    var brush: Dictionary = tip.get("brush", {})
    var target: Resource = settings.tip
    if target == null:
        target = SaBrushTipScript.new()
        settings.tip = target
    if brush.has("spacing"):
        settings.spacing = clampf(SaKppReader.attr_float(brush, "spacing", settings.spacing), 0.01, 5.0)
    target.angle = SaKppReader.attr_float(brush, "angle", 0.0)
    target.randomness = clampf(SaKppReader.attr_float(brush, "randomness", 0.0), 0.0, 1.0)
    target.density = clampf(SaKppReader.attr_float(brush, "density", 1.0), 0.0, 1.0)
    target.auto_spacing = SaKppSensors.truthy(String(brush.get("useAutoSpacing", "0")))
    target.auto_spacing_coeff = SaKppReader.attr_float(brush, "autoSpacingCoeff", 1.0)
    match String(tip.get("kind", "")):
        SaKppReader.TIP_GENERATED:
            var generator: Dictionary = tip.get("generator", {})
            var diameter := SaKppReader.attr_float(generator, "diameter", 40.0)
            settings.radius = diameter / 2.0 / DOCUMENT_LOWER
            target.diameter = diameter
            target.ratio = clampf(SaKppReader.attr_float(generator, "ratio", 1.0), 0.01, 1.0)
            target.spikes = maxi(int(SaKppReader.attr_float(generator, "spikes", 2.0)), 2)
            target.antialias_edges = SaKppSensors.truthy(String(generator.get("antialiasEdges", "1")))
            target.generator = int(SaKppReader.GENERATORS.get(String(generator.get("id", "default")), 0))
            target.shape = int(SaKppReader.SHAPES.get(String(generator.get("type", "circle")), SaBrushTipScript.Shape.CIRCLE))
            target.kind = SaBrushTipScript.Kind.PROCEDURAL
            target.image_path = ""
            var fade := (SaKppReader.attr_float(generator, "hfade", 1.0) + SaKppReader.attr_float(generator, "vfade", 1.0)) * 0.5
            settings.hardness.value = clampf(fade, 0.0, 1.0)
            if generator.has("softness_curve"):
                var refused := _apply_softness_curve(target, String(generator["softness_curve"]))
                if not refused.is_empty():
                    not_carried.append(refused)
        SaKppReader.TIP_IMAGE:
            var size: Vector2i = tip.get("size", Vector2i.ZERO)
            var scale := SaKppReader.attr_float(brush, "scale", 1.0)
            var diameter := maxf(float(maxi(size.x, size.y)) * scale, 1.0)
            settings.radius = diameter / 2.0 / DOCUMENT_LOWER
            target.diameter = diameter
            var written := _write_tip(tip)
            if written.is_empty():
                not_carried.append("image tip")
            else:
                var mask := SaBrushTipMask.select(target, written)
                if not mask.error.is_empty():
                    not_carried.append("image tip")
            # Krita's gradient map, the picture's lightness picking each texel's
            # colour off a gradient, is the stamp brush's Gradient Map mode. The
            # file holds no gradient, Krita taking the canvas's current one, so
            # the preset keeps the empty field that reads as the painter's colour
            # to the background, Krita's own default, and the report says so.
            if String(tip.get("application", "")) == SaKppReader.APPLICATION_GRADIENT_MAP:
                settings.tip_mode = SettingsScript.TipMode.GRADIENT_MAP
                settings.gradient = []
                notes.append(GRADIENT_FROM_THE_PAINTER)
        SaKppReader.TIP_REFUSED:
            var file_name := String(tip.get("file_name", "")).to_lower()
            # A refused pipe says why, the way a refused image tip does below,
            # so no tag says only that something was lost. The bare phrase
            # "pipe tip" left a painter unable to tell a tip missing from the
            # bundle from a file Sara failed to read.
            if file_name.ends_with(".gih"):
                var unknown := String(tip.get("selection", ""))
                if not unknown.is_empty():
                    not_carried.append("pipe selection mode %s" % unknown)
                else:
                    not_carried.append("pipe tip: " + String(tip.get("error", "refused")))
            else:
                not_carried.append("tip: " + String(tip.get("error", "refused")))
        _:
            pass


## Krita's `softness_curve` attribute onto the tip's own `Curve`. Empty when
## it carried, and the phrase to wear when it did not.
##
## **The points travel unchanged.** Krita's `KisCurveCircleMaskGenerator` reads
## its table at `norme`, the squared elliptical radius, and
## `SaBrushTip.softness_curve` is coverage against the same squared normalised
## radius, so the two axes are the one axis and there is nothing to rescale.
## The string is Krita's `x,y;` list, which is the one `SaKppSensors.parse_curve`
## already reads for a sensor.
##
## **A curve that does not descend is refused**, which is the trap
## `sa_brush_tip.gd` names: the identity `0,0;1,1` is what a preset's XML falls
## back to when nobody drew one, and it is a tip clear in the middle and opaque
## at the rim. The default falloff is kept and the preset wears a phrase saying
## which refusal it was, rather than the one that means Sara has no home for the
## feature at all, so a painter filtering the docker by tag can tell the presets
## that lost a drawn curve from the hundred that never had one.
static func _apply_softness_curve(target: Resource, text: String) -> String:
    var points := SaKppSensors.parse_curve(text)
    if points.is_empty():
        return "mask softness curve"
    if points[points.size() - 1].y >= points[0].y:
        return "mask softness curve, it does not descend"
    var curve := Curve.new()
    for point in points:
        curve.add_point(point)
    target.softness_curve = curve
    return ""


## The embedded picture into `user://brush_tips` under its own file name, so
## `image_path` points at a file that outlives the `.kpp`. The path it was
## written to, or empty. The writing itself is the tip mask's, which owns the
## folder and reads back with [method SaBrushTipMask.select].
static func _write_tip(tip: Dictionary) -> String:
    return SaBrushTipMask.save(String(tip.get("file_name", "")).get_file(), tip.get("bytes", PackedByteArray()))


## The plain numbers and switches: opacity, flow, the mode, the blend, the
## eraser, the airbrush, sharpness, the mirrors and the scatter axes.
static func _apply_numbers(options: Dictionary, settings: Resource, taken: Dictionary, not_carried: Array[String]) -> void:
    if options.has("OpacityValue"):
        settings.opacity = clampf(SaKppSensors.float_of(options, "OpacityValue", settings.opacity), 0.0, 1.0)
        taken["OpacityValue"] = true
    if options.has("FlowValue"):
        settings.flow.value = clampf(SaKppSensors.float_of(options, "FlowValue", settings.flow.value), 0.0, 1.0)
        taken["FlowValue"] = true
    # Build-up unless the preset says wash, because build-up is Krita's own
    # default and a preset with no `PaintOpAction` painted in it there. A new
    # brush here starts in wash, so the import says it rather than inheriting it.
    settings.painting_mode = SettingsScript.PaintingMode.BUILD_UP
    if options.has("PaintOpAction"):
        taken["PaintOpAction"] = true
        match int(SaKppSensors.float_of(options, "PaintOpAction", 1.0)):
            1:
                pass
            2:
                settings.painting_mode = SettingsScript.PaintingMode.WASH
            _:
                not_carried.append("painting mode")
    if options.has("CompositeOp"):
        taken["CompositeOp"] = true
        var op := SaKppSensors.string_of(options, "CompositeOp").strip_edges()
        if BLEND_MODES.has(op):
            settings.blend_mode = StringName(String(BLEND_MODES[op]))
        else:
            not_carried.append("blend mode " + op)
    if options.has("EraserMode"):
        taken["EraserMode"] = true
        if SaKppSensors.bool_of(options, "EraserMode"):
            settings.blend_mode = SaLayerScript.BLEND_MODE.ERASE
    if options.has("AirbrushEnabled"):
        settings.airbrush_enabled = SaKppSensors.bool_of(options, "AirbrushEnabled")
        taken["AirbrushEnabled"] = true
    if options.has("AirbrushRate"):
        settings.airbrush_rate = maxf(SaKppSensors.float_of(options, "AirbrushRate", settings.airbrush_rate), 0.0)
        taken["AirbrushRate"] = true
    if options.has("AirbrushIgnoreSpacing"):
        settings.airbrush_ignore_spacing = SaKppSensors.bool_of(options, "AirbrushIgnoreSpacing")
        taken["AirbrushIgnoreSpacing"] = true
    _apply_sharpness(options, settings, taken)
    # Krita's two Mirror checkboxes say which axes the *option* is allowed to
    # turn over, and `PressureMirror` is the option's own switch, so where the
    # option is on they are the option's axes and the tip keeps no standing
    # mirror at all. `SaKppSensors.OPTION_STEMS` carries the rest of the
    # option, the switch included, so nothing here writes `enabled`.
    #
    # **Krita mirrors on neither axis with the option off**, `isChecked()`
    # guarding the whole of `KisPressureMirrorOption::apply`, so the second
    # branch is Sara's own reading rather than a port, and it stands on purpose:
    # Sara draws a Mirror Tip H checkbox of its own, so the home for a preset's
    # `Mirror/HorizontalMirror` with no sensor behind it is that checkbox, and
    # dropping it instead would quietly unmirror a tip.
    if options.has("Mirror/HorizontalMirror") or options.has("Mirror/VerticalMirror"):
        var mirror_h := SaKppSensors.bool_of(options, "Mirror/HorizontalMirror")
        var mirror_v := SaKppSensors.bool_of(options, "Mirror/VerticalMirror")
        if SaKppSensors.bool_of(options, "PressureMirror"):
            settings.mirror_axis_x = mirror_h
            settings.mirror_axis_y = mirror_v
        else:
            settings.tip.mirror_horizontal = mirror_h
            settings.tip.mirror_vertical = mirror_v
        taken["Mirror/HorizontalMirror"] = true
        taken["Mirror/VerticalMirror"] = true
    if options.has("Scatter/AxisX") or options.has("Scatter/AxisY"):
        settings.scatter_axis_x = SaKppSensors.bool_of(options, "Scatter/AxisX") if options.has("Scatter/AxisX") else true
        settings.scatter_axis_y = SaKppSensors.bool_of(options, "Scatter/AxisY") if options.has("Scatter/AxisY") else true
        taken["Scatter/AxisX"] = true
        taken["Scatter/AxisY"] = true


## Sara's sharpness is a slider, a softness and a curve option: the value
## lands on the slider when the option is on, the softness lands as a
## fraction, the sensors land on `sharpness_option`, and the threshold is
## read and dropped. Nothing here is left uncarried any more.
##
## **The stem is applied here rather than through `SaKppSensors.OPTION_STEMS`**,
## which is the loop every other option goes round, because Sara splits Krita's
## one number across two homes. `SharpnessValue` is the ceiling, and Sara keeps
## the ceiling on the slider so a preset whose sensors are all off still
## sharpens by the amount the file says. The option is then how much of that
## ceiling a dab takes, so its own strength has to be one: leaving `Value` on it
## as well would square the number and a preset at 0.5 would import at 0.25.
static func _apply_sharpness(options: Dictionary, settings: Resource, taken: Dictionary) -> void:
    var on := _stem_enabled(options, "Sharpness", taken)
    if options.has("SharpnessValue"):
        settings.sharpness = clampf(SaKppSensors.float_of(options, "SharpnessValue", 0.0), 0.0, 1.0) if on else 0.0
    if options.has("Sharpness/softness"):
        settings.sharpness_softness = clampf(SaKppSensors.float_of(options, "Sharpness/softness", 0.0) / 100.0, 0.0, 1.0)
        taken["Sharpness/softness"] = true
    if options.has("Sharpness/threshold"):
        taken["Sharpness/threshold"] = true
    var option := settings.sharpness_option as SaCurveOption
    SaKppSensors.apply(option, options, "Sharpness", taken)
    if option != null:
        option.strength = 1.0


## Krita's colour smudge engine onto the smudge stage.
##
## **The engine is the switch.** Krita has no checkbox for the smudge, a
## colour smudge preset is one, so Smudge Pickup is ticked for the engine and
## for nothing else. `SmudgeRate`, the smear length, came across through the
## option table with every other curve option.
##
## **Colour rate straight through.** Krita's `ColorRate` is how much of the
## brush's own colour a dab adds, one being a plain brush and nought a pure
## smudge, and Sara's Colour Rate means the same, so the value, the tick and
## the sensors land as they stand, the way the option table carries every
## other curve option.
##
## **The radius widens the pickup.** `SmudgeRadius` is how far out the pickup
## reads as a multiple of the dab, and it lands on the brush's own
## `smudge_radius` through [_smudge_radius] below, which turns over the two
## ways Krita wrote the number.
##
## **The two rates carry.** `SmudgeRateMode` is Krita's own numbering, nought
## for smearing and one for dulling, which is exactly what
## [member SettingsScript.SmudgeMode] holds, so the number lands as it stands.
static func _apply_smudge(preset: Dictionary, settings: Resource, taken: Dictionary) -> void:
    if String(preset.get("engine", "")) != SMUDGE_ENGINE or not "smudge_pickup_option" in settings:
        return
    var options: Dictionary = preset.get("options", {})
    settings.smudge_pickup_option.enabled = true
    SaKppSensors.apply(settings.smudge_color_rate_option as SaCurveOption, options, "ColorRate", taken)
    if options.has("SmudgeRateMode"):
        taken["SmudgeRateMode"] = true
        settings.smudge_mode = (
            SettingsScript.SmudgeMode.DULLING
            if int(SaKppSensors.float_of(options, "SmudgeRateMode", 0.0)) != 0
            else SettingsScript.SmudgeMode.SMEARING
        )
    for name: String in SaKppSensors.names_of("SmudgeRadius"):
        if options.has(name):
            taken[name] = true
    if options.has("SmudgeRadiusVersion"):
        taken["SmudgeRadiusVersion"] = true
    if options.has("SmudgeRadiusValue"):
        taken["SmudgeRadiusValue"] = true
        settings.smudge_radius = clampf(_smudge_radius(options), SaSmudgePage.MIN_RADIUS, SaSmudgePage.MAX_RADIUS)


## Krita's smudge radius onto the brush's own multiple of the dab.
##
## **One value, two writers, and the tag that tells them apart.** The option's
## range was wrong for six years: the GUI showed a hundred times what the file
## stored, so a painter asking for the dab's own radius asked for a hundred of
## them. Krita fixed the range and could not simply reinterpret every preset
## already on disk, so a preset saved since carries `SmudgeRadiusVersion` at two
## and stores the fraction the row now means, and anything older, or with no tag
## at all, stores a hundred times it. The division below is that compatibility
## and nothing else: it is the same reading Krita's own option makes, and
## without it an old preset would import with a pickup a hundredth of a texel
## wide, which is a smudge that lays no carried paint at all.
static func _smudge_radius(options: Dictionary) -> float:
    var value := SaKppSensors.float_of(options, "SmudgeRadiusValue", 1.0)
    return value if int(SaKppSensors.float_of(options, "SmudgeRadiusVersion", 0.0)) >= 2 else value / 100.0


## Krita's four random offset params onto Sara's three
## rows.
##
## **Four onto three, and nothing is lost.** Krita switches the two axes
## separately and Sara has one checkbox with an amount per axis, so an axis
## Krita left switched off arrives as an amount of nought, which is the same
## paper. The checkbox goes on when either axis does, and a preset with both
## off carries an unticked box and whatever amounts it named, so ticking the
## box by hand gives the painter the jump Krita would have.
##
## `MaximumOffsetX` and `MaximumOffsetY` are read as document pixels, the unit
## Sara's own offset rows are in and the unit Krita's own spinbox counts, and
## are clamped to the page's ceiling the way the fixed offset is.
static func _apply_texture_randomizer(options: Dictionary, settings: Resource, taken: Dictionary) -> void:
    var on := false
    for axis: String in ["X", "Y"]:
        var switch := "Texture/Pattern/isRandomOffset" + axis
        var amount_key := "Texture/Pattern/MaximumOffset" + axis
        # Read whether or not the switch is on, because an amount left in the
        # file by a painter who switched the axis off again is still an amount
        # the importer has seen, and an option nobody reads is an unread option.
        if options.has(amount_key):
            taken[amount_key] = true
        if not options.has(switch):
            continue
        taken[switch] = true
        if not SaKppSensors.bool_of(options, switch):
            continue
        on = true
        var amount := clampi(int(SaKppSensors.float_of(options, amount_key, 0.0)), 0, SaTexturePage.MAX_OFFSET)
        settings.set("texture_random_offset_" + axis.to_lower(), amount)
    settings.texture_random_per_stroke = on


## The texture block onto the Texture page: the switch, the scale, the
## offset, the invert, the tone, the cutoff and the embedded pattern
## written to the painter's patterns folder under its own name. The
## strength curve is `SaKppSensors`' stem.
static func _apply_texture(preset: Dictionary, settings: Resource, taken: Dictionary, not_carried: Array[String]) -> void:
    var options: Dictionary = preset.get("options", {})
    var any := false
    for name: String in options:
        if String(name).begins_with("Texture/Pattern/"):
            any = true
            break
    if not any:
        return
    settings.texture_option.enabled = SaKppSensors.bool_of(options, "Texture/Pattern/Enabled")
    taken["Texture/Pattern/Enabled"] = true
    if options.has("Texture/Pattern/Scale"):
        settings.texture_scale = clampf(
            SaKppSensors.float_of(options, "Texture/Pattern/Scale", 1.0), SaDabPattern.MIN_SCALE, SaDabPattern.MAX_SCALE
        )
        taken["Texture/Pattern/Scale"] = true
    if options.has("Texture/Pattern/OffsetX"):
        settings.texture_offset_x = int(SaKppSensors.float_of(options, "Texture/Pattern/OffsetX", 0.0))
        taken["Texture/Pattern/OffsetX"] = true
    if options.has("Texture/Pattern/OffsetY"):
        settings.texture_offset_y = int(SaKppSensors.float_of(options, "Texture/Pattern/OffsetY", 0.0))
        taken["Texture/Pattern/OffsetY"] = true
    if options.has("Texture/Pattern/Invert"):
        settings.texture_invert = SaKppSensors.bool_of(options, "Texture/Pattern/Invert")
        taken["Texture/Pattern/Invert"] = true
    if options.has("Texture/Pattern/TexturingMode"):
        taken["Texture/Pattern/TexturingMode"] = true
        # Krita's numbers are Sara's numbers, so a preset's own value is
        # written onto the row rather than translated from it. A mode this
        # engine has no arithmetic for paints multiply and says so, and the
        # substitution is what tells those two apart.
        var mode := int(SaKppSensors.float_of(options, "Texture/Pattern/TexturingMode", 0.0))
        var carried: int = SaDabPattern.mode_for(mode)
        if carried != mode:
            not_carried.append("texturing mode")
        settings.texture_mode = carried
    _apply_texture_randomizer(options, settings, taken)
    _apply_texture_tone(options, settings, taken)
    _apply_texture_cutoff(options, settings, taken)
    if options.has("Texture/Pattern/PatternFileName"):
        taken["Texture/Pattern/PatternFileName"] = true
        var file_name := SaKppSensors.string_of(options, "Texture/Pattern/PatternFileName").get_file()
        var written := _write_pattern(preset, file_name)
        if written.is_empty():
            not_carried.append("pattern " + file_name.get_extension())
            settings.pattern_name = ""
        else:
            settings.pattern_name = SaPatternStore.name_for(written)


## Krita's three tone params onto the three tone rows, which is the mapping
## table's "texture brightness and contrast" row turning from not-carried into
## carried.
##
## **The one place the two programs disagree is what Contrast means.** Krita
## writes a multiplier, one being the pattern untouched, and Sara's row is the
## widening about the neutral point, nought being the pattern untouched, because
## nought is what every other symmetric row on the page reads as untouched and
## because `adjust.gmacs`'s Contrast already means that. So the conversion is a
## subtraction of one, and a file with no `Contrast` key leaves the row at
## nought rather than at minus one.
##
## Brightness and the neutral point are the same number in both programs, a
## pattern value and an offset on one, and both are clamped to Sara's own band
## rather than trusted, because a `.kpp` is a file somebody else wrote.
static func _apply_texture_tone(options: Dictionary, settings: Resource, taken: Dictionary) -> void:
    if options.has("Texture/Pattern/Brightness"):
        settings.texture_brightness = clampf(
            SaKppSensors.float_of(options, "Texture/Pattern/Brightness", 0.0),
            SaPatternTone.MIN_BRIGHTNESS,
            SaPatternTone.MAX_BRIGHTNESS
        )
        taken["Texture/Pattern/Brightness"] = true
    if options.has("Texture/Pattern/Contrast"):
        settings.texture_contrast = clampf(
            SaKppSensors.float_of(options, "Texture/Pattern/Contrast", 1.0) - 1.0,
            SaPatternTone.MIN_CONTRAST,
            SaPatternTone.MAX_CONTRAST
        )
        taken["Texture/Pattern/Contrast"] = true
    if options.has("Texture/Pattern/NeutralPoint"):
        SaPatternTone.take_neutral(
            settings, SaKppSensors.float_of(options, "Texture/Pattern/NeutralPoint", SaPatternTone.DEFAULT_NEUTRAL)
        )
        taken["Texture/Pattern/NeutralPoint"] = true


## Krita's cutoff band and policy onto the three cutoff rows, which is the
## mapping table's "texture cutoff" row turning from not-carried into
## carried.
##
## **Krita writes a bound as a byte and Sara stores a pattern value**, because
## every other number on the Texture page that means "a place in the paper's
## range" is a pattern value, the neutral point included, and a row that read
## 0 to 255 beside one that reads 0 to 1 would be two units for one idea. So the
## two bounds are divided by [constant SaPatternTone.KRITA_CUTOFF_FULL].
##
## The policy is Krita's own number and needs no conversion, its three values
## being the three [enum SaPatternTone.Policy] has in the same order. A file
## whose bounds have crossed is kept as it stands rather than sorted: Krita
## paints nothing through a crossed band and so does the kernel, and quietly
## swapping the two would be this importer inventing a preset its author did not
## write.
static func _apply_texture_cutoff(options: Dictionary, settings: Resource, taken: Dictionary) -> void:
    if options.has("Texture/Pattern/CutoffLeft"):
        settings.texture_cutoff_left = clampf(
            SaKppSensors.float_of(options, "Texture/Pattern/CutoffLeft", 0.0) / SaPatternTone.KRITA_CUTOFF_FULL,
            SaPatternTone.MIN_CUTOFF,
            SaPatternTone.MAX_CUTOFF
        )
        taken["Texture/Pattern/CutoffLeft"] = true
    if options.has("Texture/Pattern/CutoffRight"):
        settings.texture_cutoff_right = clampf(
            (
                SaKppSensors.float_of(options, "Texture/Pattern/CutoffRight", SaPatternTone.KRITA_CUTOFF_FULL)
                / SaPatternTone.KRITA_CUTOFF_FULL
            ),
            SaPatternTone.MIN_CUTOFF,
            SaPatternTone.MAX_CUTOFF
        )
        taken["Texture/Pattern/CutoffRight"] = true
    if options.has("Texture/Pattern/CutoffPolicy"):
        settings.texture_cutoff_policy = clampi(
            int(SaKppSensors.float_of(options, "Texture/Pattern/CutoffPolicy", 0.0)),
            SaPatternTone.Policy.OFF,
            SaPatternTone.Policy.PAPER
        )
        taken["Texture/Pattern/CutoffPolicy"] = true


## The embedded pattern into `user://patterns`, where the pattern store
## lists a painter's own, when it is a file the store reads: a `.png`, an
## `.exr`, a `.gmacs` or a `.pat`, GIMP's own format and what Krita's
## bundled papers are. The path written, or empty.
static func _write_pattern(preset: Dictionary, file_name: String) -> String:
    if file_name.is_empty() or not SaPatternStore.is_pattern_file(file_name):
        return ""
    var resources: Dictionary = preset.get("resources", {})
    var found: Dictionary = {}
    for name: String in resources:
        var resource: Dictionary = resources[name]
        if String(resource.get("type", "")) != "patterns":
            continue
        if String(resource.get("filename", "")).get_file() == file_name or found.is_empty():
            found = resource
    if found.is_empty():
        return ""
    var bytes: PackedByteArray = found.get("bytes", PackedByteArray())
    if bytes.is_empty():
        return ""
    # A `.pat` is checked before it is written, because the store lists a file
    # by its name and a corrupt one would leave the preset naming a paper that
    # never paints. Refusing here is what puts it back under "pattern pat",
    # which is where a painter reads that the paper did not come.
    if file_name.get_extension().to_lower() == SaPattern.PAT_EXTENSION:
        if not SaPatternPat.refusal_for(bytes, file_name).is_empty():
            return ""
    # Written here rather than through a store door, the way
    # `sa_pattern_capture.gd` writes a captured paper: the patterns folder has
    # no writer of its own and the tip folder's belongs to `SaBrushTipMask`.
    if DirAccess.make_dir_recursive_absolute(SaPatternStore.saved_dir()) != OK:
        if not DirAccess.dir_exists_absolute(SaPatternStore.saved_dir()):
            return ""
    var path := SaPatternStore.saved_dir().path_join(file_name.validate_filename())
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return ""
    file.store_buffer(bytes)
    file.close()
    return path


## Mix and the colour source, the two colour rows that are not a plain stem
## read.
##
## **Mix is turned over on the way in under a plain source.** Krita's Mix
## weights the foreground by the option's value, so one is the painting colour
## and nought the background. Sara's is the other way round, because all five
## colour options are off at nought. So every curve the stem carries, the common
## one and each sensor's own, has its values turned over, `y` onto `1 - y`. That
## is exact at full strength, where Krita's `1 * r` of the painting colour is
## Sara's `1 - r` of the background. Below full strength it is not, because
## Krita scales the weight towards the background and Sara scales the distance
## from the painting colour, and no curve can make `s * (1 - r)` equal `1 - s *
## r` for every `r`. The strength travels as written, which keeps the two ends
## of the stroke right and leans the middle of a half-strength one towards the
## painting colour.
##
## **Under a gradient source Mix lands as written**, Krita picking
## `colorAt(mix)` and Sara `ramp_at(dab.mix)`, each the strength times the
## curve, so the stroke walks the ramp as Krita's does at every strength, on
## Sara's default ramp, which is Krita's default gradient too and which the
## report names. Krita's other sources, `uniform_random`, `total_random`,
## `pattern` and `lockedpattern`, are tagged.
static func _apply_colour(
    options: Dictionary, settings: Resource, taken: Dictionary, not_carried: Array[String], notes: Array[String]
) -> void:
    var gradient := false
    if options.has("ColorSource/Type"):
        taken["ColorSource/Type"] = true
        var named := SaKppSensors.string_of(options, "ColorSource/Type").strip_edges()
        gradient = named == "gradient" and "color_source" in settings and "gradient" in settings
        if gradient:
            settings.color_source = SaColorDynamics.Source.GRADIENT
            settings.gradient = []
            if not notes.has(GRADIENT_FROM_THE_PAINTER):
                notes.append(GRADIENT_FROM_THE_PAINTER)
        elif named == "plain":
            if "color_source" in settings:
                settings.color_source = SaColorDynamics.Source.PLAIN
        else:
            not_carried.append("colour source")
    _apply_lightness(options, settings, taken)
    var mix := settings.get("mix_option") as SaCurveOption if "mix_option" in settings else null
    if mix == null:
        return
    var present := false
    for name: String in SaKppSensors.names_of("Mix"):
        if options.has(name):
            present = true
    SaKppSensors.apply(mix, options, "Mix", taken)
    if not present or gradient:
        return
    mix.common_curve = _turned_over(mix.common_curve)
    # `sensors` is keyed by id, so the values are the sensors.
    for sensor: SaSensor in mix.sensors.values():
        if sensor != null and sensor.curve.size() >= 2:
            sensor.curve = _turned_over(sensor.curve)


## Krita's lightness map onto the painted tip's own strength.
##
## **The stem's value and not only its switch.** The map is a strength rather
## than a yes: `LightnessStrengthValue` is the number the brush editor's
## Lightness row shows and `PressureLightnessStrength` is the switch beside it.
## A preset that switched the map on and wrote no value gets the whole of it,
## which is what a switch with no number beside it means in this format
## everywhere else.
##
## **Nothing is tagged**, because nothing is lost: the row exists on the Brush
## Tip page, which is what this stem is. The number lands whether or not the tip
## behind it carries colour, since only the picture can answer that and the mask
## asks it at load, where a grey tip's answer turns the number back into the
## neutral.
static func _apply_lightness(options: Dictionary, settings: Resource, taken: Dictionary) -> void:
    if not _stem_enabled(options, "LightnessStrength", taken):
        return
    var tip: Resource = settings.get("tip") if "tip" in settings else null
    if tip == null or not "lightness_strength" in tip:
        return
    tip.lightness_strength = clampf(SaKppSensors.float_of(options, "LightnessStrengthValue", 1.0), 0.0, 1.0)
    # Krita reads the strength in its lightness map alone, so a gradient map keeps its mode.
    if settings.get("tip_mode") != SettingsScript.TipMode.GRADIENT_MAP:
        settings.set("tip_mode", SettingsScript.TipMode.LIGHTNESS_MAP)


## *points* with every value turned over, `y` onto `1 - y`, in the same order.
static func _turned_over(points: PackedVector2Array) -> PackedVector2Array:
    var out := PackedVector2Array()
    for point: Vector2 in points:
        out.append(Vector2(point.x, 1.0 - point.y))
    return out


## The features with no home, one phrase each: the colour stems Sara has no
## option for. The colour source, the masking brush and lightness were here
## once and carry now.
static func _apply_not_carried_features(options: Dictionary, taken: Dictionary, not_carried: Array[String]) -> void:
    for stem: String in UNCARRIED_COLOUR_STEMS:
        if _stem_enabled(options, stem, taken):
            not_carried.append(String(UNCARRIED_COLOUR_STEMS[stem]))


## Whether the curve option under *stem* is switched on, its six params marked
## read either way.
static func _stem_enabled(options: Dictionary, stem: String, taken: Dictionary) -> bool:
    var on := false
    for name: String in SaKppSensors.names_of(stem):
        if options.has(name):
            taken[name] = true
    if options.has("Pressure" + stem):
        on = SaKppSensors.bool_of(options, "Pressure" + stem)
    return on
