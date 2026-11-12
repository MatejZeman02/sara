## The stamp brush's settings: every field the old resource had, plus the curve
## options and the migration that fills two of them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Sara's own, and each of the ranges below says why it is what it is.
##
## **Every field of `tools/brush_settings.gd` is here under the same name.** That
## is what makes a preset written by an older build still usable: the preset
## store copies by script variable name, so an old preset's `radius` lands on
## this `radius` and its `size_by_pressure` lands on this `size_by_pressure`.
##
## **The four old pressure fields stay and stop being read.** They are the input
## to `migrate()` and they are what a downgrade needs, so they are not deleted
## and not deprecated in a way that drops them from the file.
class_name SaStampBrushSettings
extends Resource

## The engine a preset written from these settings belongs to, which the preset
## store stamps into the file and a tool declares it takes.
const PRESET_ENGINE: StringName = &"stamp"

const SaLayerScript = preload("res://core/api/document/sa_layer.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## What `migrate()` brings a resource up to, and what a saved file then carries.
##
## A file written before the curve options existed has no `format_version` key
## at all, so it loads at the exported default of 1 and is migrated. A file
## written since carries the version it was written at and only the steps above
## it are run, which is what stops a curve the painter drew by hand in the editor
## from being overwritten by the exponent it was derived from.
##
## What each step does and why is written once, at the step in [method migrate],
## rather than a second time here: 3 switches the curve on for a preset that
## predates it being on by default, 4 and 6 promise the mask and its two options
## come back off, 5 is the pivot from the pattern, and 7 to 10 give the pickup's
## reach, the tip's lightness, the stage's rate and the pickup's sample the value
## the brush behaved as before each existed, 11 stamps the pressure table of
## the machine that loads the file, 12 is the gradient, which writes nothing
## because its empty default is what the brush did before it, 13 is the tip's
## mode, read off the lightness row the file holds, 14 the painting mode,
## build-up for a file with none, and 15 turns a dilution into a colour rate.
##
## A new step takes the next number and runs after every step below it, so the
## order here is the order a file climbs through.
const FORMAT_VERSION: int = 15

## How many even control points a pressure curve falls back to when three cannot
## draw it, see [SaPressureCurveFit]. Nine is where the error against the power
## the preset was built from falls below a hundredth.
const MIGRATED_CURVE_POINTS: int = 9

## The exponent an old preset's pressure readings were taken through, applied
## inside `SaTablet.normalize` ahead of either `GammaFloat`. `SaStrokeInfo.feed`
## applies none.
##
## The migrated curve carries the product of the two, so a preset painted
## through the sensor path answers what it answered through the old one. Losing
## this factor is not a subtle regression: at the default opacity gamma of 0.5
## it is the difference between an exponent of 1.2 and one of 0.5.
const TOOL_PRESSURE_GAMMA: float = 2.4

## Which format this resource was written in. Exported, so it travels in the
## `.tres`, and defaulting to 1 so a file that predates the key is migrated.
@export var format_version: int = 1

## The painter's pressure table this preset was made under, the correction of
## Preferences > Tablet as `SaPressureStamp.current()` writes it.
##
## **The stroke reads pressure through this rather than through the painter's
## own table**, so a preset handed from one painter to another answers the
## same brush output at the same pen pressure in both pairs of hands, whatever
## curve each set. The option curves below were drawn by someone pressing
## through this table, and read through another they would be a different
## brush.
##
## Stamped with the painter's table when the resource is made, so a brush built
## here carries this machine's curve, and by the version 11 step for a file
## written before the field existed. `SaMakerCurve` moves it on when the painter
## changes their curve and it was theirs. Saving writes what the brush carries,
## so a preset made here goes out with this painter's curve and one from
## another painter goes back out with its maker's. Empty only on an object
## nobody has stamped, which the stroke reads as the diagonal.
@export var maker_pressure_curve: PackedFloat32Array = PackedFloat32Array()

# --- Every field the old settings resource had, under the same name -----------

@export var radius: float = 0.02314814815  # 2x radius is diameter (% proportional to the canvas lower dimension)
@export var hardness: GammaFloat = GammaFloat.new(0.0, 1.0)
## The most opacity a stroke, or a dab under build-up, lays. A wash stroke at
## 1.074, which a script's jitter wrote through the door, laid alpha 1.064 on
## an empty layer, coverage above one that looks like any dark silhouette and
## that paint over it lifts. So the field holds zero to one whatever writes it,
## a preset file as much as the door, and the range lets the door's `brush`
## step refuse a number outside it rather than paint the clamp.
@export_range(0.0, 1.0) var opacity: float = 1.0:
    set(value):
        opacity = clampf(value, 0.0, 1.0)
@export var flow: GammaFloat = GammaFloat.new(1.0, 2.4)  # strength per dab/stamp
@export var spacing: float = 0.05  # % of the brush diameter

## The stabilizer in front of the interpolation: 0 off, 1 a weighted moving
## average, 2 a rope. `stabilizer_amount` is nought to one, how many
## samples or how long a rope. Both travel with a preset.
@export var stabilizer_mode: int = 0
@export var stabilizer_amount: float = 0.5

## The four the migration reads, and the two booleans the tool options bar still
## writes.
##
## The gammas are read by the migration alone. The booleans keep a setter each
## because the bar's "Size by Pressure" and "Opacity by Pressure" rows write them
## by name through `SaOptionSpec`, and nothing downstream reads them, so without
## the setter the two switches on the bar would do nothing at all.
##
## The setter flips the option and does not redraw its curve unless the option
## has none. Switching pressure off and on again therefore gives back the curve
## that was there, which is the painter's if they drew one, rather than the
## exponent it started from.
@export var size_by_pressure: bool = false:
    set(value):
        size_by_pressure = value
        _follow_toggle(size_option, value, size_pressure_gamma)
@export var size_pressure_gamma: GammaFloat = GammaFloat.new(0.0, 2.0)
@export var opacity_by_pressure: bool = true:
    set(value):
        opacity_by_pressure = value
        _follow_toggle(opacity_option, value, opacity_pressure_gamma)
@export var opacity_pressure_gamma: GammaFloat = GammaFloat.new(0.0, 0.5)

@export var color: Color = Color(1.0, 1.0, 1.0, 1.0)

## The other colour of the picker's pair, which Mix blends towards.
##
## Beside `color` and written by the same module through the same bus, because
## Mix is the one option whose answer depends on a colour the painter did not
## paint with.
##
## **Not exported, so no preset carries it**, unlike `color` above, which is.
## The pair belongs to the painter rather than to the brush, and a preset that
## mixed towards white on one machine should mix towards whatever the pair holds
## on the next, which is what a painter swapping the pair with X expects.
## `color` being exported is the older shape and not a precedent this follows: a
## preset carrying it is harmless because the bus overwrites it on the first
## pick, and a preset carrying the background would be the same harmless thing
## with one more line in every `.tres` for nobody. A plain member is stored by no
## `.tres` and is still read by `settings.get()` and written by the module, which
## is everything this field is asked for.
var background_color: Color = SaInHand.Pair.DEFAULT_BACKGROUND

## The pattern store the module made at registration, which `pattern_name`
## above is a name in.
##
## Here for the reason `background_color` is here: the module owns the store
## and a tool instance is built by the machine from a script, so the settings
## resource is the one object of the module's that reaches every brush, the
## main canvas's and the scratchpad's alike. Not exported, so no preset carries
## it and `copy_settings` walks past it: a preset names a paper, and which
## folders that name is looked up in is the module's business on every machine.
var pattern_store: SaPatternStore = null

## The paint exposure in stops, which is the foreground's own in `SaColors`
## rather than a number of the brush's: the bar's Exposure reads and writes it
## here because the bar reads a brush's settings. Not exported, so no preset
## carries it and a preset's `exposure`, a multiplier this class does not have,
## is read without it. The colour the dab carries already holds the stops, so
## nothing multiplies it again.
var paint_exposure: float:
    get:
        return SaPaintExposure.current()
    set(value):
        SaPaintExposure.move_to(value)

@export var blend_mode: StringName = SaLayerScript.BLEND_MODE.NORMAL

## The pattern the dab is textured with, by the name `SaPatternStore` lists it
## under, and empty for none. A name rather than a path so a painter moving a
## file between the two pattern folders breaks no preset, and an additive key
## so a preset written before it loads with none.
@export var pattern_name: String = ""

## The Texture page's four plain rows, beside `pattern_name` above and the
## `texture_option` below, which is the page's curve.
##
## `texture_scale` multiplies the tile: the pattern texture the dab samples is
## the pattern generated or resampled at its tile size times this, because the
## kernel takes the tile from the texture's own size and the push constant block
## has no float left for a scale. The offset is in document texels and shifts
## the grid the paper is laid on, so two brushes can share a grain and not its
## phase. `texture_invert` turns the paper over: nought becomes where the dab
## paints in full, which is what a scanned dark-on-light paper wants.
##
## **A number its reader clamps declares the clamp on its export**, the scale
## here and the five tone and cutoff numbers below, with the reader's own
## constants. A scenario's brush step reads the band off the property and
## refuses a number past it, because a number beyond the band paints what the
## band's end paints and the step would otherwise answer it as done.
@export_range(SaDabPattern.MIN_SCALE, SaDabPattern.MAX_SCALE) var texture_scale: float = 1.0
@export var texture_offset_x: int = 0
@export var texture_offset_y: int = 0
@export var texture_invert: bool = false

## The randomiser of the paper's place, a random offset per stroke and how far
## it may reach in x and y, which is what keeps a paper from repeating where the
## eye can see it.
##
## `texture_random_per_stroke` is the switch and the two amounts are how far the
## grid may jump, in the same document texels the fixed offset above is in. The
## draw is once per stroke rather than once per dab, because a phase that moved
## between dabs would be noise rather than paper, and it is added to the fixed
## offset rather than replacing it, so a painter who set a phase on purpose
## keeps it as the middle of the jump.
##
## Both amounts are here rather than one, because paper is not isotropic: a
## grain that runs one way wants jumping along it and not across it.
@export var texture_random_per_stroke: bool = false
@export var texture_random_offset_x: int = 0
@export var texture_random_offset_y: int = 0
## The Texture page's tone rows, baked into the pattern texture beside the
## scale rather than carried per dab, for the reason `SaPatternTone`'s header
## gives: `dab.gmacs`'s push constant was full before the scale needed room and
## is no less full now.
##
## `texture_brightness` is added to every texel, `texture_contrast` widens the
## grain about `texture_neutral` at a gain of `1 + contrast`, and the neutral
## point is the pattern value that stays put while the tooth grows. All three
## are additive keys, so a preset written before this loads with the pattern its
## author drew.
@export_range(SaPatternTone.MIN_BRIGHTNESS, SaPatternTone.MAX_BRIGHTNESS) var texture_brightness: float = 0.0
@export_range(SaPatternTone.MIN_CONTRAST, SaPatternTone.MAX_CONTRAST) var texture_contrast: float = 0.0
@export_range(SaPatternTone.MIN_NEUTRAL, SaPatternTone.MAX_NEUTRAL) var texture_neutral: float = SaPatternTone.DEFAULT_NEUTRAL
## Whether the contrast turns about the pattern's own mean instead of `texture_neutral`, as `SaPatternTone` says.
@export var texture_neutral_from_pattern: bool = true

## The Texture page's mode row: what the paper does to the coverage, multiply or
## subtract, as `SaDabPattern.Mode`. Multiply is what an additive key answers
## for a preset written without the row, which is the paper that preset's author
## drew with. The number reaches the kernel on the band of the strength rather
## than on a float of its own, which `SaDabPattern`'s header gives the reason
## for.
@export var texture_mode: int = SaDabPattern.Mode.MULTIPLY

## The Texture page's cutoff rows, baked into the same texture by the same
## dispatch as the tone above.
##
## The band is two pattern values and the policy says what becomes of a texel
## outside it: nothing, so the dab paints nothing there, or full, so the dab
## paints as if there were no paper. The shipped band is the whole range, which
## reads as no cutoff whatever the policy says, so a painter who picks a policy
## before touching a bound sees the paper they had. All three are additive keys,
## like the tone's.
@export_range(SaPatternTone.MIN_CUTOFF, SaPatternTone.MAX_CUTOFF) var texture_cutoff_left: float = SaPatternTone.MIN_CUTOFF
@export_range(SaPatternTone.MIN_CUTOFF, SaPatternTone.MAX_CUTOFF) var texture_cutoff_right: float = SaPatternTone.MAX_CUTOFF
@export var texture_cutoff_policy: int = SaPatternTone.Policy.OFF

## The tip, one of the block above's fields and set out here for its own note.
##
## This file's own rule is that every field of `tools/brush_settings.gd` is here
## under the same name, because the preset store copies by script variable name.
## Without this line the module would hold a settings resource with no tip on it
## and every dab would go back to being a hard circle, silently and with a green
## gate behind it.
@export var tip: Resource = SaBrushTipScript.new()

## The masking brush: a second tip, its own size and its own spacing, off by
## default.
##
## Beside `tip` rather than at the end of the file, because it is the second of
## exactly that field and a reader who finds one wants the other. The block is a
## `Resource` of its own, so the preset store carries it the way it carries the
## tip.
##
## The kernel reads it through the masking brush's block.
@export var masking: SaMaskingBrush = SaMaskingBrush.new()

## Sharpness, which is two things at once and one slider.
##
## It pulls the dab centre onto the pixel grid and it binarises the mask: at one
## the brush is a pen, every texel opaque or clear and every centre a whole
## pixel, and at zero it is the brush without the row. `sharpness_softness`
## widens the band of coverage the threshold leaves alone, so an edge keeps some
## of its ramp while the middle still goes solid.
##
## On the settings rather than on the tip, because a tip is a shape and this is
## how the shape is *placed and cut*: two brushes with the same tip can differ
## in it, and a tip carried between brushes should not bring it along. Zero by
## default, so nothing a painter already has changes.
@export var sharpness: float = 0.0
@export var sharpness_softness: float = 0.0

## Whether a pen, `sharpness` at one, enters the pixel mode, where a dab under
## `SaDabGeometry.PIXEL_MODE_DIAMETER` paints whole texels. Any other brush
## draws a thin line antialiased whatever this says.
##
## Off for Fill alone: its thin line lays cover summing to twice its radius down
## a column, so a dash 1, 1.5, 2 or 3 pixels tall can be asked of it, and
## `SaSmallDab` says how. A switch a preset carries and not a row, like the mode
## itself, and the preset's own about line says so.
@export var pixel_mode_when_small: bool = true

## Build-up or wash, which is the difference between a stroke that darkens
## where it crosses itself and one that does not.
##
## **Build-up** folds the stroke opacity into every dab and begins the stroke at
## one, so the buffer merges unscaled and overlapping dabs accumulate.
## **Wash** leaves the stroke opacity on the stroke, gives each dab the tip
## opacity only, and composites with the alpha-darken rule, so the whole stroke
## reaches exactly the opacity it was set to and no more.
enum PaintingMode { BUILD_UP = 0, WASH = 1 }

## Wash by default, because a lowered opacity is a promise of how much a stroke
## covers: a hard round at 0.36 in build-up covers far more than that in one
## stroke, where in wash it covers the 36 % it says.
##
## **A file written before format 14 is read by the old default.** Godot leaves
## a value equal to the declared default out of a file it writes, so a preset
## saved in build-up while build-up was the default carries no mode at all, and
## loads as whatever the new object held. The setter notes that a load wrote
## the mode, and the step below 14 in [method migrate] reads a file that wrote
## none as the build-up it painted in.
@export var painting_mode: PaintingMode = PaintingMode.WASH:
    set(value):
        painting_mode = value
        _wrote_painting_mode = true

## Whether anything wrote [member painting_mode] since construction, which a
## load does only when its file carries the key. False after construction, since
## an initial value calls no setter and `_init` puts it back.
var _wrote_painting_mode: bool = false

## The airbrush: paint deposited on a clock rather than on travel, so a
## pointer held still keeps painting.
##
## `airbrush_rate` is dabs per second, fifty by default, which is dense enough
## that a held pen fills rather than beads and slow enough to be visibly a rate.
## `airbrush_ignore_spacing` turns the distance gate off entirely, so time is the
## only clock and a fast drag deposits the same count as a slow one.
##
## **The frame clock quantises this.** The tick is once a frame, so at 60 frames
## a second the finest usable rate is 60 and anything above it deposits at most
## one dab a frame. The Rate row's tooltip says so rather than leaving a painter
## to find a slider that stops doing anything.
@export var airbrush_enabled: bool = false
@export var airbrush_rate: float = 50.0
@export var airbrush_ignore_spacing: bool = false

# --- The curve options --------------------------------------------------------
#
# One per modulated parameter, each with the range its own quantity has: the
# comment above every field is what that range means, and none of them is a
# preference. Every one of them is born with an empty sensor set rather than
# through `SaCurveOption.create_default()`, so an option nobody has touched
# writes no sensor entries into the `.tres` at all. Every one of them is also
# born reading its sensors, so the first one a painter ticks takes effect
# without a second switch.
#
# The heading does not count them, because the number moves and the rule above
# it does not.

## Multiplies the dab scale, so its ceiling is one: a size option makes a dab
## smaller than the setting says and never larger, and a painter who wants larger
## raises the setting. Off for a new brush, and the migration switches it on when
## the old `size_by_pressure` was on.
@export var size_option: SaCurveOption = _fresh_option(0.0, 1.0, false)

## The dab's alpha. Always on, in the sense that the widget draws no checkbox
## for it, and on at the old gamma for a new brush.
@export var opacity_option: SaCurveOption = _fresh_option(0.0, 1.0, true)

## How fast a dab reaches that alpha. Always on and a constant, because nothing
## in Sara has ever modulated flow by anything and giving it a sensor here would
## change how every existing brush paints.
@export var flow_option: SaCurveOption = _fresh_option(0.0, 1.0, true)

## Radians. The one option read through the rotation-like reducer.
@export var rotation_option: SaCurveOption = _fresh_option(0.0, 1.0, false)

## The tip's minor over major axis.
@export var ratio_option: SaCurveOption = _fresh_option(0.0, 1.0, false)

## The mask generator's fade, auto tips only. The one option whose floor is not
## zero, and the floor is the reason: a softness of nothing is a tip with no
## mask at all, which is not a soft brush but an absent one, so the range starts
## a tenth of the way up.
@export var softness_option: SaCurveOption = _fresh_option(0.1, 1.0, false)

## Multiplies the Hardness row, so its ceiling is one: the option makes the
## brush's edge softer than the row says and never harder, and a painter who
## wants harder raises the row.
##
## The second option on an edge. It is not a duplicate of `softness_option`
## above: that one scales the tip's own fade, this one scales the brush's
## Hardness before the fade pair is built from it, so the two are separate rows.
## Off for a new brush, and off is the Hardness row untouched, so no preset
## written before it moves.
##
## The floor is zero rather than softness's tenth. A softness of nothing is a
## tip with no mask, which is an absent brush, but a hardness of nothing is the
## kernel's soft dome, which is the lost edge this option is for.
@export var hardness_option: SaCurveOption = _fresh_option(0.0, 1.0, false)

## Where a dab's colour comes from before the three options below touch
## it.
##
## `plain` or `gradient`, which takes the colour off [member gradient] at the
## Mix option's value. Krita's `ColorSource/Type` also has `uniform random`,
## `total random` and `pattern`, and the importer tags a preset for each.
@export var color_source: SaColorDynamics.Source = SaColorDynamics.Source.PLAIN

## The preset's own ramp, which a gradient-map tip and a gradient colour source
## read, kept as `SaColorRamp.to_array` writes it, since a ramp is a
## `RefCounted` and not a sub-resource.
##
## Empty means the painter's colour to the background colour, read at the moment
## of asking by [method gradient_ramp], so a preset written before the field
## existed follows the pair as the brush always did and saving it again writes
## the same empty array. An edit on the Colour Dynamics page's Gradient row is
## what fills it.
@export var gradient: Array = []

## What a picture tip does to the dab, Krita's brush application. Mask lays the
## brush's colour through the picture's coverage, Lightness Map moves it by the
## picture's lightness as far as the tip's Lightness row says, and Gradient Map
## takes each texel's colour from [member gradient] at that lightness.
##
## **On the settings and not on the tip**, so `core/api/tip` gains nothing, and
## beside the gradient it reads. The first two are what a brush did before the
## field, told apart by the lightness row, which is what the step at 13 reads.
enum TipMode { MASK = 0, LIGHTNESS_MAP = 1, GRADIENT_MAP = 2 }
@export var tip_mode: TipMode = TipMode.MASK

## How far the dab turns the picked colour's hue, in half-turns.
##
## **The three colour options are offsets, and they carry the ordinary 0 to 1
## range all the same.** The reading is moved onto -1 to 1 where it is read, in
## `SaDynamics._offset_like` for the two below and inside `rotation_like` for
## this one, so the strength row here means what it means on every other page: a
## number from nothing to all of it. A range of -1 to 1 on the option itself
## would put the middle of the slider at no effect and the bottom at a full
## shift the other way, which is not a strength.
@export var hue_option: SaCurveOption = _fresh_option(0.0, 1.0, false)

## How far the dab moves the picked colour's chroma, scaled onto real chroma by
## [constant SaColorDynamics.MAX_CHROMA_SHIFT].
@export var saturation_option: SaCurveOption = _fresh_option(0.0, 1.0, false)

## How far the dab moves the picked colour's lightness, which is Oklab's own and
## needs no scale.
@export var value_option: SaCurveOption = _fresh_option(0.0, 1.0, false)

## How far the dab pulls the picked colour towards black.
##
## **The two below are amounts and the three above are offsets**, and the range
## on the option is the same 0 to 1 all the same. What differs is what the
## reading means once it is read: a darken of nought is the colour the painter
## picked and a darken of one is black, with nothing on the far side of nought
## to reach for. `SaDynamics._amount_like` is the reducer, and it is the plain
## reading times the strength with no move onto -1 to 1 in the middle.
@export var darken_option: SaCurveOption = _fresh_option(0.0, 1.0, false)

## How far the dab blends the picked colour towards the background colour.
##
## Krita's Mix runs the other way round, one being the painting colour and
## nought the background, because its slider is a crossfade between the pair. It
## is nought-neutral here so that every one of the five colour options is off at
## nought and a brush that has never met them paints what it always did, which
## the crossfade reading cannot give: a mix option switched on with no sensor
## under it would paint the background.
@export var mix_option: SaCurveOption = _fresh_option(0.0, 1.0, false)

## A multiplier applied after the tip's own spacing.
@export var spacing_option: SaCurveOption = _fresh_option(0.0, 1.0, false)

## Jitter measured in dab diameters rather than as a fraction of anything, which
## is why its ceiling is 5: a scatter of one means "up to one dab away", and a
## painter spraying wants several.
@export var scatter_option: SaCurveOption = _fresh_option(0.0, 5.0, false)

## Which way the scatter is allowed to move the dab.
##
## Beside the scatter curve option rather than inside it, because they change
## what the one number means rather than what it is: both on is a cloud around
## the path, one on is a stroke that wanders along its own direction or across
## it, and neither on is the option switched off by another name. `SaCurveOption`
## is a set of sensors and a curve and has no room for a pair of axes, so they
## sit here.
@export var scatter_axis_x: bool = true
@export var scatter_axis_y: bool = true

## Divides the airbrush interval, so it can only slow it.
@export var rate_option: SaCurveOption = _fresh_option(0.0, 1.0, false)

## How much of the Sharpness row above this dab gets.
##
## A multiplier on the row rather than a replacement for it, so its ceiling is
## one the way every size-like option's is: the row is the pen a painter dialled
## in and the option says how much of that pen the pressure has earned. Off for
## a new brush, and an option that is off multiplies by one, so a preset written
## before this existed sharpens exactly as it did.
##
## Beside the row rather than inside `SaBrushTip` for the reason the row itself
## gives: sharpness is how a shape is placed and cut, not what the shape is.
@export var sharpness_option: SaCurveOption = _fresh_option(0.0, 1.0, false)

## How much of the pattern the dab's coverage is given over to. `enabled` is
## the Texture page's checkbox and off is no pattern at all, the dab exactly as
## strength zero leaves it, so a preset written before this option existed
## loads with the paper off rather than at full tooth.
@export var texture_option: SaCurveOption = _fresh_option(0.0, 1.0, false)

## Whether the tip is turned over, per dab.
##
## Read as a threshold rather than as a quantity, `SaDynamics.MIRROR_THRESHOLD`,
## because a mirror has two states and nothing between them. The range is
## nought to one so the threshold sits in the middle of it, and off for a new
## brush, so a preset written before this option existed keeps whatever static
## mirror its tip carries and nothing else.
@export var mirror_option: SaCurveOption = _fresh_option(0.0, 1.0, false)

## The smudge stage: the stroke picks paint up from under the dab and drags
## it along, mixed into the colour it lays.
##
## **`smudge_pickup_option` is the stage's switch**, its `enabled` the page's
## checkbox, and off is the brush exactly as it was, so a preset written before
## the stage existed paints the same strokes. The other two are read only while
## it is on. Pickup is how much of the paint under the dab enters the carry per
## dab, the colour rate how much of the brush's own colour the dab lays beside
## the carry, nought when unticked as in Krita, and the smear length how much of
## the carry survives from one dab to the next, a carry that never fades when
## unticked. The colour rate alone starts ticked, at half, so ticking Smudge
## Pickup on a brush that never smudged paints and smudges at once.
@export var smudge_pickup_option: SaCurveOption = _smudge_option(0.3)
@export var smudge_color_rate_option: SaCurveOption = SaSmudgePage.option(0.5, true)
@export var smudge_length_option: SaCurveOption = _smudge_option(0.9)

## A file's Smudge Dilution, which [method migrate] turns over and drops.
@export var smudge_dilution_option: SaCurveOption = null

## How far out the smudge pickup reads, as a multiple of the dab's own
## radius.
##
## **A plain number rather than a curve option**, and the one smudge parameter
## without a stage of its own. What a dab carries and lays is a per-dab decision
## and the three curve options above answer it per dab. How far out the pickup
## looks is a property of the brush, so it is one number and a sensor on it is a
## unit of its own rather than this one.
##
## One is the dab itself, which is the reach the stage sampled before this field
## existed, so a preset written then smudges exactly as it did. The ceiling is
## [constant SaSmudgePage.MAX_RADIUS].
@export var smudge_radius: float = 1.0

## The three rates the smudge stage knows.
##
## **Smearing drags and dulling averages.** In smearing, what each dab picks up
## is mixed into the carry at the pickup rate, so the paint the stroke crossed
## travels along it for several dabs and the carry lags the canvas under it. In
## dulling the carry is set to the paint under the dab on every dab, so no dab
## drags anything: the stroke lays the mean of what stands where it is, which is
## a flat band across a hard edge rather than a smear carried off it. Krita has
## both under the one row, `SmudgeRateMode`, and a preset's own numbering is
## what the importer reads.
##
## **Blurring softens.** It picks up as dulling does, and each texel lays the
## paint around it under a Gaussian rather than the dab's one mean, so the same
## stroke along an edge leaves a ramp across it ([SaSmudgeBlur]). Krita has no
## third value, so an imported preset never lands here.
enum SmudgeMode { SMEARING = 0, DULLING = 1, BLURRING = 2 }

## Which of the three the stage is doing, and smearing is the neutral.
##
## **Smearing, which is the neutral a file carrying no row is read as**, so a
## preset that predates the row and a brush a painter saves without touching it
## both keep the strokes they had. It is a plain setting rather than a curve
## option for the reason [member smudge_radius] gives: how the stage treats what
## it picks up is a property of the brush and not a per-dab decision.
@export var smudge_mode: SmudgeMode = SmudgeMode.SMEARING

## Whether the pickup reads the composite or only the layer being painted.
##
## **On, which is the neutral a file carrying no row is read as**: a pickup that
## reads the composite is Krita's overlay, and the stroke a preset of that
## vintage was drawn with. Switched off, a smudge on a layer above a painting
## drags only what that layer holds, and a brush that crosses two layers reads
## the layer alone. A plain setting rather than a curve option for the reason
## [member smudge_radius] gives: what the pickup reads is a property of the
## brush and not a per-dab decision.
@export var smudge_sample_merged: bool = true

## Whether a smudge stroke moves the paint's height with its colour,
## so a smudge through thick paint drags the ridge along.
##
## **On, and it moves only a height that is there**: a layer with no height
## gains none from a smudge, so the switch changes nothing until the layer
## carries one, and a preset written before the row existed smudges a layer
## without height exactly as it did. A plain setting rather than a curve
## option for the reason [member smudge_radius] gives.
@export var smudge_move_height: bool = true

## Which axes the mirror option is allowed to turn over, Krita's two Mirror
## checkboxes.
##
## Beside the option rather than inside it, exactly as `scatter_axis_x` sits
## beside the scatter curve: they change what the one number means rather than
## what it is, and `SaCurveOption` is a set of sensors and a curve with no room
## for a pair of axes. Neither on is the option switched off by another name.
##
## **X on and Y off by default**, which is not the pair the scatter axes default
## to and is not an oversight: both axes flipped at once is a point mirror,
## which is a half turn rather than a reflection, so a painter who switches
## Mirror on and expects the tip to face the other way gets that and opts into
## the second axis. The tip's own `mirror_vertical` is still there for a
## standing vertical flip.
@export var mirror_axis_x: bool = true
@export var mirror_axis_y: bool = false


## A new object is a new brush, so the step below 14 is told its wash was
## written while the constructor migrates, and the note is cleared after it for
## a load to write.
func _init() -> void:
    _wrote_painting_mode = true
    migrate()
    _wrote_painting_mode = false


## Brings a resource written before the curve options existed up to date, and
## answers whether it did anything.
##
## Idempotent by the version stamp rather than by the shape of what it writes,
## because the second run has to leave a curve the painter drew alone. A fresh
## resource is migrated here at construction, which costs nothing and wants no
## second path: the defaults of the four old fields are opacity by pressure on
## at gamma 0.5 and size by pressure off, so migrating a new object produces
## exactly the options a new brush should have.
func migrate() -> bool:
    if format_version >= FORMAT_VERSION:
        return false
    if format_version < 2:
        _migrate_pressure_option(size_option, size_by_pressure, size_pressure_gamma)
        _migrate_pressure_option(opacity_option, opacity_by_pressure, opacity_pressure_gamma)
    if format_version < 3:
        # A file below version 3 was written while the options were born with
        # the curve off, so all nine options loaded with the curve off and
        # "Enable pen settings" unticked, and the sensors ticked on them did
        # nothing. The curve is switched on rather than the flags left as they
        # were, which costs a painter who switched one off on purpose, once, and
        # the stamp is what makes it once.
        for option: SaCurveOption in options().values():
            if option != null:
                option.use_curve = true
    if format_version < 4:
        # A file below 4 predates the masking block entirely, so there is
        # nothing in it to read and the step's whole job is to promise that the
        # mask a painter gets back is off. The null branch is not theoretical:
        # a `.tres` is text, and one written by hand or repaired by
        # `SaResourceFinder.repair_resource_paths` can name a sub-resource that is
        # no longer there.
        if masking == null:
            masking = SaMaskingBrush.new()
        masking.enabled = false
    if format_version < 6:
        # A file below 6 predates the mask's own two options, so the guarantee
        # is the same shape as the one above: whatever the block carried, the
        # options come back off and the mask paints at the row's size and the
        # whole strength.
        if masking != null:
            if masking.size_option != null:
                masking.size_option.enabled = false
            if masking.strength_option != null:
                masking.strength_option.enabled = false
    if format_version < 7:
        # A file below 7 predates the pickup's own reach, and the stage then
        # sampled the dab itself, so the neutral is what it comes back as. The
        # field's export default is the same number and the step says it anyway,
        # because a default is a promise to a new object and not to a file.
        smudge_radius = 1.0
    if format_version < 8:
        # A file below 8 predates the tip's lightness row, and the map is off for
        # it: a brush written before the row existed has no lightness of its own
        # to apply, and one whose picture does carry colour is switched on by the
        # importer rather than by a guess made here. The tip is a sub-resource and
        # can be missing, which a `.tres` written by hand or repaired by
        # `SaResourceFinder.repair_resource_paths` can produce for the reason the
        # step below version 4 gives.
        if tip != null:
            tip.lightness_strength = 0.0
    if format_version < 9:
        # A file below 9 predates the stage's rate, and the stage then dragged
        # what it picked up, so smearing is what it comes back as. The step says
        # it rather than trusting the export default for the reason above.
        smudge_mode = SmudgeMode.SMEARING
    if format_version < 10:
        # A file below 10 predates the pickup's sample, and the stage then read
        # the composite, so sampling merged is what it comes back as. The step
        # says it for the reason above, and the two states are not a repair: a
        # brush written before the row existed was a brush that read every
        # visible layer.
        smudge_sample_merged = true
    if format_version < 11:
        # A file below 11 predates the maker's table, and the stroke then read
        # the pressure through the table of whichever machine painted with it,
        # so that is the table it is stamped with: the machine loading it now.
        # Every preset already on disk feels as it did on the machine that holds
        # it, and from here on it keeps that feel when it travels. A fresh
        # object is stamped here as well, at construction, with the painter's.
        maker_pressure_curve = SaPressureStamp.current()
    if format_version < 12:
        # A file below 12 predates the gradient, and its empty default is the
        # painter's pair, which is all the brush knew of a ramp then. So the step
        # writes nothing, and is here so the stamp says the file was read.
        pass
    if format_version < 13:
        # A file below 13 predates the mode, and its tip then moved the colour
        # whenever the lightness row stood above nought, so that is a lightness
        # map and everything else a mask, which paints the texels it painted.
        var lightness: float = SaTyped.real(tip.get("lightness_strength")) if tip != null else 0.0
        tip_mode = TipMode.LIGHTNESS_MAP if lightness > 0.0 else TipMode.MASK
    if format_version < 14:
        # A file below 14 was written while build-up was the declared default,
        # so one in build-up carries no mode, and a load that wrote none is
        # that build-up. One in wash carries the key and keeps it. A resource
        # built by hand from an older script's fields is build-up as well,
        # since that script had no wash.
        if not _wrote_painting_mode:
            painting_mode = PaintingMode.BUILD_UP
    if format_version < 15:
        # Smudge Dilution turned over into the Colour Rate that lays the same
        # paint, a curve included, see SaSmudgePage.color_rate_of.
        if smudge_dilution_option != null:
            smudge_color_rate_option = SaSmudgePage.color_rate_of(smudge_dilution_option)
            smudge_dilution_option = null
    # Version 5, the pivot from the pattern, is the tone's own step.
    SaPatternTone.migrate_neutral(self, format_version)
    format_version = FORMAT_VERSION
    return true


## The ramp [member gradient] holds, or the painter's colour to the background
## colour while it holds none. A fresh object each call, so a reader may edit
## what it is handed and the preset stays as it was.
func gradient_ramp() -> SaColorRamp:
    return SaColorRamp.from_array(gradient, SaColorRamp.from_pair(color, background_color))


## The options by the name the editor and the evaluator know them under, in
## Krita's own order, with Sara's own at the end of it: texture, then hardness,
## sharpness and mirror.
##
## A dictionary rather than an accessor each because every consumer of this so
## far wants all of them: the editor builds a page per entry and a dump reports
## the lot.
func options() -> Dictionary:
    return {
        "size": size_option,
        "opacity": opacity_option,
        "flow": flow_option,
        "ratio": ratio_option,
        "softness": softness_option,
        "hardness": hardness_option,
        "rotation": rotation_option,
        "scatter": scatter_option,
        "spacing": spacing_option,
        "rate": rate_option,
        "hue": hue_option,
        "saturation": saturation_option,
        "value": value_option,
        "darken": darken_option,
        "mix": mix_option,
        "texture": texture_option,
        "sharpness": sharpness_option,
        "mirror": mirror_option,
    }


## Sets fields on the options by name, and switches sensors on, from a plain
## dictionary, which is what a scenario's `pen_settings` carries.
## [SaBrushPenSettings] owns the walk and says everything it reaches. *straight*
## keeps a bare tick on the straight line, which is the line the shipped
## recipes were written and recorded on.
func apply_pen_settings(spec: Dictionary, straight: bool = false) -> void:
    SaBrushPenSettings.apply(self, spec, straight)


## The curve `pow(x, gamma * 2.4)` in the fewest control points that draw it.
##
## Static and public because the test grades the migration against this shape
## and a scenario reports it, and because it is the one piece of the migration
## that is arithmetic rather than bookkeeping. Three points for both switches'
## shipped gammas, the ends and one bend, and `MIGRATED_CURVE_POINTS` even ones
## only for a gamma three cannot draw. [SaPressureCurveFit] owns the fit and
## says how close it comes.
static func pressure_curve(gamma: float) -> PackedVector2Array:
    return SaPressureCurveFit.of_power(gamma * TOOL_PRESSURE_GAMMA, MIGRATED_CURVE_POINTS)


## One option built from an old boolean and an old `GammaFloat`.
##
## The boolean becomes `enabled`, and that is the whole of the off switch.
## `use_curve` is not written here at all: the option arrives from
## `_fresh_option` with the curve on, and an option that is off is never read,
## because `SaDynamics` filters on `enabled` before it reads anything and
## `begin_stroke()` is what would have given it a sensor. The guard against that
## sits in `SaCurveOption.ensure_one_active()`, which leaves an untouched
## option's empty sensor set empty, rather than in a `use_curve = was_on` here.
func _migrate_pressure_option(option: SaCurveOption, was_on: bool, gamma: GammaFloat) -> void:
    if option == null:
        return
    option.enabled = was_on
    option.use_same_curve = true
    option.strength = 1.0
    if not was_on:
        # An old preset with the boolean off never had a sensor set, and the one
        # standing here is the constructor's, put there before `copy_settings`
        # wrote the old fields over it. The curve stays on, so a leftover would
        # come alive the moment a painter ticked the option.
        option.sensors.clear()
        return
    option.common_curve = pressure_curve(gamma.gamma() if gamma != null else 1.0)
    option.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))


## One of the two bar switches reaching the option it names.
##
## Null-checked because a member initializer runs in declaration order and both
## booleans are declared above the options they point at, so the very first write
## of each happens while the option is still null.
func _follow_toggle(option: SaCurveOption, on: bool, gamma: GammaFloat) -> void:
    if option == null:
        return
    option.enabled = on
    if not on:
        return
    if option.sensors.is_empty():
        option.common_curve = pressure_curve(gamma.gamma() if gamma != null else 1.0)
        option.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))


## An option with a range, no sensors and a curve that is read.
##
## **`use_curve` is on for all nine**. It was off for every option the migration
## did not build, so a painter who ticked a sensor got nothing until they found
## "Enable pen settings". On costs nothing while the sensor set is empty: the
## option has no sensor to read, so it answers its `strength` exactly as it did
## with the curve off, and `SaCurveOption.ensure_one_active()` invents none.
##
## *on* is `enabled`, which is the real off switch and stays as it was.
## One of the smudge stage's three options: off, nought to one, and at
## *strength* for the day a painter switches the stage on.
static func _smudge_option(strength: float) -> SaCurveOption:
    var option := _fresh_option(0.0, 1.0, false)
    option.strength = strength
    return option


static func _fresh_option(minimum: float, maximum: float, on: bool) -> SaCurveOption:
    var option := SaCurveOption.new()
    option.enabled = on
    option.use_curve = true
    option.strength = 1.0
    option.strength_min = minimum
    option.strength_max = maximum
    return option
