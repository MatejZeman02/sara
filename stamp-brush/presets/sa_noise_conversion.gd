## The stamp brush's presets as the noise brush's and back: the two converters
## the stamp module registers through the door.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The conversion belongs to the other engines, so the flagship noise brush never
## grows a table of every engine beside it. This module registers stamp to noise
## and noise to stamp, and the noise module registers nothing.
##
## **What carries.** The name, tags, tip and icon (the store carries the first
## two, and the icon is drawn from the tip and size), plus the size, opacity,
## blend mode and the Size, Opacity and Saturation curve options. Hardness does
## not, because the stamp's is the tip's edge and the noise brush's is the edge of
## the holes its texture leaves, two quantities under one word.
##
## **The rest is invented from a chaos metric** for a painter to tune afterwards.
## It combines the tip's Randomness (or the widest fuzzy sensor roll), the
## Scatter strength over [constant SCATTER_FULL] dab diameters, the tip's
## sparseness (one less its Density) and its irregularity (nought for a
## procedural tip, the silhouette's jumps and gaps for an image tip) as the chance
## that at least one breaks the stroke, `1 - (1 - r)(1 - s)(1 - d)(1 - i)`. It is
## not a mean, because one strong trait is enough: a round tip scattered two
## diameters wide is a splatter, and a mean would call it a quarter chaotic.
##
## **What the metric names.** Below [constant GRAIN_BELOW] the field is Grain,
## from there it is Bristle, with the contrast and spread rising with the chaos
## between the `*_CALM` and `*_WILD` constants. A stamp painting through a
## pattern of the store's keeps it as the Picture field at the same scale
## whatever the metric reads, because that texture is what the painter chose. The
## texture's cut is written the old way and handed to the noise settings'
## `carry_cut`, which turns it into the Strength shift and curve.
##
## **Noise to stamp** carries what both share. A Picture becomes the stamp's
## pattern, its scale the texture's and its cut the Texture option. A Grain or a
## Bristle has no pattern in the store to become, so the preset wears
## `not carried: grain field` or `not carried: bristle field` with
## `not carried: strength`, the kpp import's spelling of the same fact.
extends RefCounted

const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## The two engines, by the ids their settings declare.
const STAMP: StringName = &"stamp"
const NOISE: StringName = &"noise"

## The noise brush's field ids, as its presets store them in `texture_field`.
## Written out rather than read from its module, which this one never names.
const GRAIN: String = "grain"
const BRISTLE: String = "bristle"
const PICTURE: String = "picture"

## The metadata key the preset store reads a converter's tags under,
## `SaPresetMeta.TAGS_META`, spelled here because the store is behind the door.
## Its suite holds the two spellings together.
const TAGS_META: StringName = &"tags"

## The curve options both engines read under one name and for one quantity.
const SHARED_OPTIONS: Array[String] = ["size_option", "opacity_option", "saturation_option"]

## A scatter this many dab diameters wide reads as fully chaotic. Two, because
## at two a dab lands clear of the line more often than on it and the stroke
## reads as a spray.
const SCATTER_FULL: float = 2.0

## How far a silhouette jumping between neighbouring angles counts. A circle at
## [constant OUTLINE_SAMPLES] angles moves by about a hundredth a step, which
## this makes 0.04, and a torn edge by a tenth, which makes 0.4.
const EDGE_GAIN: float = 4.0
const OUTLINE_SAMPLES: int = 64

## The longest side of a tip the gap count visits every texel of. A larger tip
## is visited on a grid this many texels wide, since the share of gaps does not
## need every texel of a 1024 pixel scan.
const GAP_GRID: int = 128

## Below this the metric names Grain, from it Bristle.
const GRAIN_BELOW: float = 0.35

## Grain's contrast at no chaos, and at full chaos, were Grain chosen there.
const CONTRAST_CALM: float = 1.0
const CONTRAST_WILD: float = 3.0

## Bristle's spread at no chaos and at full.
const SPREAD_CALM: float = 0.5
const SPREAD_WILD: float = 1.0

## The Strength row at no chaos and at full, and where its pressure curve
## stops at full chaos.
const STRENGTH_CALM: float = 0.3
const STRENGTH_WILD: float = 0.9
const FLOOR_WILD: float = 0.5

## The Picture field's scale row's range, which a stamp's texture scale is
## clamped into.
const PICTURE_SCALE_MIN: float = 0.1
const PICTURE_SCALE_MAX: float = 8.0

## The door's tool registry, untyped because its class sits behind the door.
## Asked at each conversion for the noise brush's settings, since the noise
## module may register after this one or not at all.
var _tools: Object = null


func _init(tools: Object) -> void:
    _tools = tools


## Stamp to noise: a new noise preset from *source*, or null when no tool of the
## noise engine is registered to build one from.
func stamp_to_noise(source: Resource) -> Resource:
    var target := _settings_of(NOISE)
    if target == null or source == null:
        return null
    _carry_shared(source, target)
    # The noise brush rolls along the stroke and never per dab, so a stamp's
    # per dab roll on a shared option moves onto that clock.
    if target.has_method("carry_rolls_along"):
        target.call("carry_rolls_along")
    var metric := chaos_of(source)
    var chaos: float = metric["chaos"]
    var field := field_for(source, chaos)
    target.set("texture_field", field)
    match field:
        PICTURE:
            target.set("picture_name", String(source.get("pattern_name")))
            target.set("picture_scale", clampf(float(source.get("texture_scale")), PICTURE_SCALE_MIN, PICTURE_SCALE_MAX))
        GRAIN:
            target.set("grain_contrast", lerpf(CONTRAST_CALM, CONTRAST_WILD, chaos))
        BRISTLE:
            target.set("bristle_spread", lerpf(SPREAD_CALM, SPREAD_WILD, chaos))
    var cut := SaCurveOption.create_default()
    cut.enabled = true
    _fall_to(cut, FLOOR_WILD * chaos)
    if target.has_method("carry_cut"):
        target.call("carry_cut", lerpf(STRENGTH_CALM, STRENGTH_WILD, chaos), cut)
    return target


## Noise to stamp: a new stamp preset from *source*, wearing a tag for each
## thing of the noise brush it could not carry.
func noise_to_stamp(source: Resource) -> Resource:
    if source == null:
        return null
    var target := StampSettingsScript.new()
    _carry_shared(source, target)
    var lost: Array[String] = []
    var field := String(source.get("texture_field"))
    if field == PICTURE:
        target.pattern_name = String(source.get("picture_name"))
        target.texture_scale = float(source.get("picture_scale"))
        var cut: Variant = source.call("old_cut") if source.has_method("old_cut") else null
        var texture := cut as SaCurveOption if cut is SaCurveOption else SaCurveOption.create_default()
        texture.enabled = true
        texture.strength_min = 0.0
        texture.strength_max = 1.0
        target.texture_option = texture
        if not is_zero_approx(float(source.get("picture_rotation"))):
            lost.append("picture rotation")
    else:
        lost.append("%s field" % field)
        lost.append("strength")
    if int(source.get("texture_channels")) > 1:
        lost.append("second channel")
    if not lost.is_empty():
        var tags := PackedStringArray()
        for phrase: String in lost:
            tags.append(SaKppImport.NOT_CARRIED_PREFIX + phrase)
        target.set_meta(TAGS_META, tags)
    return target


## The field the metric names for *stamp* at *chaos*: its pattern's picture
## when it paints through one, else Grain or Bristle.
static func field_for(stamp: Resource, chaos: float) -> String:
    if _textured(stamp):
        return PICTURE
    return GRAIN if chaos < GRAIN_BELOW else BRISTLE


## The metric's four readings of *stamp* and the chaos they make, each nought
## to one, under `randomness`, `scatter`, `sparseness`, `irregularity` and
## `chaos`.
static func chaos_of(stamp: Resource) -> Dictionary:
    var tip := stamp.get("tip") as Resource
    var randomness := clampf(float(tip.get("randomness")), 0.0, 1.0) if tip != null else 0.0
    if stamp.has_method("options"):
        for option: SaCurveOption in (stamp.call("options") as Dictionary).values():
            randomness = maxf(randomness, option.random_amount())
    var scatter := 0.0
    var spray := stamp.get("scatter_option") as SaCurveOption
    if spray != null and spray.enabled and (bool(stamp.get("scatter_axis_x")) or bool(stamp.get("scatter_axis_y"))):
        scatter = clampf(spray.strength / SCATTER_FULL, 0.0, 1.0)
    var sparseness := 1.0 - clampf(float(tip.get("density")), 0.0, 1.0) if tip != null else 0.0
    var irregularity := tip_irregularity(tip)
    var calm := (1.0 - randomness) * (1.0 - scatter) * (1.0 - sparseness) * (1.0 - irregularity)
    return {
        "randomness": randomness,
        "scatter": scatter,
        "sparseness": sparseness,
        "irregularity": irregularity,
        "chaos": 1.0 - calm,
    }


## How ragged *tip* is, nought for a procedural tip, one for a sequence, and
## for a picture its edge's jumps and its gaps, as the file's head says.
static func tip_irregularity(tip: Resource) -> float:
    if tip == null or not tip.call("uses_image"):
        return 0.0
    var path := String(tip.get("image_path"))
    if SaBrushTipMask.is_pipe_path(path):
        return 1.0
    var image := SaTipImage.load_from(path)
    if not image.ok():
        return 0.0
    var outline := image.outline(OUTLINE_SAMPLES)
    if outline.size() < 3:
        return 0.0
    var edge := 0.0
    for i in outline.size():
        edge += absf(outline[i].length() - outline[(i + 1) % outline.size()].length())
    edge /= float(outline.size())
    return clampf(EDGE_GAIN * edge + _gaps(image, outline), 0.0, 1.0)


## The share of the texels inside *outline* whose coverage falls short of the
## silhouette's own threshold.
static func _gaps(image: SaTipImage.Tip, outline: PackedVector2Array) -> float:
    var centre := Vector2(image.size) * 0.5
    var step := maxi(1, ceili(float(maxi(image.size.x, image.size.y)) / float(GAP_GRID)))
    var furthest := 0.0
    for y in range(0, image.size.y, step):
        for x in range(0, image.size.x, step):
            if image.at(x, y) >= SaTipImage.OUTLINE_COVERAGE:
                furthest = maxf(furthest, (Vector2(x, y) - centre).length())
    if furthest <= 0.0:
        return 0.0
    var inside := 0
    var bare := 0
    for y in range(0, image.size.y, step):
        for x in range(0, image.size.x, step):
            var offset := Vector2(x, y) - centre
            var angle := fposmod(offset.angle(), TAU)
            var reach: float = outline[int(angle / TAU * outline.size()) % outline.size()].length()
            if offset.length() / furthest > reach:
                continue
            inside += 1
            if image.at(x, y) < SaTipImage.OUTLINE_COVERAGE:
                bare += 1
    return float(bare) / float(inside) if inside > 0 else 0.0


## Whether *stamp* paints through a pattern of the store's.
static func _textured(stamp: Resource) -> bool:
    var texture := stamp.get("texture_option") as SaCurveOption
    return texture != null and texture.enabled and not String(stamp.get("pattern_name")).is_empty()


## A fresh settings resource of *engine*, the script of the settings the
## engine's tool is registered with, or null when no tool takes its presets.
func _settings_of(engine: StringName) -> Resource:
    if _tools == null:
        return null
    for descriptor: SaToolDescriptor in _tools.call("list_descriptors"):
        if descriptor.preset_engine != engine or descriptor.shared_settings == null:
            continue
        var script := descriptor.shared_settings.get_script() as Script
        if script != null and script.can_instantiate():
            return script.new() as Resource
    return null


## What both engines hold under one name and mean alike, copied so the target
## shares no resource with the preset it came from.
static func _carry_shared(source: Resource, target: Resource) -> void:
    target.set("radius", float(source.get("radius")))
    target.set("opacity", float(source.get("opacity")))
    target.set("blend_mode", source.get("blend_mode"))
    var tip := source.get("tip") as Resource
    if tip != null:
        target.set("tip", tip.duplicate(true))
    for key: String in SHARED_OPTIONS:
        var option := source.get(key) as SaCurveOption
        if option != null and target.get(key) is SaCurveOption:
            target.set(key, option.duplicate(true))


## Bends *option*'s pressure line to fall from one at no pressure to *lowest*
## at full, on the shared curve and the pressure sensor's own.
static func _fall_to(option: SaCurveOption, lowest: float) -> void:
    var falling := PackedVector2Array([Vector2(0.0, 1.0), Vector2(1.0, lowest)])
    option.common_curve = falling
    var pressure := option.sensor_for(SaSensor.Id.PRESSURE)
    if pressure != null:
        pressure.curve = falling.duplicate()
