## The noise brush's settings: the few fields its page shows, the tip, and the
## curve options the door's dynamics reads.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Built on the door and nothing else.** `SaDynamics` reads its options by
## field name and `SaBrushTip` is the door's tip resource, so this file names
## no class of another module. A third party writing a brush engine would write
## this file the same way, which is the point of building on the door.
##
## **The page is reduced on purpose.** The spec's option page is Size,
## Opacity, Hardness, Tip, Texture, Strength, Thickness, Randomness, Blend mode
## and Chroma variation. The tip's Warp went, because a warp that differs per
## dab is the visible stamp, and so did rolls drawn per dab.
## Spacing is not a field at all: the stroke is swept rather than walked in
## dabs, so a preset's spacing means nothing to it.
##
## **The pressure is the cut** (designs 2 and 3 of the rework in the spec). A
## texel paints where the pressure reaches the field's value, and Strength is
## how far the whole field is shifted against the pressure, nought by default.
## Settings stored while Strength was the cut itself are brought over by
## [method migrate], which the preset store calls on every load.
extends Resource

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")
const SaLayerScript = preload("res://core/api/document/sa_layer.gd")
const NoiseFieldsScript = preload("res://modules/sara-noise-brush-engine/noise_fields.gd")
const NoiseFieldFolderScript = preload("res://modules/sara-noise-brush-engine/field_folder/noise_field_folder.gd")
const NoiseFieldReadingScript = preload("res://modules/sara-noise-brush-engine/noise_field_reading.gd")
const NoiseOldCutScript = preload("res://modules/sara-noise-brush-engine/presets/noise_old_cut.gd")

## The engine a preset written from these settings belongs to. The preset
## store stamps it into the file and reads it back, which is what tells a noise
## preset from a stamp one, and it reads as "Noise" in a preset's name when
## another engine converts one.
const PRESET_ENGINE: StringName = &"noise"

## How far Chroma variation at full swings each dab's hue either way from a
## middle grey of texture to black or white, in half-turns of the colour
## circle, and its saturation, in the units of `SaColorDynamics`, where one is
## `MAX_CHROMA_SHIFT` of Oklab chroma. 0.15 of a half-turn is twenty-seven
## degrees, a hue that wanders without leaving its family, and
## three tenths of the shift is 0.12 of chroma, which greys a strong colour by
## about half at the texture's darkest.
const HUE_SWING: float = 0.15
const SATURATION_SWING: float = 0.3

## How much longer the tip grows along the pen's lean at the stretch option's
## full answer, as a fraction of its length. One makes a pen laid flat
## paint a tip twice as long, and Thickness's elevation curve halves the
## deposit there, so the same paint covers the doubled area.
const TILT_STRETCH: float = 1.0

## The speed sensor's reading a fast hand reaches, where the speed curves of
## a fresh preset stop moving. The door reads full speed at thirty pixels a
## millisecond, a flick across a screen-wide canvas in a fifteenth of a second,
## so a curve that ran all the way there would barely move under a quick
## stroke. Three tenths is nine pixels a millisecond.
const FAST: float = 0.3

## The names a preset's `pressure` block and a `brush` step's `pen_settings`
## may give a curve option besides its page's own. `radius` is the field the
## Size row writes, and Size's option is what scales it, so a recipe that puts
## the radius on the pen's pressure says so by the field's name.
const OPTION_ALIASES: Dictionary = {"radius": "size"}

## The share of the Size row the radius falls to at no pressure, once a preset
## or a step puts it on the pen's pressure. A third, so a stroke pressed in and
## let go comes to a point at both ends and its lightest touch still lays a mark
## a third as wide rather than none.
const RADIUS_AT_NO_PRESSURE: float = 1.0 / 3.0

## The power the radius rises along between that third and the full row, the
## stamp's Size by Pressure switch's own, its size gamma of two times the
## tool's 2.4. A hand finds the noise brush's width where it finds the stamp's,
## and the harness pen's table, which is fitted to that switch's curve, makes a
## door stroke's width follow the pressure sent nearly in proportion. On a
## straight line the table's 0.2 reaches the brush as about 0.7, and a taper
## sent from 0.2 keeps about four fifths of its width.
const RADIUS_EXPONENT: float = 4.8

## How many control points [method radius_pressure_curve] draws the power with,
## the stamp's migration's nine, through which the door's monotone spline passes.
const RADIUS_CURVE_POINTS: int = 9

## What [method migrate] brings stored settings up to, and what a file saved
## since carries. Six spreads Texture Tone and Strand Softness wider, five has
## the Look page's rows, four reads the smudge's
## Colour Rate, three rolls along the stroke and has no warp, two is the
## pressure as the cut, one Strength as the cut.
const FORMAT_VERSION: int = 6

## `NOISE_TEXTURE_TONE` in `noise_dab.gmacs`, the stops Texture Tone at one
## moves the paint's lightness either way.
const TEXTURE_TONE_STOPS: float = 1.5

## Which format these settings were written in, declared at one, the format
## before it had a number, and stamped at [constant FORMAT_VERSION] at
## construction, so a file saved since carries the number and one saved before
## carries none.
##
## **A file with no number cannot be told by the number alone.** Godot runs
## `_init` before it writes the file's values over the new object, and a key
## the file does not have keeps what `_init` left, so an old file loads at the
## current number like a new one. What tells them apart is which values the
## load wrote: every file carries Strength's curve option, a sub-resource, and
## only a file saved since carries this number. The setters note what was
## written, and [method migrate] reads the notes.
@export var format_version: int = 1:
    set(value):
        format_version = value
        _wrote_version = true

## A fraction of the canvas's smaller dimension, which is what the Size row and
## the tool machine's bracket keys write. The stamp's own default, so the two
## brushes start at the same width.
@export var radius: float = 0.02314814815

## Opacity and flow as one, as one row: a stroke reaches this
## and stops. It is the stroke's opacity, applied once when the stroke lands,
## and the dab lays its own coverage under the wash ceiling. It holds zero to
## one whatever writes it, a preset file as much as the door, because 1.074
## from a script's jitter laid alpha 1.074 on an empty layer, coverage above
## one that paint over it lifts. The range lets the door's `brush` step refuse
## a number outside it rather than paint the clamp.
@export_range(0.0, 1.0) var opacity: float = 1.0:
    set(value):
        opacity = clampf(value, 0.0, 1.0)

## The width of the soft band under the cut, read the other way round: one is
## a hard cut, where a texel paints fully or not at all, and nought fades a
## texel in over the whole range beneath the cut. The stamp's Hardness is the
## tip's edge, and this one is the edge of the holes the texture leaves, which
## is where a light stroke's opacity comes from. Below one it also thins the
## grain towards the stroke's rim, from all of it at its own share of the way
## out to none at the rim, as a round's soft edge falls. High by default, so a
## light stroke reads as paint with holes rather than as a haze.
@export var hardness: float = 0.8

## How far the whole field is shifted against the pressure, minus one to one,
## before its sensors. A texel paints where the pressure reaches the field's
## value plus this, so above nought a texel needs a firmer press and below
## nought a lighter one. Nought by default, where white needs the full pressure
## and black takes paint at any.
@export var strength: float = 0.0:
    set(value):
        strength = value
        _wrote_strength = true

## The tip's shape, the door's resource, so a preset carries it whole.
@export var tip: Resource = SaBrushTipScript.new()

## Whether a stroke's seed is rolled at all. Nought holds the stroke's seed at
## [member held_seed], so every stroke of the preset paints the same field and
## rolls its options the same way along it. Above nought each stroke draws a
## seed of its own, and how far above makes no difference: nothing else is
## scaled by it.
@export var randomness: float = 0.5

## The seed a stroke is laid with while Randomness is nought, carried by the
## preset so a held preset paints its field on every machine. Never nought,
## which the door's stroke sample reads as "draw one".
@export var held_seed: int = 1

## Picture: the pattern's name in the store. Declared before the field, because
## a preset is copied in the order the properties are declared, and a preset
## that turns to the Picture field then makes only the pattern it names rather
## than the old name's first.
@export var picture_name: String = "Paper Grain":
    set(value):
        picture_name = value
        _choose_picture()

## The field the stroke paints through, an id `noise_fields.gd` has
## registered. Grain by default, and Grain with a notice when the settings
## hold their fields and none has the id, a preset naming a painter's field
## whose file has gone.
@export var texture_field: String = "grain":
    set(value):
        texture_field = value
        _keep_a_field()
        _choose_picture()

## The numbers of the painter's own fields, the ones a `.gmacs` file in the
## noise brush's folder brings, by the key `noise_field_folder.gd` makes, so a
## preset carries them. A key with no entry reads as its field's default.
## Copied on every write, so a preset's dictionary is never the live brush's.
@export var field_numbers: Dictionary = {}:
    set(value):
        field_numbers = value.duplicate()

## One or two channels, for a field that has two. With one the field's
## lightness is its coverage, and with two it is a second reading.
@export var texture_channels: int = 1

## How far the second channel's lightness is stretched about its middle, so
## nought is a flat grey. The lightness is what [member thickness] deposits.
@export var texture_relief: float = 1.0

## How far the field slides along with the brush, shared by every field.
## Nought leaves the field where the stroke laid it, so the pen moves over a
## still texture, and one carries it with the tip, so a streak runs the whole
## stroke the way a bristle drags. Nought by default.
@export var texture_drift: float = 0.0

## Grain: the speck's width in document pixels, and how hard the grain is
## stretched about its middle.
@export var grain_scale: float = 5.0
@export var grain_contrast: float = 2.0

## Bristle: how many streaks lie across the stroke, how far each strays from an
## even comb, and how long a streak runs before it breaks, in brush widths.
@export var bristle_count: int = 24
@export var bristle_spread: float = 0.5
@export var bristle_length: float = 1.5

## The look a flat, firm fill with a texture in its tone is made of, the rows
## `noise_look_rows.gd` puts on the Look page. Each rest paints as the brush
## did before the rows were there, so a preset that names none of them, and
## every preset saved before format 5, keeps its look.
##
## Fill: the share of the field's pressure map drawn down towards nothing, so
## at one the stroke's body paints at any press past Strength's shift whatever
## the field says, and the field shows only in the tone and the relief.
@export var fill: float = 0.0

## Texture Tone: how far the field's lightness moves the paint's own, darker
## where the field is dark and lighter where it is light, a stop and a half
## either way at one, the field's lightness spread over its own range first. The texture laid in the paint
## rather than cut out of it.
@export var texture_tone: float = 0.0

## Bristle's strands: their width as a multiple of the widths each draws, how
## soft their edges are, and how much of the narrowing to a point at the end of
## a run is kept. Strand Softness scales each strand's draw of softness up to
## a half, so nought draws every strand at its sharpest, a half lets each draw
## its own and one draws half of them at their softest, and from one to two it
## fades every soft strand's edge further into it, over a third of its width
## at two. A half by default, and the width and the taper at one.
@export var strand_width: float = 1.0
@export var strand_softness: float = 0.5:
    set(value):
        strand_softness = value
        _wrote_strand_softness = true
@export var strand_taper: float = 1.0

## Rim Firmness: how much of the band the rim thins over Hardness leaves is
## taken away, so the outline stays firm under a soft cut, and how far the
## edge's nicks fade, gone from a half up. Nought by default, where
## Hardness alone sets it.
@export var rim_firmness: float = 0.0

## Build Up: the share of what a return over the stroke's own paint lays that
## is added to the paint there rather than washed. One by default, where a
## scrub builds up by all of it, and nought lays a return as a wash.
@export var build_up: float = 1.0

## Picture: the size of one repeat against the pattern's own pixels, its turn in
## degrees, and whether its light parts take paint first rather than its dark
## ones. The pattern's name is [member picture_name], above the field.
@export var picture_scale: float = 1.0
@export var picture_rotation: float = 0.0
@export var picture_invert: bool = false

## How much paint the stroke lays in height, in virtual millimetres, before
## its sensors: the brush's own height at a texel is the field's lightness
## times this times [member thickness_option]'s answer, the pen's pressure by
## default. Half a millimetre at full, where a height of 1.0 is one virtual
## millimetre. Nought writes no height and gains the layer none.
@export var thickness: float = 0.5

## How much more height the edge of the tip the pen leans to lays than its
## middle, minus one to one, before [member thickness_lean_option]. The
## Thickness at a texel is multiplied by one plus this times where the texel
## lies along the lean, one at the edge the pen leans to and minus one at the
## opposite edge, so the first lays this share more, the second this share
## less, and the middle the Thickness untouched, in a straight line between.
## Below nought the opposite edge is the heavier, so the side can be turned
## round if the lean reads backwards. Nought by default, which lays every
## texel of a dab at one height and keeps a preset's look.
@export var thickness_lean: float = 0.0

## How loaded the brush is, nought to one: the share of the gap to its own
## height a stroke closes where it covers fully. A preset sets it, not a row.
@export var paint_load: float = 1.0

## Whether the stroke pushes the colour of the paint on the layers below its
## own, where its own layer holds none, weighed by that paint's height, the
## Background and the grounds left out. On by default, and off pushes the
## layer's own paint alone. A preset saved without the key loads it on.
@export var push_colour_below: bool = true

## The paint exposure in stops, the foreground's own in `SaColors`, read and
## written here for the bar's Exposure as the stamp's settings do. Not
## exported, so no preset carries it and a preset's old `exposure` multiplier
## is read without it.
var paint_exposure: float:
    get:
        return SaPaintExposure.current()
    set(value):
        SaPaintExposure.move_to(value)

## Which blend mode the stroke lands through, an id of the registry's list.
@export var blend_mode: StringName = SaLayerScript.BLEND_MODE.NORMAL

## How far the picked colour's hue and saturation follow the texture, nought
## to one. A binding rather than a number of its own: the press
## writes it into Hue and Saturation as the door's texture sensor, through
## [method bind_chroma], so the curve editor shows it and a preset carries it.
@export var chroma_variation: float = 0.0

## The picked colour, written by the module from the bus. Exported like the
## stamp's, and harmless for the same reason: the bus overwrites it on the
## first pick.
@export var color: Color = Color(1.0, 1.0, 1.0, 1.0)

## The pair's other half, for the door's colour dynamics. Not exported, since
## the pair belongs to the painter rather than to the brush.
var background_color: Color = Color(0.0, 0.0, 0.0, 1.0)

## Whether a stroke shows its front, the round end under the pen, while it is
## drawn. Not exported and on no control: a scenario turns it off through the
## `brush` step to lay a stroke as its body alone paints it, beside one with
## the front, and nothing a painter keeps carries it.
var front_shown: bool = true

## The door's pattern store the Picture field reads, set by the module when it
## registers and not exported, since a store is not a preset's to carry. The
## state makes its own when a suite built the settings without the module.
var pattern_store: SaPatternStore = null:
    set(value):
        pattern_store = value
        _choose_picture()

## The fields the Texture row lists, `noise_fields.gd`'s registry, set by
## the module beside the store for the same reason. Null means the shipped
## three, which is what the state reads then.
var fields: RefCounted = null:
    set(value):
        fields = value
        _choose_picture()

## The pattern [member picture_name] names, made while the Picture field is the
## chosen one and a store is set, so a press only binds it. Not
## exported, and made again by the next settings that name a pattern.
var chosen_picture: NoiseFieldsScript.Picture = NoiseFieldsScript.Picture.new()

## The curve options the page's rows have. The first three are read by
## `SaDynamics` under the name the stamp's settings use, and all three start
## off, so a fresh brush is its rows and Opacity sits at full: pressure is the
## cut rather than the opacity, which is design 1 of the spec. Strength's is
## read by the state, since the door's dynamics has no field for a shift, and
## it starts off with no sensor, since the pressure is the cut itself and a
## Strength that also fell with it would read the pen twice.
@export var size_option: SaCurveOption = _option(false)
@export var opacity_option: SaCurveOption = _option(false)
@export var hardness_option: SaCurveOption = _option(false)
@export var strength_option: SaCurveOption = _option(false):
    set(value):
        strength_option = value
        _wrote_strength_option = true

## What the Thickness row is multiplied by, read by the state for the same
## reason as Strength's. Pressure along a rising line, which is the spec's
## "times the dab's pressure", times the pen's elevation and its speed:
## a pen laid flat and a fast hand each halve the deposit, since the same
## paint spreads over twice the tip or twice the length. A fast hand is
## [constant FAST] of the door's full speed. Each sensor keeps a
## curve of its own, so a painter unbinds any of the three in the curve editor
## and bends the others alone.
@export var thickness_option: SaCurveOption = _thickness_option()

## How far the pen's lean stretches the tip along the lean, read by the state.
## On the pen's elevation along a falling line, so an upright pen paints
## the tip as drawn and one laid flat stretches it to [constant TILT_STRETCH]
## more of its length. The lean's direction is the axis, which the state reads
## off the tilt itself, and this option is its amount. It turns a round tip
## to the lean and grows any other along its own axes, so it never turns a
## picture.
@export var stretch_option: SaCurveOption = _stretch_option()

## How far the tip is turned from its own angle, read by the door's dynamics
## under the stamp's name and to the stamp's rule. Off and carrying no sensor,
## so a picture tip lies as drawn whatever the pen does, and a preset that
## wants it to follow the lean, the heading or the twist switches it on with
## that sensor, as on the stamp.
@export var rotation_option: SaCurveOption = _option(false)

## What the Thickness Lean row is multiplied by, read by the state. On the
## pen's elevation along a falling line, so an upright pen lays an even dab
## whatever the row says and one laid flat lays the row's full difference.
## The lean's direction is the axis, the one the stretch reads off the tilt.
@export var thickness_lean_option: SaCurveOption = _stretch_option()

## What the Drift row is multiplied by, read by the state. On the pen's
## speed, from one at rest to twice at [constant FAST], so a fast stroke carries
## the field further and its streaks draw out. Nothing drifts while the Drift
## row is at nought, whatever the speed, and the carry never outruns the pen.
@export var drift_option: SaCurveOption = _speed_drift_option()

## How far the dab moves the picked colour's chroma, read by the door's colour
## dynamics exactly as the stamp's is. On, because its page is the only option
## on it and so draws no switch, and carrying no sensor, which `SaDynamics`
## reads as no shift: a brush nobody touched paints the picked colour. Here for
## the lift-up, which greys the paint as the pen lets go, and for the
## texture a preset binds to it.
@export var saturation_option: SaCurveOption = _option(true)

## How far the dab turns the picked colour's hue, the same door option the
## stamp reads, and on for the reason Saturation is. Here for Chroma
## variation, which binds it to the texture.
@export var hue_option: SaCurveOption = _option(true)

## The smudge stage, the stamp's own: the stroke picks paint up from under the
## dab and drags it along, mixed into the colour it lays. The door's
## `SaDynamics` reads the three options by these names, so they mean here what
## they mean on the stamp. [member smudge_pickup_option] is the switch, off by
## default, so a noise brush nobody touched lays its own colour alone, and the
## colour rate starts ticked at a half, so ticking the pickup paints and
## smudges at once.
@export var smudge_pickup_option: SaCurveOption = SaSmudgePage.option(0.3)
@export var smudge_color_rate_option: SaCurveOption = SaSmudgePage.option(0.5, true)
@export var smudge_length_option: SaCurveOption = SaSmudgePage.option(0.9)

## The Smudge Dilution a file written before format 4 carries, which
## [method migrate] turns into [member smudge_color_rate_option] and drops.
## Null and so never written, and here so a load has a field to put it on.
@export var smudge_dilution_option: SaCurveOption = null

## How far out the pickup reads, as a multiple of the dab's own radius, one
## being the dab itself.
@export var smudge_radius: float = 1.0

## Which of the stage's two rates the stroke paints at, the numbers
## [constant SaSmudgePage.SMEARING] and [constant SaSmudgePage.DULLING] name,
## the stamp's `smudge_mode` meaning.
@export var smudge_mode: int = SaSmudgePage.SMEARING

## Whether the pickup reads the composite or only the layer being painted, the
## stamp's `smudge_sample_merged` meaning, and on for the reason it is there.
@export var smudge_sample_merged: bool = true

## The Chroma variation and Hue option last bound, so a press binds when the row
## moved or a load replaced the options, and a hand tick at nought is kept.
var _bound_chroma: float = 0.0
var _bound_hue: SaCurveOption = null

## Which of the three values [method migrate] reads a load wrote: the format's
## number, Strength and Strength's curve option. All three false after
## construction, since an initial value calls no setter and `_init` puts the
## first back.
var _wrote_version: bool = false
var _wrote_strength: bool = false
var _wrote_strength_option: bool = false
## Whether a load wrote Strand Softness, since a file of format five that holds
## the rest it had then holds no number for it, and loads the rest of now.
var _wrote_strand_softness: bool = false


func _init() -> void:
    format_version = FORMAT_VERSION
    _wrote_version = false
    _wrote_strand_softness = false


## Brings stored settings up to date, and answers whether it did anything. The
## preset store calls it on every load, and settings made here or loaded from a
## file saved since are left alone.
##
## Format one, Strength as the cut, carries the old cut by
## `presets/noise_old_cut.gd`'s rule and reads a stored picture inverted, since
## its light parts took paint first. Formats one and two move their per dab
## rolls along the stroke. Their Warp needs no step, since a stored Warp writes
## nowhere: the class has no such property. Format three and below carry the
## smudge's dilution, which the door's page turns over into its colour rate.
## Format four and below need no step for the Look page: a file without its
## rows loads them at their rests, which paint as the brush did, so only the
## number moves. Format five's Look rows are carried onto the wider ranges by
## [method carry_look].
func migrate() -> bool:
    var stored := _stored_format()
    if stored >= FORMAT_VERSION:
        return false
    if stored < 2:
        carry_cut(strength if _wrote_strength else 1.0, strength_option)
        if texture_field == NoiseFieldsScript.PICTURE:
            picture_invert = true
    if stored < 3:
        carry_rolls_along()
    if smudge_dilution_option != null:
        smudge_color_rate_option = SaSmudgePage.color_rate_of(smudge_dilution_option)
        smudge_dilution_option = null
    if stored == 5:
        carry_look()
    format_version = FORMAT_VERSION
    return true


## Carries format five's Texture Tone and Strand Softness onto format six's
## ranges, so a stored brush paints as it did. Strand Softness's old range is
## the lower half of the new one, the same draws at half the number. Texture
## Tone was a share of the colour either way, `1 + 0.5 t (2 y - 1)`, and is now
## [constant TEXTURE_TONE_STOPS] stops either way of the field's lightness
## spread over its range by `NoiseFieldReading.tone_stretch`. The two agree in
## their slope at the field's middle grey when the new tone is the old times a
## half over the stops, the natural log of two and that stretch, and a tone of
## Firm Fill's 0.6 lays within a twentieth of a stop of the old one at the
## field's ends.
func carry_look() -> void:
    if _wrote_strand_softness:
        strand_softness *= 0.5
    var two := texture_channels > 1
    var stretch := NoiseFieldReadingScript.tone_stretch(texture_field, two, grain_contrast, texture_relief)
    texture_tone *= 0.5 / (TEXTURE_TONE_STOPS * log(2.0) * stretch)


## The format a load wrote these settings in: the number the file carried, one
## for a file with no number, which still carries Strength's curve option as
## every file does, and the current format for settings made here.
func _stored_format() -> int:
    if _wrote_version:
        return format_version
    return 1 if _wrote_strength_option else FORMAT_VERSION


## Moves every roll drawn per dab onto the along-the-stroke clock at its own
## curve and switch, named by its option when it had no name, so two moved rolls
## do not move together. Public, for the stamp's converter's per dab rolls.
func carry_rolls_along() -> bool:
    var moved := false
    var rolled := _curve_options()
    for key: String in rolled:
        var option: SaCurveOption = rolled[key]
        var roll := option.sensor_for(SaSensor.Id.FUZZY_PER_DAB)
        if roll == null:
            continue
        var along := SaSensor.create(SaSensor.Id.FUZZY_ALONG_STROKE, roll.active)
        along.curve = roll.curve.duplicate()
        along.resource_name = key if roll.resource_name.is_empty() else roll.resource_name
        option.sensors.erase(int(SaSensor.Id.FUZZY_PER_DAB))
        option.set_sensor(along)
        moved = true
    return moved


## Every curve option these settings store, the smudge stage's among them, by
## its name less the `_option` suffix, the name a randomise control rolls by.
func _curve_options() -> Dictionary:
    var found := {}
    for property: Dictionary in get_property_list():
        if not (int(property["usage"]) & PROPERTY_USAGE_STORAGE):
            continue
        var value: Variant = get(String(property["name"]))
        if value is SaCurveOption:
            found[String(property["name"]).trim_suffix("_option")] = value
    return found


## Writes Strength and its curve option for the old cut *old_strength* times
## *old_option*. Public, because the stamp's converter names its cut the old
## way, from a chaos metric written for it.
func carry_cut(old_strength: float, old_option: SaCurveOption) -> void:
    var shift: NoiseOldCutScript.Shift = NoiseOldCutScript.carry(old_strength, old_option)
    strength = shift.strength
    strength_option = shift.option


## The old cut that paints what Strength and its curve paint now, which the
## stamp's converter hands to the stamp's Texture option, since that reads a
## cut the old way.
func old_cut() -> SaCurveOption:
    return NoiseOldCutScript.read_back(strength, strength_option)


## Every curve option by the name the brush editor's pages use, which is also
## the shape `SaDynamics` asks for when it has to find them all.
func options() -> Dictionary:
    return {
        "size": size_option,
        "opacity": opacity_option,
        "hardness": hardness_option,
        "strength": strength_option,
        "thickness": thickness_option,
        "stretch": stretch_option,
        "rotation": rotation_option,
        "thickness_lean": thickness_lean_option,
        "drift": drift_option,
        "saturation": saturation_option,
        "hue": hue_option,
    }


## The curve option *key* names, by its page's name in [method options] or by
## one of [constant OPTION_ALIASES], or null for a name these settings lack.
func option_for(key: String) -> SaCurveOption:
    return options().get(String(OPTION_ALIASES.get(key, key)), null) as SaCurveOption


## The curve the radius is read along on the pen's pressure: from
## [constant RADIUS_AT_NO_PRESSURE] at no pressure up the power
## [constant RADIUS_EXPONENT] to the whole Size row at a full press.
static func radius_pressure_curve() -> PackedVector2Array:
    var points := PackedVector2Array()
    for index in RADIUS_CURVE_POINTS:
        var x := float(index) / float(RADIUS_CURVE_POINTS - 1)
        points.append(Vector2(x, lerpf(RADIUS_AT_NO_PRESSURE, 1.0, pow(x, RADIUS_EXPONENT))))
    return points


## Switches *option* on and reads it along *curve* on the pen's pressure, the
## binding a preset's `pressure` block makes. The curve is the option's shared
## one as well as the sensor's, so the option reads it whether or not the
## editor's Share one curve is on.
static func bind_pressure(option: SaCurveOption, curve: PackedVector2Array) -> void:
    var pressure := SaSensor.create(SaSensor.Id.PRESSURE, true)
    pressure.curve = curve.duplicate()
    option.set_sensor(pressure)
    option.common_curve = curve.duplicate()
    option.enabled = true


## Writes what a scenario's `pen_settings` asks onto the curve options, the
## shape the stamp's settings read: `{"radius": {"enabled": true, "sensors":
## ["pressure"]}}`. The `brush` step hands it here by the method's name when
## its `tool` is the noise brush, which is how a step turns the radius on the
## pen's pressure. A key is a name [method option_for] knows, and a field the
## option has is set as given. A name or a field it does not know is skipped.
func apply_pen_settings(spec: Dictionary, _straight: bool = false) -> void:
    for key: String in spec:
        var option := option_for(key)
        if option == null or not spec[key] is Dictionary:
            continue
        var offset := SaDynamics.is_offset(StringName(String(OPTION_ALIASES.get(key, key)) + "_option"))
        var asked: Dictionary = spec[key]
        for field: String in asked:
            if field == "sensors":
                _tick_sensors(option, asked[field], offset)
            elif field in option:
                option.set(field, asked[field])


## Every sensor *keys* names switched on on *option*, a key or a dictionary
## carrying one under `id` and the sensor's own fields beside it, as the stamp's
## settings read them. The lift-up is bound through the door's binding, which
## *offset* picks the curve of, since on the identity curve it reads backwards.
##
## **Pressure on Size that has none draws the radius's own curve**, the one Grain
## Round ships with, so a step that turns the radius on for another preset gets
## the taper that preset paints rather than a straight line to nothing, and a
## pressure Size already reads keeps the curve it has.
func _tick_sensors(option: SaCurveOption, keys: Variant, offset: bool) -> void:
    if not keys is Array:
        return
    for key: Variant in keys as Array:
        var asked: Dictionary = key if key is Dictionary else {}
        var name := String(asked.get("id", "")) if key is Dictionary else String(key)
        var id := SaSensor.id_of(name)
        if id < 0:
            continue
        if id == SaSensor.Id.LIFT_UP:
            option.bind_lift_up(offset)
            continue
        var sensor := option.sensor_for(id as SaSensor.Id)
        if sensor == null and id == SaSensor.Id.PRESSURE and option == size_option:
            bind_pressure(option, radius_pressure_curve())
            sensor = option.sensor_for(SaSensor.Id.PRESSURE)
        elif sensor == null:
            sensor = SaSensor.create(id as SaSensor.Id, true)
        sensor.active = true
        for field: String in asked:
            if field != "id" and field in sensor:
                sensor.set(field, asked[field])
        option.set_sensor(sensor)


## Binds Hue and Saturation to the texture sensor at the row's swing, when the
## row has moved since the last binding or is on over options a load replaced.
## Called at the press, since a plain row has no call of its own.
func bind_chroma() -> void:
    if is_equal_approx(chroma_variation, _bound_chroma) and (hue_option == _bound_hue or chroma_variation <= 0.0):
        return
    _bound_chroma = chroma_variation
    _bound_hue = hue_option
    var amount := clampf(chroma_variation, 0.0, 1.0)
    hue_option.bind_texture(amount * HUE_SWING)
    saturation_option.bind_texture(amount * SATURATION_SWING)


## An option with a curve that is read and no sensor yet, so the first one a
## painter ticks takes effect without a second switch.
## Makes [member chosen_picture] for the pattern the settings name, when the
## Picture field is the chosen one and there is a store to ask.
##
## **The hook that keeps the read out of the stroke**. The row
## and a preset write these settings through `set`, the tool options by
## `set_indexed` and the preset store by `copy_settings`, so the setters of
## the field, the pattern's name, the store and the registry are where a
## pattern is chosen, the way the stamp's pressure toggles follow their rows.
## Settings with no store do nothing, which is a preset read off disk for a
## thumbnail or a listing, never a brush's own, and the next write after a
## store arrives makes it. The name is declared before the field, so a preset
## that turns to the Picture field names its pattern before it turns and makes
## one picture rather than two.
func _choose_picture() -> void:
    if pattern_store == null or chosen_picture == null:
        return
    var picked := false
    if fields != null and fields.has_method("field"):
        var field: SaBrushFieldRegistry.Field = fields.field(texture_field)
        picked = field != null and field.is_picture()
    else:
        picked = texture_field == NoiseFieldsScript.PICTURE
    if picked:
        chosen_picture.choose(pattern_store, picture_name)


## Grain in place of a field the settings' fields do not have, with a notice
## in the canvas corner that names the file the field would be read from.
## Settings with no fields, a preset read off disk, keep the id as stored.
func _keep_a_field() -> void:
    if fields == null or not fields.has_method("field") or fields.field(texture_field) != null:
        return
    if texture_field == NoiseFieldsScript.GRAIN or fields.field(NoiseFieldsScript.GRAIN) == null:
        return
    var missing := texture_field
    var path := SaBrushFieldRegistry.folder_for(NoiseFieldsScript.ENGINE).path_join(missing + ".gmacs")
    texture_field = NoiseFieldsScript.GRAIN
    EventBus.paint_refused.emit(
        (
            TranslationServer.translate(
                "The brush's texture '%s' is missing, so it paints with Grain. Put %s back to have it again."
            )
            % [missing, path]
        )
    )


## One of the painter's own fields' numbers, [member field_numbers]'s entry or
## the field's default, and null for any other name.
func _get(property: StringName) -> Variant:
    var key := String(property)
    if not key.begins_with(NoiseFieldFolderScript.NUMBER_PREFIX):
        return null
    if field_numbers.has(key):
        return field_numbers[key]
    var named := key.trim_prefix(NoiseFieldFolderScript.NUMBER_PREFIX)
    var at := named.rfind("_")
    var field: SaBrushFieldRegistry.Field = fields.field(named.left(at)) if fields != null and at > 0 else null
    var index := named.substr(at + 1).to_int() - 1
    if field == null or index < 0 or index >= field.fallbacks.size():
        return null
    return field.fallbacks[index]


## Writes one of the painter's own fields' numbers into [member field_numbers],
## and answers false for any other name, which the class's own properties take.
func _set(property: StringName, value: Variant) -> bool:
    var key := String(property)
    if not key.begins_with(NoiseFieldFolderScript.NUMBER_PREFIX) or not (value is float or value is int):
        return false
    var numbers := field_numbers.duplicate()
    numbers[key] = float(value)
    field_numbers = numbers
    return true


static func _option(on: bool) -> SaCurveOption:
    var option := SaCurveOption.new()
    option.enabled = on
    option.use_curve = true
    return option


## Thickness's option: pressure along the rising line, elevation from a half
## laid flat to one upright, and speed from one at rest to a half at
## [constant FAST] and beyond. Not one shared curve, since the three fall
## different ways.
static func _thickness_option() -> SaCurveOption:
    var option := SaCurveOption.create_default()
    option.enabled = true
    option.use_same_curve = false
    option.set_sensor(_sensor(SaSensor.Id.TILT_ELEVATION, [Vector2(0.0, 0.5), Vector2(1.0, 1.0)]))
    option.set_sensor(_sensor(SaSensor.Id.SPEED, [Vector2(0.0, 1.0), Vector2(FAST, 0.5), Vector2(1.0, 0.5)]))
    return option


## Stretch's option and Thickness Lean's: the elevation along a falling line,
## nought upright and one laid flat, and the pressure the door's default puts
## in left out.
static func _stretch_option() -> SaCurveOption:
    var option := _option(true)
    option.use_same_curve = false
    option.set_sensor(_sensor(SaSensor.Id.TILT_ELEVATION, [Vector2(0.0, 1.0), Vector2(1.0, 0.0)]))
    return option


## Drift's option: speed from a half at rest to one at [constant FAST] and
## beyond, read at a strength of two, so the Drift row is what a stroke at rest
## carries and a fast stroke carries twice that.
static func _speed_drift_option() -> SaCurveOption:
    var option := _option(true)
    option.use_same_curve = false
    option.strength = 2.0
    option.strength_max = 2.0
    option.set_sensor(_sensor(SaSensor.Id.SPEED, [Vector2(0.0, 0.5), Vector2(FAST, 1.0), Vector2(1.0, 1.0)]))
    return option


## An active sensor of *id* along the curve through *points*.
static func _sensor(id: SaSensor.Id, points: Array[Vector2]) -> SaSensor:
    var sensor := SaSensor.create(id, true)
    sensor.curve = PackedVector2Array(points)
    return sensor
