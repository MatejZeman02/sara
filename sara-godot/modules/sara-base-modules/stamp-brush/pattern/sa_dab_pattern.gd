## The pattern a stroke's dabs are textured with: the texture behind the
## settings' name, at the settings' scale and phase, bound onto the pattern
## binding for every dab.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **One per brush, beside the tip mask.** The dynamics half hands over one
## number, the dab's `pattern_strength`, and the name, scale and invert are read
## off the settings here, so the dynamics never touch a texture.
##
## **The scale is a texture size, not a push constant.** The push constant block
## is full to its last float, so a pattern at twice the scale is the pattern
## generated, or a picture resampled, at twice its tile. One texture is kept per
## scale until the settings ask for another, because a stroke asks once per dab.
## The tone (`SaPatternTone`) rides the same carrier, so the cache key is the
## name, the scale and the tone's three numbers and [member builds] counts one per
## change, never one per dab.
##
## **The invert and the mode ride the strength.** The invert takes its sign, and
## [method strength_for] takes the band: a magnitude at or under one is multiply,
## the band above it is subtract, then lightness, height, colour burn, hard mix
## softer and linear height, each a whole number higher with the strength as the
## fraction above the band's floor. Nought stays off in every band. The mode
## cannot be baked into texels, since multiply and subtract are two arithmetics
## over the same paper, and a sixth binding would burden every caller.
##
## **Not a static cache.** Compiled wrappers held in a static outlive the
## rendering device, so the store, the patterns and the texture die with the
## brush that holds them.
##
## **The store is the module's when the settings carry one**, put there at
## registration beside `background_color`, so the main canvas, the scratchpad and
## the Texture page's chooser read one store. A brush whose settings carry none
## makes its own.
class_name SaDabPattern
extends RefCounted

## Under this scale a tile is a texel and a pattern is noise, and over it a
## tile is bigger than a chunk and a dab is inside one texel of paper.
const MIN_SCALE: float = 0.1
const MAX_SCALE: float = 4.0

## What the paper does to the dab, under Krita's own numbers, so an imported
## `TexturingMode` is this value rather than a value this has to be mapped from.
##
## MULTIPLY thins the whole dab in proportion to the paper, so a tooth of a
## half halves the coverage wherever it sits. SUBTRACT takes the tooth off the
## coverage and stops at nothing, so the paint is lifted away where the grain
## sits and left as it was where the paper is clear. LIGHTNESS does not touch the
## coverage at all and moves the dab colour's lightness about the paper's
## neutral instead. HEIGHT reads the paper as a height field and paints only
## where it is below the strength, so a light touch catches the valleys and a
## heavy one everything.
##
## COLOR_BURN, HARD_MIX_SOFTER and LINEAR_HEIGHT are Krita's own arithmetic
## rather than Sara's, because the presets that name them look the way they do
## because of it. Each is the alpha variant Krita's texture
## option composites the paper onto the dab's alpha with, read from
## `libs/ui/tool/strokes/KisMaskingBrushCompositeOp.h` in the 5.2 tree, and the
## kernel's `sa_pattern_burned`, `sa_pattern_hard_mixed` and
## `sa_pattern_linear_height` name the function each came from. A burn divides
## the dab's lack of coverage by the paper, so a dark tooth closes the dab and a
## light one leaves it. Hard mix softer is three times the dab less twice the
## tooth, which is the flat, hard-edged fill the Flat Tip presets are
## made of. Linear height is Krita's height ramp and a multiply taken together,
## whichever paints more.
##
## **The gaps are Krita's**, read from
## `plugins/paintops/libpaintop/KisTextureOptionData.h` in the 5.2 tree, whose
## `TexturingMode` numbers the sixteen modes from nought. The nine between them
## that are not here are arithmetic this engine has no answer for, and none of
## the presets the importer is checked against names one. Naming the seven here
## is what keeps the import a comparison rather than a table, and the numbers
## are the file's rather than an index of Sara's own choosing.
enum Mode {
    MULTIPLY = 0,
    SUBTRACT = 1,
    LIGHTNESS = 2,
    COLOR_BURN = 7,
    HARD_MIX_SOFTER = 11,
    HEIGHT = 12,
    LINEAR_HEIGHT = 13,
}

## The row's choices in the order Krita lists them, and the word a dump and the
## row print for each, which is the one list every place that offers a mode
## reads so a mode added here is offered everywhere at once.
const MODES: Array[Mode] = [
    Mode.MULTIPLY,
    Mode.SUBTRACT,
    Mode.LIGHTNESS,
    Mode.COLOR_BURN,
    Mode.HARD_MIX_SOFTER,
    Mode.HEIGHT,
    Mode.LINEAR_HEIGHT,
]
const LABELS: Array[String] = [
    "Multiply",
    "Subtract",
    "Lightness",
    "Colour Burn",
    "Hard Mix Softer",
    "Height",
    "Linear Height",
]

## The two keys the per-stroke jump is drawn under. Named for the axis rather
## than for an option, because the phase is the paper's and not any one
## option's, and spelled out here so a reader can find both ends of the draw.
const RANDOM_KEY_X: String = "texture_random_offset_x"
const RANDOM_KEY_Y: String = "texture_random_offset_y"

## The store the name is looked up in, made on first use so a brush that never
## names a pattern never scans a folder.
var _store: SaPatternStore = null

## What is bound now: the key it was made for and the texture, so a stroke of
## a hundred dabs resolves the name once.
var _bound_key: String = ""
var _bound: SaTexture = null

## The pattern and key the last failed ask was for, so a paper that cannot be
## made is refused once and not once per dab, rather than read again and logged
## for every dab of a stroke, which is a lag a painter feels before they read
## the log. A rescan hands out a new pattern object, and that is when a file
## that was mended is tried again.
var _failed_key: String = ""
var _failed_pattern: SaPattern = null

## Why the last ask answered nothing, for the dump. Empty while it worked.
var error: String = ""

## How many times a pattern has been resolved into the texture the dab binds
## since this object was built, which has to be one per change of a row and
## never one per dab. Public because a test and the dump read it, written by
## this class and nowhere else.
var builds: int = 0

## How many times the bound paper has been read into [member _paper] for the
## texture sensor, which has to be one per build and never one per dab. Public
## for the stamp's suite, written by this class and nowhere else.
var reads: int = 0

## The bound paper as the CPU holds it for the texture sensor, one float a
## texel, read once per build and dropped with the texture it came from.
var _paper: Image = null

## The tone pass, which holds its own compute and dies with this object for the
## reason the header's third paragraph gives.
var _tone := SaPatternTone.new()

## The settings [method texture] answers for without building its key again,
## between [method hold] and [method release]. The key reads a dozen fields by
## name and formats two strings, and the brush asked for it twice a dab.
var _held_for: Resource = null
## Whether a curve of [member _held_for] reads the texture sensor, answered once
## at [method hold] because a walk asks it once a dab.
var _held_reads: bool = false


## *pattern_store* is the store to read, for a test over a scratch folder, and
## null is the two real folders on the first ask.
func _init(pattern_store: SaPatternStore = null) -> void:
    _store = pattern_store


## The store, resolved on the first ask: the constructor's, else the one on
## *settings*, else a fresh one over the two real folders.
func store(settings: Resource = null) -> SaPatternStore:
    if _store == null and settings != null and "pattern_store" in settings:
        _store = settings.get("pattern_store") as SaPatternStore
    if _store == null:
        _store = SaPatternStore.new()
    return _store


## The name *settings* carries, or empty for a brush with none.
static func name_of(settings: Resource) -> String:
    return String(settings.get("pattern_name")) if settings != null and "pattern_name" in settings else ""


## The scale *settings* asks for, clamped to the band a pattern makes sense in.
static func scale_of(settings: Resource) -> float:
    var scale: float = float(settings.get("texture_scale")) if settings != null and "texture_scale" in settings else 1.0
    return clampf(scale, MIN_SCALE, MAX_SCALE)


## Whether *settings* asks for the paper turned over.
static func inverted(settings: Resource) -> bool:
    return settings != null and "texture_invert" in settings and bool(settings.get("texture_invert"))


## The mode *settings* asks for, and multiply for a preset written before
## the row existed, which is what an additive key means, and for a number of
## Krita's this engine has no arithmetic for.
static func mode_of(settings: Resource) -> Mode:
    if settings == null or not "texture_mode" in settings:
        return Mode.MULTIPLY
    return mode_for(int(settings.get("texture_mode")))


## The mode Krita's number *value* names, and multiply for every number that is
## not one of the seven Sara paints.
##
## **The number of Krita's rather than an index of Sara's**, which is what lets
## the import write a preset's own value onto the row rather than translate it,
## and what makes the nine modes Sara has no answer for paint multiply without
## a table of them.
##
## A caller that has to know whether the number was carried rather than
## substituted compares the answer with the number it passed, which is what
## `sa_kpp_import.gd` does to decide its tag.
static func mode_for(value: int) -> Mode:
    return value as Mode if MODES.has(value) else Mode.MULTIPLY


## The word a dump prints for *mode*, which is the row's own name rather than a
## number: a reader comparing two dumps wants to see that the stroke changed
## mode rather than that one integer became another.
static func mode_name(mode: Mode) -> String:
    return LABELS[maxi(MODES.find(mode), 0)].to_lower()


## The whole number *mode*'s band starts at: multiply is the floor at nought and
## every mode above it takes the next number, so the kernel reads the mode back
## off the magnitude it is handed and no band ever touches the one above it. The
## band is not Krita's number, because the number has gaps and the packing's
## clamp is the highest band plus one.
##
## **A band is not a mode's place in [constant MODES]**: the first four hold the
## lowest bands and the other three sit above height, so a mode added to the
## list moves no band the kernel already reads.
static func band_of(mode: Mode) -> int:
    match mode:
        Mode.SUBTRACT:
            return 1
        Mode.LIGHTNESS:
            return 2
        Mode.HEIGHT:
            return 3
        Mode.COLOR_BURN:
            return 4
        Mode.HARD_MIX_SOFTER:
            return 5
        Mode.LINEAR_HEIGHT:
            return 6
        _:
            return 0


## The offset *settings* asks for, in document texels.
static func offset_of(settings: Resource) -> Vector2:
    if settings == null or not "texture_offset_x" in settings:
        return Vector2.ZERO
    return Vector2(float(settings.get("texture_offset_x")), float(settings.get("texture_offset_y")))


## The strength the push constant carries for *dab*: the dab's own raised by the
## band its mode sits at, negative when *settings* says invert, and nought
## whenever there is no texture to read, because a strength above nought over
## the clear stand-in paints nothing at all.
##
## The two ride one number for the reason the header's mode paragraph gives,
## and they do not collide: a strength of nothing has already returned, so a
## multiply is at one or under and each of the six above it is strictly above
## the band below, one whole number apart.
##
## **Never past the top band.** The number is held to as many bands as there are
## modes, here rather than in `SaDabPacking`: the encoding is this class's, so
## the ceiling is too, and the door writes the number it is handed.
func strength_for(dab_strength: float, settings: Resource) -> float:
    if dab_strength <= 0.0 or texture(settings) == null:
        return 0.0
    var carried := minf(dab_strength + float(band_of(mode_of(settings))), float(MODES.size()))
    return -carried if inverted(settings) else carried


## How far the paper may jump when a stroke starts, in document texels, and
## nothing when the randomiser is off.
##
## Two amounts rather than one, because paper is not isotropic: a grain that
## runs one way wants jumping along it and not across it. Negatives are clamped
## away rather than read as a jump the other direction, because the phase drawn
## below is signed already and an amount is a distance.
static func random_amount_of(settings: Resource) -> Vector2:
    if settings == null or not "texture_random_per_stroke" in settings:
        return Vector2.ZERO
    if not bool(settings.get("texture_random_per_stroke")):
        return Vector2.ZERO
    return Vector2(
        maxf(float(settings.get("texture_random_offset_x")), 0.0), maxf(float(settings.get("texture_random_offset_y")), 0.0)
    )


## The jump this stroke drew, in document texels, and nothing while *info* is
## null or the randomiser is off.
##
## **Drawn once per stroke, not once per dab.** `SaStrokeInfo.stroke_random`
## already answers one number per stroke per key and caches it, which is what
## `fuzzy_per_stroke` is built on, so asking it here every dab costs a
## dictionary lookup and answers the same number until the pen is lifted. A
## phase that moved between dabs would be noise rather than paper.
##
## The two keys are this file's own and not an option's, so a brush with a
## fuzzy per stroke sensor on the Texture option draws a different number from
## the phase and the two do not move together.
##
## The draw is `2 * randf - 1` times the amount, so the amount is a radius
## around the painter's fixed offset rather than a ceiling above it: a painter
## who set a phase on purpose keeps it as the middle of the jump.
static func random_phase(settings: Resource, info: SaStrokeInfo) -> Vector2:
    var amount := random_amount_of(settings)
    if info == null or amount == Vector2.ZERO:
        return Vector2.ZERO
    return Vector2(
        (2.0 * info.stroke_random(RANDOM_KEY_X) - 1.0) * amount.x, (2.0 * info.stroke_random(RANDOM_KEY_Y) - 1.0) * amount.y
    )


## The tile grid's origin for one paint target, in the kernel's chunk-local
## frame: the chunk's own document origin plus the painter's offset, plus the
## jump this stroke drew, so every chunk of one stroke reads one grid and the
## next stroke reads a grid in a different phase.
##
## *info* defaults to null so a caller with no stroke, which is every test that
## checks the fixed offset and the preview that has not pressed yet, reads the
## grid the painter set and nothing else.
static func offset_for(target: SaPaintContext.Target, chunk_size: int, settings: Resource, info: SaStrokeInfo = null) -> Vector2:
    return Vector2(target.grid_pos * chunk_size) + offset_of(settings) + random_phase(settings, info)


## Puts the texture *settings* names on binding 4 of *compute* when *dab_strength*
## is above nought, and leaves the stand-in the tip mask bound when it is not.
func bind(compute: SaCompute, settings: Resource, dab_strength: float) -> void:
    if compute == null or dab_strength <= 0.0:
        return
    var bound := texture(settings)
    if bound != null:
        compute.set_sampled_texture(SaStampBindings.PATTERN_BINDING, bound.rid)


## What the texture sensor reads for a dab at document point *centre*: the
## paper the kernel reads at the texel under the centre, 0 to 1, turned over
## when *settings* says invert, and the neutral grey with no paper bound.
##
## **Read as the kernel reads it.** The texel is the one `sa_pattern_sampled`
## would read for the texel the centre sits in, at the same offset and the same
## per-stroke jump, and between its four neighbours the way the linear sampler
## reads a fractional offset. The tone and the scale are in the texels already,
## because this reads the texture the dab binds and not the pattern's source.
##
## **One readback per build, never one per dab.** The texture sensor is read on
## the CPU before the dab is laid, and a generated paper has no CPU twin, so the
## tile is copied out once when it is made and kept beside it. The canvas is the
## thing a stroke may never read back, and this is a tile of paper no stroke
## writes, which is the reading `SaPattern.image_at` gives a chooser. A brush
## with no paper named never reads anything.
##
## **A stroke's ask reads nothing its curves do not read**. A
## dab asks with its stroke's *info*, and while no curve of *settings* reads the
## texture sensor the answer is the neutral grey the sensor would never look at,
## with no tile read back. A preset that does read it has had its tile read by
## [method prepare] in a frame with no stroke running, so its first dab finds
## the paper on the CPU already, with or without a hover before the press. An ask with no stroke, a suite's or a dump's, reads the
## paper whatever the curves say.
func sensor_reading(settings: Resource, centre: Vector2, info: SaStrokeInfo = null) -> float:
    if info != null and not reads_texture(settings):
        return SaSensor.NEUTRAL_TEXTURE
    var paper := _paper_image(settings)
    if paper == null:
        return SaSensor.NEUTRAL_TEXTURE
    var at := centre.floor() + offset_of(settings) + random_phase(settings, info)
    var low := at.floor()
    var t := at - low
    var width := paper.get_width()
    var height := paper.get_height()
    var x0 := posmod(int(low.x), width)
    var y0 := posmod(int(low.y), height)
    var x1 := posmod(x0 + 1, width)
    var y1 := posmod(y0 + 1, height)
    var top := lerpf(paper.get_pixel(x0, y0).r, paper.get_pixel(x1, y0).r, t.x)
    var bottom := lerpf(paper.get_pixel(x0, y1).r, paper.get_pixel(x1, y1).r, t.x)
    var sampled := clampf(lerpf(top, bottom, t.y), 0.0, 1.0)
    return 1.0 - sampled if inverted(settings) else sampled


## Whether a curve of *settings* reads the texture sensor: an option that is on,
## reads its sensors, and has the texture sensor switched on among them, which
## is the test `SaDynamics` makes before it reads an option at all. Asked while a
## walk holds *settings* it is answered once for the walk.
func reads_texture(settings: Resource) -> bool:
    if _held_for != null and settings == _held_for:
        return _held_reads
    return _any_texture_curve(settings)


## Builds the paper *settings* names and reads it back for the texture sensor,
## while no stroke is running, so a preset whose curves read the sensor pays
## the one readback before the press rather than inside its first frame. The
## stamp calls it from its frame clock whenever no stroke runs, so the read
## lands within a frame of the paper or a curve changing, whatever changed it,
## and a door's press with no hover before it finds the paper read.
## Past that frame it is the curves walked, a key compared and a cached image
## returned. Nothing at all for a preset no curve of which reads the sensor.
func prepare(settings: Resource) -> void:
    if reads_texture(settings):
        _paper_image(settings)


static func _any_texture_curve(settings: Resource) -> bool:
    if settings == null or not settings.has_method("options"):
        return false
    var options: Dictionary = settings.options()
    for key: String in options:
        var option := options[key] as SaCurveOption
        if option == null or not option.enabled or not option.use_curve:
            continue
        var sensor := option.sensor_for(SaSensor.Id.TEXTURE)
        if sensor != null and sensor.active:
            return true
    return false


## The bound paper on the CPU, read back the first time it is asked for after a
## build, and null while nothing is bound.
func _paper_image(settings: Resource) -> Image:
    var bound := texture(settings)
    if bound == null or bound.rd == null:
        return null
    if _paper != null:
        return _paper
    # Read here rather than through the export path, which is not the door a
    # module sees, so this file is on `tests/test_hard_rules.gd`'s list of the
    # files allowed to read a texture back.
    var formats := {
        RenderingDevice.DATA_FORMAT_R32_SFLOAT: [Image.FORMAT_RF, 4],
        RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT: [Image.FORMAT_RGBAF, 16],
    }
    if not formats.has(bound.format):
        return null
    var raw := bound.rd.texture_get_data(bound.rid, 0)
    if raw.size() != bound.size.x * bound.size.y * int(formats[bound.format][1]):
        return null
    _paper = Image.create_from_data(bound.size.x, bound.size.y, false, int(formats[bound.format][0]), raw)
    reads += 1
    return _paper


## Settles the paper *settings* names for one input event's walk, so every
## dab of it binds the texture this answers without asking again. Nothing a
## painter can change moves while a walk is running.
func hold(settings: Resource) -> void:
    _held_for = null
    texture(settings)
    _held_reads = _any_texture_curve(settings)
    _held_for = settings


## Ends what [method hold] settled, so the next dab reads the settings afresh.
func release() -> void:
    _held_for = null


## The texture *settings* asks for, made when the name or the scale moved and
## answered from the last ask otherwise. Null when there is no name, the name
## is not in the store, or the pattern could not be made, with `error` saying
## which.
func texture(settings: Resource) -> SaTexture:
    if _held_for != null and settings == _held_for and _bound != null and _bound.rid.is_valid():
        return _bound
    var pattern_name := name_of(settings)
    if pattern_name.is_empty():
        _drop()
        error = ""
        return null
    var scale := scale_of(settings)
    var key := "%s|%.3f|%s" % [pattern_name, scale, SaPatternTone.key_of(settings)]
    if key == _bound_key and _bound != null and _bound.rid.is_valid():
        return _bound
    _drop()
    var pattern := store(settings).pattern(pattern_name)
    if pattern == null:
        error = tr("no pattern called '%s' in either patterns folder.") % pattern_name
        return null
    if pattern == _failed_pattern and key == _failed_key:
        return null
    _bound = _make(pattern, scale, settings)
    if _bound == null:
        _failed_pattern = pattern
        _failed_key = key
        # The pattern's own reason first, because a tile that never got made
        # leaves the tone with nothing to say but that there was nothing to tone.
        error = pattern.error
        if error.is_empty():
            error = _tone.error
        if error.is_empty():
            error = tr("%s could not be made.") % pattern_name
        return null
    _bound_key = key
    _failed_pattern = null
    _failed_key = ""
    error = ""
    return _bound


## What the dump reads: the name, the numbers and what the next dab binds,
## asked for rather than remembered, so a name blanked since the last stroke
## reads as nothing bound.
func report(settings: Resource) -> Dictionary:
    var bound := texture(settings)
    return {
        "name": name_of(settings),
        "scale": scale_of(settings),
        "offset": [offset_of(settings).x, offset_of(settings).y],
        "random_per_stroke":
        settings != null and "texture_random_per_stroke" in settings and bool(settings.get("texture_random_per_stroke")),
        "random_amount": [random_amount_of(settings).x, random_amount_of(settings).y],
        "invert": inverted(settings),
        "mode": mode_name(mode_of(settings)),
        "tone": _tone.report(settings),
        "builds": builds,
        "reads": reads,
        "reads_texture": reads_texture(settings),
        "bound": bound != null,
        "texture_size": [bound.size.x, bound.size.y] if bound != null else [0, 0],
        "error": error,
    }


## *pattern* at *scale* with *settings*' tone folded in: its own texture at a
## scale of one, generated at the scaled tile when it is a kernel, and resampled
## on the CPU when it is a picture, which is the pattern's own decoded mask and
## an upload and not a readback. Then one dispatch of `pattern_tone` over
## whatever came out.
##
## **The tone is baked into a second texture and never into the first**, because
## at a scale of one the first is `SaPattern`'s own cached texture, which every
## brush naming that pattern shares. Toning it in place would put this brush's
## contrast on every other brush's paper. `SaPatternTone.bake` hands back the
## source unchanged when the three rows are neutral, so the second texture is
## made only when there is something to put in it.
func _make(pattern: SaPattern, scale: float, settings: Resource) -> SaTexture:
    var made := _tone.bake(_sized(pattern, scale), settings)
    if made != null:
        builds += 1
    return made


## *pattern* at *scale*, before the tone.
##
## **A generated pattern is told the scale as well as the size.** The tile alone
## grows a kernel that counts its features across the tile, and Paper Grain keeps
## its cells eight texels wide whatever the tile, so a wash at a scale of a
## quarter, a half and one laid one mottle three times. The zoom
## is the side made over the pattern's own tile rather than the scale asked for,
## because the side is rounded to whole texels and a kernel that counts its cells
## from the two has to land on the count its own tile has.
func _sized(pattern: SaPattern, scale: float) -> SaTexture:
    if is_equal_approx(scale, 1.0):
        return pattern.texture()
    if pattern.is_generated():
        var side := maxi(int(round(float(pattern.tile) * scale)), 1)
        return pattern.generate(Vector2i(side, side), float(side) / float(pattern.tile))
    var mask := pattern.mask()
    if mask == null:
        return null
    var scaled := mask.duplicate() as Image
    scaled.resize(
        maxi(int(round(float(mask.get_width()) * scale)), 1),
        maxi(int(round(float(mask.get_height()) * scale)), 1),
        Image.INTERPOLATE_BILINEAR
    )
    return SaPatternImage.upload(scaled)


func _drop() -> void:
    _bound = null
    _paper = null
    _bound_key = ""
