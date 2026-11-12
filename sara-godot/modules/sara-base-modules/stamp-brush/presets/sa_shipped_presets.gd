## The brush presets the stamp brush module ships, and which of them a settings
## resource can carry.
##
## **Here rather than in `core/`.** Every path a recipe names, `radius`,
## `hardness:value`, `stabilizer_mode`, `smudge_pickup_option:strength`, is a
## field of this module's settings resource, so core would carry a table it
## could not read without the module that owns the fields. The module registers
## the script under the `shipped_presets` role and
## [method SaPresetStore.install_shipped] is handed it, so a build with no stamp
## brush installs nothing and says nothing.
##
## Written into a store that has none rather than shipped as `.tres` files under
## `res://`, which is `SaPresetStore.install_shipped`'s half. A hand-written
## `.tres` names the module's script and its property set by hand, and a preset
## cannot load without the module that wrote it: generating them from the live
## settings resource means the presets that land are valid for the build that
## wrote them, whatever fields the module has.
##
## A class of its own rather than a part of `sa_preset_store.gd`, because it
## holds what the store does not own: the recipes, and the rule that a recipe
## the template cannot carry is not written.
class_name SaShippedPresets
extends RefCounted

## The second bundle, the brushes on Sara's own drawn tips, kept in a table of
## its own and handed out with this one by [method entries].
const SaDrawnTipPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_drawn_tip_presets.gd")

## The third bundle, the brushes made of the basic set by options painters keep setting,
## handed out with the other two by [method entries].
const SaHabitPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_habit_presets.gd")

## The fourth table, the bundled presets shipped as they were saved,
## handed out with the other three by [method entries].
const SaAuthorPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_author_presets.gd")

## The role this script is registered under. Named here rather than written out
## in the module and in the capture report, so what a dump says about where the
## recipes came from cannot drift from where the module put them.
const ROLE: StringName = &"shipped_presets"

## The two bundles the recipes of this module are filed under, written onto
## each preset it installs as `bundle` metadata, the basic brushes apart from
## the filters and the advanced paint brushes. Sara Basic holds
## the rounds and the erasers a painter starts with, named on their recipes
## below, so moving one is its `bundle` line. Sara Advanced Paint holds every
## other recipe of this table and the three tables handed out with it. The third
## bundle, Sara Filters, is the filter brush's and the liquify shelf's.
##
## **A name on the recipe rather than one for the table**, because the first-run
## install is per bundle: a directory has one marker per name, and this name is
## what the marker is filed under.
const BASIC: String = "Sara Basic"
const ADVANCED: String = "Sara Advanced Paint"

## The names this table's recipes shipped under before, the newest first,
## handed to the store as each entry's `formerly`, so a profile's record of
## what Sara Essentials, and Sara basic before it, offered and wrote becomes the
## new bundles': no preset the painter deleted comes back, and each preset
## filed under an old name is moved to its new one, `SaPresetBundleMap`.
const FORMERLY: Array[String] = ["Sara Essentials", "Sara basic"]

## The version of both bundles, raised when their recipes change in a way a
## painter would want to tell apart.
const VERSION: String = "1.0"

## Who made the bundles.
const AUTHOR: String = "Matěj Zeman"

## Each bundle's own sentence, what it holds as a whole.
const BASIC_ABOUT: String = "The few round brushes and erasers a painter starts with, hard and soft."
const ADVANCED_ABOUT: String = "Every other paint brush Sara ships: drawn tips, noise, pencils, markers and smudges."

## The fields each bundle's entries carry beside `bundle`, under the keys
## `SaPresetStore.install_shipped` writes them as metadata. The noise module
## spells Sara Advanced Paint's again, since it sees the door only, and a
## suite holds the two the same.
const FIELDS: Dictionary = {
    BASIC: {"bundle_version": VERSION, "bundle_author": AUTHOR, "bundle_about": BASIC_ABOUT},
    ADVANCED: {"bundle_version": VERSION, "bundle_author": AUTHOR, "bundle_about": ADVANCED_ABOUT},
}

## The licence each bundle's recipes ship under, named once beside the bundle's
## own name rather than repeated on every entry. GPL-3.0-or-later, because the
## recipes are source inside a GPLv3 module and are distributed as part of it.
##
## A recipe of the drawn table carries the pictures' licence as `licence` of
## its own instead, since one bundle now holds recipes under two licences, and
## the store takes an entry's own before the bundle's.
const LICENCES: Dictionary = {BASIC: "GPL-3.0-or-later", ADVANCED: "GPL-3.0-or-later"}


## The rounds and erasers of Sara Basic, by name, in the table's order. Read off
## the recipes rather than listed twice.
static func basic_names() -> Array[String]:
    var out: Array[String] = []
    for entry: Dictionary in ENTRIES:
        if String(entry.get("bundle", "")) == BASIC:
            out.append(String(entry["name"]))
    return out


## The size curves of Airbrush, Pencil, Wash and Oil Smudge, each taking the
## share its name gives off the ring below full pressure and none at full.
##
## **A curve rather than a strength below one**. `size_like` multiplies the
## pressure reading by the option's strength, Krita's own rule, so a strength of
## 0.3 would make Oil Smudge's dab a quarter of its ring at pressure 0.8 and lay
## four times the dabs its size promises. The recipes mean "pressure takes this
## share off the size", which is a curve from one less the share at no pressure
## to one at full, with the strength left at one. The engine and the importer
## keep Krita's rule, so a preset brought in from Krita sizes as it did there.
const SIZE_OFF_30: Array[Vector2] = [Vector2(0.0, 0.7), Vector2(1.0, 1.0)]
const SIZE_OFF_50: Array[Vector2] = [Vector2(0.0, 0.5), Vector2(1.0, 1.0)]
## Wash's. Its floor is 0.4 of the ring rather than 0.6, so a light touch lays a
## narrow glaze and a full press the whole ring the bar names.
const SIZE_OFF_60: Array[Vector2] = [Vector2(0.0, 0.4), Vector2(1.0, 1.0)]

## The recipes: the first three, then the five below, then the basic twenty-one.
##
## **A recipe that names no `painting_mode` paints in wash**, the settings' own
## default, so a lowered opacity covers what it says. Airbrush and Chisel Marker
## name build-up and say why beside them. Grainy Pencil, Pencil and Wash name
## wash and keep it written, because a template of the old script, which has no
## such field, is what passes them over.
##
## `radius` is a fraction of the canvas's smaller dimension, so the sizes the
## answer gives in pixels are those pixels on the 1080 of a default document.
## Hardness and flow are `GammaFloat`, hence the indexed paths.
##
## **The last five are one engine shipped as several presets of itself**, each
## built on one feature: the marker on the depletion sensor, the pencil on the
## lit grain, the round on the randomised hardness, the pen on the sharpness
## option and the flat brush on the fan. A curve option is not a property path,
## so those five carry `pen_settings`, the dictionary the settings resource's
## own `apply_pen_settings` reads, asked for by method name so this file names
## no script beside it. `about` is the sentence saying what the preset is for.
const ENTRIES: Array[Dictionary] = [
    {
        "name": "Sketch",
        "tags": ["lines"],
        "bundle": BASIC,
        "about": "A hard thin line with no smoothing, paler under a light press, for drawing the picture before painting it.",
        "settings": {"radius": 0.00463, "hardness:value": 1.0, "opacity": 1.0, "flow:value": 1.0, "stabilizer_mode": 0},
    },
    {
        "name": "Paint",
        "tags": ["paint"],
        "bundle": BASIC,
        "about": "A soft round at half flow, for laying in colour.",
        # No stabiliser, because on a tablet the Average held its paint 60 ms
        # behind the pen.
        "settings":
        {
            "radius": 0.023148,
            "hardness:value": 0.0,
            "opacity": 1.0,
            "flow:value": 0.5,
            "stabilizer_mode": 0,
        },
    },
    {
        "name": "Fill",
        "tags": ["paint"],
        "bundle": BASIC,
        "about":
        (
            "A hard round more than a third of the canvas's short side across, see-through under a light "
            + "press and solid at a full one, for covering ground fast."
        ),
        "settings":
        {
            "radius": 0.185185,
            "hardness:value": 1.0,
            "opacity": 1.0,
            "flow:value": 1.0,
            "stabilizer_mode": 0,
            "pixel_mode_when_small": false,
        },
    },
    # A thousand pixels of ink at full pressure, so a stroke across a default
    # document is spent by its far end, with the depletion on both curves.
    {
        "name": "Dry Marker",
        "tags": ["lines"],
        "bundle": ADVANCED,
        "about": "A felt marker that runs dry along the stroke and is full again at the next press.",
        "settings": {"radius": 0.013889, "hardness:value": 0.85, "opacity": 1.0, "flow:value": 1.0, "spacing": 0.1},
        "pen_settings":
        {
            "opacity": {"sensors": [{"id": "depletion", "length": 1000}]},
            "flow": {"enabled": true, "sensors": [{"id": "depletion", "length": 1000}]},
        },
    },
    # Sixteen pixels across at full pressure, which is a few of the lit grain's
    # twelve texel cells, so the tooth shows inside the line rather than beside
    # it. Wash rather than build-up, because overlapping dabs that build up fill
    # every hollow of the grain by the tenth dab and the stroke is a solid black
    # line. A jump per stroke, so two strokes side by side do not lay the same
    # grain. The layer holds the colour picked to the level, and the grain
    # leaves the ground showing between its peaks, so on the atlas's cream a
    # grey of 48 levels reads as a warm (133, 127, 116), the cream at the same
    # share in each channel. That is the pencil and not a tint, and the line
    # says it.
    {
        "name": "Grainy Pencil",
        "tags": ["lines"],
        "bundle": ADVANCED,
        "about":
        (
            "A pencil whose line catches the lit grain of the paper, thinner under a light hand. "
            + "The paper shows between the grains, so the line reads lighter than the colour picked "
            + "and takes the tint of the ground."
        ),
        "settings":
        {
            "radius": 0.007407,
            "hardness:value": 1.0,
            "opacity": 1.0,
            "flow:value": 0.9,
            "spacing": 0.05,
            "painting_mode": 1,
            "pattern_name": "Lit Grain",
            "texture_scale": 1.0,
            "texture_random_per_stroke": true,
            "texture_random_offset_x": 256,
            "texture_random_offset_y": 256,
        },
        "pen_settings":
        {
            "texture": {"enabled": true, "strength": 1.0},
            "size": {"enabled": true, "sensors": ["pressure"]},
        },
    },
    # The Hardness row at one and the option at full strength on the random sensor,
    # which is the hardness option's own measured case of hard, soft and lost in
    # one stroke.
    {
        "name": "Lost Edges",
        "tags": ["paint"],
        "bundle": ADVANCED,
        "about": "A round whose hardness is drawn afresh for every dab, so one stroke has hard, soft and lost edges.",
        "settings": {"radius": 0.027778, "hardness:value": 1.0, "opacity": 1.0, "flow:value": 0.7, "spacing": 0.12},
        "pen_settings": {"hardness": {"enabled": true, "strength": 1.0, "sensors": ["fuzzy_per_dab"]}},
    },
    # Opacity off, because ink is opaque, and the pressure on the size and on
    # the sharpness, so a light touch is a thin line that still keeps its edge.
    {
        "name": "Inked Pen",
        "tags": ["lines"],
        "bundle": ADVANCED,
        "about": "A pen with a cut edge, every pixel either opaque or clear, swelling with pressure.",
        "settings":
        {
            "radius": 0.003704,
            "hardness:value": 0.35,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.05,
            "sharpness": 1.0,
            "sharpness_softness": 0.0,
            "stabilizer_mode": 1,
            "stabilizer_amount": 0.3,
        },
        "pen_settings":
        {
            "size": {"enabled": true, "sensors": ["pressure"]},
            "opacity": {"enabled": false},
            "sharpness": {"enabled": true, "sensors": ["pressure"]},
        },
    },
    # A rectangle a fifth as thick as it is wide, turned by the drawing angle
    # and a quarter turn beyond it, so the broad side crosses the stroke the way
    # a flat brush is dragged, with the fan so a corner is swept rather than
    # broken. Ten degrees is the step the fan's scenario closed the corner at.
    # Without the quarter turn the stroke is a thin bar with a half disc
    # standing off each corner, which is the fan sweeping a blade laid along the
    # path.
    #
    # Full flow, because a blade a pixel or two thick covers a texel wholly with
    # two or three of its dabs and no more. Below full flow a dash never covers
    # wholly, and under radius 1.5, where the pixel mode lays exactly one dab a
    # texel, it covers the flow and no more.
    {
        "name": "Flat Brush",
        "tags": ["paint"],
        "bundle": ADVANCED,
        "about": "A flat brush that follows the stroke's direction and sweeps round a corner instead of breaking it.",
        "settings":
        {
            "radius": 0.02963,
            "hardness:value": 0.9,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.05,
            "tip:shape": 1,
            "tip:ratio": 0.2,
        },
        "pen_settings":
        {
            "rotation":
            {
                "enabled": true,
                "strength": 1.0,
                "sensors": [{"id": "drawing_angle", "angle_offset": 90.0, "fan_corners": true, "fan_step": 10.0}],
            },
        },
    },
    # --- The basic twenty-one, which is the twelve below plus the masked one
    # at the end.
    #
    # **A recipe is read against the settings resource** and not taken as
    # written, because two kinds of name in a recipe mean something else there.
    #
    # `painting_mode` is written here as the field's enum has it, `PaintingMode
    # { BUILD_UP = 0, WASH = 1 }`, and a recipe handed in from outside may well
    # count from one instead. The pencil is the one recipe whose number moved
    # after a capture, and the comment on it says why.
    #
    # `scatter_axis_x` and `scatter_axis_y` are listed with the pen settings for
    # the spatter and are not fields of any curve option, so a pen settings entry
    # naming them is dropped in silence by `apply_pen_settings`. They are
    # properties of the settings resource and travel as settings paths, which is
    # what makes a jitter that is round rather than along the stroke. The other
    # four names in that column, `angle_offset`, `fan_corners` and `fan_step` on
    # the two flat brushes and behind the smudge's rotation, are fields of a
    # sensor and sit inside the sensor's own dictionary, the way `Flat Brush`
    # above already writes them.
    #
    # A radius is the fraction of the default document the field means, so 0.01
    # is about eleven pixels on a 1080 canvas.
    #
    # Build-up, chosen for what it is. An airbrush lays paint on a clock while
    # the pen rests, and the paint under a resting nozzle keeps thickening,
    # where wash would stop it at the coverage of its first pass. The values
    # match the bundled painter's saved Airbrush, in a mixing blend mode and with the size on
    # the pen switched off, so the pressure moves only the opacity.
    {
        "name": "Airbrush",
        "tags": ["soft"],
        "bundle": BASIC,
        "about":
        (
            "A soft spray that keeps flowing while the pen rests, thicker under pressure. It paints in a "
            + "mixing blend mode where a mixing module is installed, so over another colour it "
            + "mixes as paint does, blue over yellow turning green."
        ),
        "settings":
        {
            "radius": 0.05113898168925979,
            "hardness:value": 0.0,
            "opacity": 1.0,
            "flow:value": 0.12,
            "spacing": 0.05,
            "airbrush_enabled": true,
            "airbrush_rate": 40.0,
            "blend_mode": &"pigment_mix",
            "painting_mode": 0,
            "smudge_color_rate_option:enabled": false,
            "smudge_color_rate_option:strength": SaDrawnTipPresetsScript.AUTHORS_COLOUR_RATE,
        },
        "pen_settings":
        {
            "opacity": {"sensors": ["pressure"], "common_curve": SaDrawnTipPresetsScript.OPACITY_NINE},
            "size": {"enabled": false, "sensors": ["pressure"], "strength": 0.5},
        },
    },
    # **Wash rather than build-up.** Dabs at a spacing of eight percent overlap
    # ten times over, so in build-up every hollow of the paper fills and the
    # tooth the recipe asks for is gone by the far end of the stroke. In wash
    # each dab stands on its own and the grain survives, and the line darkens
    # under the hand through the opacity curve below instead.
    {
        "name": "Pencil",
        "tags": ["lines"],
        "bundle": ADVANCED,
        "about": "A pencil with a little tooth and a line that darkens under pressure, the everyday drawing tool.",
        "settings":
        {
            "radius": 0.0037,
            "hardness:value": 0.75,
            "opacity": 1.0,
            "flow:value": 0.85,
            "spacing": 0.08,
            "painting_mode": 1,
            "pattern_name": "Paper Grain",
            "texture_scale": 0.6,
        },
        "pen_settings":
        {
            "texture": {"enabled": true, "strength": 0.4},
            "opacity": {"enabled": true, "sensors": ["pressure"]},
            "size": {"enabled": true, "sensors": ["pressure"], "common_curve": SIZE_OFF_30},
        },
    },
    # A rectangle over twice as wide as it is deep, turned a quarter beyond the
    # drawing angle the way Flat Brush is, so the broad side crosses the stroke
    # rather than running along it. Subtract rather than multiply on the paper,
    # so the grain bites into the tone instead of only modulating it.
    {
        "name": "Charcoal",
        "tags": ["lines"],
        "bundle": ADVANCED,
        "about": "A soft flat stick that catches the paper and turns with the stroke, for tone rather than line.",
        "settings":
        {
            "radius": 0.0185,
            "hardness:value": 0.3,
            "opacity": 1.0,
            "flow:value": 0.6,
            "spacing": 0.06,
            "tip:shape": 1,
            "tip:ratio": 0.55,
            "pattern_name": "Paper Grain",
            "texture_scale": 1.2,
            "texture_mode": 1,
        },
        "pen_settings":
        {
            "rotation":
            {
                "enabled": true,
                "strength": 1.0,
                "sensors": [{"id": "drawing_angle", "angle_offset": 90.0, "fan_corners": true}],
            },
            "texture": {"enabled": true, "strength": 0.8},
            "opacity": {"enabled": true, "sensors": ["pressure"]},
        },
    },
    # No dynamics at all, which is what makes it a chisel: the tip's own angle
    # is fixed and the stroke's direction is left to say which way is thin.
    #
    # **The angle is in radians**, as `SaBrushTip.angle` reads it, so a quarter
    # of PI is 45 degrees. A 45.0 here would be read as 45 radians.
    #
    # **Build-up, chosen for what it is.** A marker's ink darkens where its
    # stroke crosses itself, which is the mark a painter reaches for one for,
    # and wash would lay the crossing at the colour of the stroke. It is also
    # the one field of the twelve the old settings resource lacks and every
    # other path here it has: without it a legacy store would carry a fourth
    # preset, and the dozen suites that install from that script count on the
    # first three. The five above are arranged the same way.
    {
        "name": "Chisel Marker",
        "tags": ["lines"],
        "bundle": ADVANCED,
        "about": "A chisel tip held at one angle, so a stroke is thick one way and thin the other, like a calligraphy marker.",
        "settings":
        {
            "radius": 0.0167,
            "hardness:value": 0.95,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.04,
            "painting_mode": 0,
            "tip:shape": 1,
            "tip:ratio": 0.3,
            "tip:angle": PI / 4.0,
        },
    },
    # Flow at six percent, so the stroke is a thin layer rather than a colour,
    # and wash for the same reason as the pencil: layer on layer is the whole
    # brush, and build-up would lay it in one pass.
    {
        "name": "Wash",
        "tags": ["paint"],
        "bundle": ADVANCED,
        "about": "A wide soft brush with very little flow, so colour builds in thin layers a stroke at a time.",
        "settings":
        {
            "radius": 0.06,
            "hardness:value": 0.0,
            "opacity": 0.7,
            "flow:value": 0.06,
            "spacing": 0.08,
            "painting_mode": 1,
            "pattern_name": "Canvas Weave",
            "texture_scale": 1.0,
        },
        "pen_settings":
        {
            "texture": {"enabled": true, "strength": 0.3},
            "size": {"enabled": true, "sensors": ["pressure"], "common_curve": SIZE_OFF_60},
        },
    },
    {
        "name": "Canvas Brush",
        "tags": ["paint"],
        "bundle": ADVANCED,
        "about": "A flat bristle brush over canvas weave, the weave showing through where the paint is thin.",
        "settings":
        {
            "radius": 0.03,
            "hardness:value": 0.85,
            "opacity": 1.0,
            "flow:value": 0.7,
            "spacing": 0.05,
            "tip:shape": 1,
            "tip:ratio": 0.25,
            "pattern_name": "Canvas Weave",
            "texture_scale": 0.8,
        },
        "pen_settings":
        {
            "rotation":
            {
                "enabled": true,
                "strength": 1.0,
                "sensors": [{"id": "drawing_angle", "angle_offset": 90.0, "fan_corners": true, "fan_step": 10.0}],
            },
            "texture": {"enabled": true, "strength": 0.6},
            "flow": {"enabled": true, "sensors": ["pressure"]},
        },
    },
    # The three smudge options are the stage's own, and the pickup is what makes
    # a brush that carries paint rather than laying it. The colour rate is half,
    # so the dab lays half its own colour beside what it drags, and the length
    # below full lets the drag fade. Both are on, since a length left off never
    # fades and a colour rate left off lays none of the brush's colour.
    {
        "name": "Oil Smudge",
        "tags": ["blend"],
        "bundle": ADVANCED,
        "about":
        (
            "A flat brush that lays a thin veil of the colour picked and drags what is under it along, wet "
            + "paint into wet paint."
        ),
        # The Oil Smudge shipped before the dilution became Colour Rate, with the
        # dilution and the length off, as `SaPresetLedger.fingerprint` reads it.
        # A profile holding it untouched gets this recipe at the next start.
        "shipped_before": ["638091b001dfe07e4c10265dccc08f944f0394a84820dab7082767cd7b9a1078"],
        "settings":
        {
            "radius": 0.028,
            "hardness:value": 0.6,
            "opacity": 1.0,
            "flow:value": 0.9,
            "spacing": 0.06,
            "tip:shape": 1,
            "tip:ratio": 0.45,
            "smudge_pickup_option:enabled": true,
            "smudge_pickup_option:strength": 0.6,
            "smudge_color_rate_option:enabled": true,
            "smudge_color_rate_option:strength": 0.5,
            "smudge_length_option:enabled": true,
            "smudge_length_option:strength": 0.75,
        },
        "pen_settings":
        {
            "rotation":
            {
                "enabled": true,
                "strength": 1.0,
                "sensors": [{"id": "drawing_angle", "angle_offset": 90.0, "fan_corners": true}],
            },
            "size": {"enabled": true, "sensors": ["pressure"], "common_curve": SIZE_OFF_30},
        },
    },
    # Pickup at full with the colour rate at nought, which is the recipe for a
    # brush that carries the colour under it perfectly and puts none of its own
    # down. The opacity curve is the only thing the hand does to it. It blurs
    # rather than smears, so one stroke along an edge leaves a gradient across
    # it with no step at either end, as a blur under a soft brush does, where a
    # smear or a dull lays a band of one colour. The colour rate is ticked at
    # nought, which lays the carry in full as an unticked one does and shows the
    # painter the number, and the length fades the carry a tenth a dab once it
    # leaves the paint. Sample merged is off, so the pickup reads the layer
    # being painted and never lays the layers below onto a transparent part of
    # it, as Photoshop's mixer brush does.
    {
        "name": "Blender",
        "tags": ["blend"],
        "bundle": ADVANCED,
        "about": "A soft round that lays no colour of its own and blends what is there into a gradient.",
        "settings":
        {
            "radius": 0.037,
            "hardness:value": 0.1,
            "opacity": 1.0,
            "flow:value": 0.5,
            "spacing": 0.05,
            "smudge_mode": 2,
            "smudge_pickup_option:enabled": true,
            "smudge_pickup_option:strength": 1.0,
            "smudge_color_rate_option:enabled": true,
            "smudge_color_rate_option:strength": 0.0,
            "smudge_length_option:enabled": true,
            "smudge_length_option:strength": 0.9,
            "smudge_sample_merged": false,
        },
        "pen_settings": {"opacity": {"enabled": true, "sensors": ["pressure"]}},
    },
    # `erase` is the layer blend mode rather than a tool of its own, which is
    # what the eraser tool itself sets on a brush (state_eraser.gd). A preset
    # that carries it is a brush that takes paint away.
    {
        "name": "Eraser",
        "tags": ["eraser"],
        "bundle": BASIC,
        "about":
        (
            "A hard round that takes paint away, thinner under a light hand. It paints in the Erase mode, so "
            + "the colour picked plays no part."
        ),
        "settings":
        {
            "radius": 0.028,
            "hardness:value": 0.9,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.06,
            "blend_mode": &"erase",
        },
        "pen_settings": {"size": {"enabled": true, "sensors": ["pressure"]}},
    },
    # Paint's hardness and flow, and no spacing of its own, so it stamps at the
    # default Paint stamps at and carves the ramp Paint lays. Each erase dab
    # keeps `1 - s` of the alpha under it and each build-up dab keeps `1 - s` of
    # the clear, so the same dabs take away exactly what they would lay. A
    # spacing of its own, finer than Paint's, would stamp several dabs to
    # Paint's one, and several bites at half flow take the paint away far out
    # towards the rim, which the suite
    # `test_soft_eraser_takes_paint_away_with_the_fall_off_paint_lays_it_with.gd`
    # measures.
    {
        "name": "Soft Eraser",
        "tags": ["eraser"],
        "bundle": BASIC,
        "about":
        (
            "A soft eraser that fades paint out rather than cutting it. It paints in the Erase mode, so the "
            + "colour picked plays no part."
        ),
        "settings":
        {
            "radius": 0.046,
            "hardness:value": 0.0,
            "opacity": 1.0,
            "flow:value": 0.5,
            "blend_mode": &"erase",
        },
        "pen_settings": {"opacity": {"enabled": true, "sensors": ["pressure"]}},
    },
    # The dot screen read as a height field: the dab paints only where the
    # screen sits below the texture's strength, and the strength rides the
    # pressure, so every press lays the same field of dots and a heavier one
    # lays them darker. A band cut on the screen with the strength on the
    # pressure did the opposite of a halftone, a solid wash at a light touch and
    # thin rings at a full one, because a weak texture is no texture.
    {
        "name": "Halftone",
        "tags": ["texture"],
        "bundle": ADVANCED,
        "about":
        "A field of dots from a printed dot screen, faint at a light press and solid at a full one, for a halftone texture.",
        "settings":
        {
            "radius": 0.037,
            "hardness:value": 1.0,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.04,
            "pattern_name": "Dot Screen",
            "texture_scale": 0.5,
            "texture_mode": SaDabPattern.Mode.HEIGHT,
        },
        "pen_settings": {"texture": {"enabled": true, "strength": 0.8, "sensors": ["pressure"]}},
    },
    # Spacing at sixty percent of the dab, so the stroke is separate dots rather
    # than a line, and the random sensor on all three curves so each dot has its
    # own size and its own darkness. The jitter axes are on in both directions,
    # which is a scatter rather than a wobble. The saved Spatter this recipe
    # matches field by field adds the pressure to the darkness and a random hue
    # to each dot, in a mixing blend mode.
    {
        "name": "Spatter",
        "tags": ["scatter"],
        "bundle": ADVANCED,
        "about":
        (
            "Round dots thrown along the stroke, each a random size, lightness and tint, for texture and "
            + "spray. It paints in a mixing blend mode where a mixing module is installed, so "
            + "over another colour it mixes as paint does, blue over yellow turning green."
        ),
        "settings":
        {
            "radius": 0.022326347745073562,
            "hardness:value": 1.0,
            "opacity": 1.0,
            "flow:value": 1.0,
            "spacing": 0.6,
            "scatter_axis_x": true,
            "scatter_axis_y": true,
            "blend_mode": &"pigment_mix",
            "painting_mode": 0,
            "smudge_color_rate_option:enabled": false,
            "smudge_color_rate_option:strength": SaDrawnTipPresetsScript.AUTHORS_COLOUR_RATE,
        },
        "pen_settings":
        {
            "scatter": {"enabled": true, "strength": 1.0, "sensors": ["fuzzy_per_dab"]},
            "size": {"enabled": true, "strength": 0.7, "sensors": ["fuzzy_per_dab"]},
            "opacity":
            {
                "strength": 0.5,
                "sensors": ["pressure", "fuzzy_per_dab"],
                "common_curve": SaDrawnTipPresetsScript.OPACITY_NINE,
            },
            "hue":
            {
                "enabled": true,
                "sensors": ["fuzzy_per_dab"],
                "common_curve": [Vector2(0.0, 0.36700654), Vector2(1.0, 0.61761016)],
            },
        },
    },
    # The masked one, and the twenty-first because it is the one a stranger
    # cannot guess from a name: a soft round with a second, smaller rectangular
    # tip over it, so what lands is a scatter of marks rather than a disc. The
    # mask's angle is 30 degrees, in radians as the mask's tip reads it, where
    # 30.0 would turn it 30 radians.
    {
        "name": "Masked Stipple",
        "tags": ["scatter"],
        "bundle": ADVANCED,
        "about":
        (
            "A narrow ribbon with square ends, the trail of a small rectangular tip set at thirty degrees, "
            + "paler under a light press, for crisp hatching."
        ),
        "settings":
        {
            "radius": 0.037,
            "hardness:value": 0.2,
            "opacity": 1.0,
            "flow:value": 0.8,
            "spacing": 0.08,
            "masking:enabled": true,
            "masking:size": 0.35,
            "masking:spacing": 0.25,
            "masking:tip:shape": 1,
            "masking:tip:ratio": 0.4,
            "masking:tip:angle": PI / 6.0,
        },
        "pen_settings": {"opacity": {"enabled": true, "sensors": ["pressure"]}},
    },
]


## Every recipe this module ships, the basic set, then the drawn one, then the
## settings-derived one, then the bundled painter's presets, for a caller that holds the script rather
## than its name.
##
## The role registry hands back a `Script`, and a `const` is not a property of
## one, so `SaPresetStore.install_shipped` cannot read `ENTRIES` off what it is
## given. This is the door it reads instead. `ENTRIES` stays the basic table,
## [SaDrawnTipPresets] the second, [SaHabitPresets] the third and
## [SaAuthorPresets] the fourth. Each recipe handed out names its bundle, Sara
## Basic or Sara Advanced Paint, that bundle's fields and the bundles it shipped
## under before, so the store files it under the new marker and carries an old
## profile's record and presets over.
static func entries() -> Array[Dictionary]:
    var all: Array[Dictionary] = []
    for entry: Dictionary in ENTRIES:
        all.append(_stamped(entry, FORMERLY, ""))
    for entry: Dictionary in SaDrawnTipPresetsScript.ENTRIES:
        all.append(_stamped(entry, [SaDrawnTipPresetsScript.FORMERLY], SaDrawnTipPresetsScript.LICENCE))
    for entry: Dictionary in SaHabitPresetsScript.ENTRIES:
        all.append(_stamped(entry, [SaHabitPresetsScript.FORMERLY], ""))
    for entry: Dictionary in SaAuthorPresetsScript.ENTRIES:
        all.append(_stamped(entry, [SaAuthorPresetsScript.FORMERLY], ""))
    return all


## A copy of *entry* in its bundle, Sara Advanced Paint when it names none, with
## that bundle's fields, *formerly* as the names it shipped under before and
## *licence* as its own when it is not the bundle's.
static func _stamped(entry: Dictionary, formerly: Array[String], licence: String) -> Dictionary:
    var stamped := entry.duplicate()
    stamped.erase("formerly")
    var bundle := String(stamped.get("bundle", ADVANCED))
    stamped["bundle"] = bundle
    stamped["formerly"] = formerly.duplicate()
    stamped.merge(FIELDS[bundle])
    if not licence.is_empty():
        stamped["licence"] = licence
    return stamped


## The licence *bundle*'s recipes ship under, or empty for a bundle this table
## does not know.
##
## Static and taking the bundle's name, because `install_shipped` is handed this
## script rather than an instance and reads its table the same way. The name it
## is asked about is the one the recipes carry, which is also what a marker is
## filed under, so the sentence a painter reads and the file the install writes
## are keyed by one word.
static func licence_for(bundle: String) -> String:
    return String(LICENCES.get(bundle, ""))


## A fresh resource of *script* at its own defaults with *entry* written onto
## it, or null when the script cannot carry the whole recipe, read by the one
## reader every engine shares.
static func build(script: Script, entry: Dictionary) -> Resource:
    return SaPresetRecipe.build(script, entry)
