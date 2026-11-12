## A Local Contrast filter brings out detail at every scale
## without halos, after darktable's local laplacian.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The filter is attached to a layer and the chain's answer for each chunk is
## read back, as the wavelet denoise's suite reads it. The attached form and the
## one-shot run the same pass (`SaNeighbourhoodPass.Runner`), so this reads
## both. Lightness is Oklab's, read off the gamma sRGB a document starts in, or
## off the stored coordinates of an Oklab document.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const LocalContrastFilter = preload("res://modules/sara-base-modules/base/filters/local_contrast/local_contrast_filter.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const MODULE_DIR := "res://modules/sara-base-modules"
const SIDE := 256
## The settings that make every remap the identity.
const IDENTITY := {"detail": 100, "highlights": 100, "shadows": 100, "midtone_range": 0.5}
const MORE_DETAIL := {"detail": 150, "highlights": 50, "shadows": 50, "midtone_range": 0.5}

var _dir_was_set: bool = false


func before_each() -> void:
    _dir_was_set = ModuleLoader.module_dirs.has(OWNER)
    if not _dir_was_set:
        ModuleLoader.module_dirs[OWNER] = MODULE_DIR


func after_each() -> void:
    if not _dir_was_set:
        ModuleLoader.module_dirs.erase(OWNER)


## Paints *images*, grid position -> Image of stored values, into a fresh
## document of *size* in *space*, gamma sRGB when null, attaches *filter*,
## Local Contrast when null, with *params* and answers the chain's reading of
## every painted chunk by grid position.
func _filtered(
    size: Vector2i, images: Dictionary, params: Dictionary, space: SaColorSpace = null, filter: SaFilter = null
) -> Dictionary:
    var easel := SaEasel.create_default(size, null, space)
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    easel.compositor.filter_chain.registry = SaFilterRegistry.new()
    if filter == null:
        filter = LocalContrastFilter.new()
    easel.compositor.filter_chain.registry.register(filter, OWNER)
    var key := SaFilterRegistry.key_for(OWNER, filter)
    var layer := easel.document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    for grid_pos: Vector2i in images:
        var chunk := layer.get_or_create_chunk(grid_pos)
        var image: Image = images[grid_pos]
        GlobalShaderCompiler.get_rd().texture_update(chunk.field(SaFieldSpec.ALBEDO).rid, 0, image.get_data())
    SaFilterOps.new(easel.document).attach(layer, key, params)
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()
    var out := {}
    for grid_pos: Vector2i in images:
        var answer := easel.compositor.filter_chain.filtered(layer, layer.get_field(grid_pos), grid_pos, SaDocument.WHOLE_CHUNK)
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(answer.rid, 0)
        out[grid_pos] = Image.create_from_data(SIDE, SIDE, false, Image.FORMAT_RGBAF, bytes)
    layer = null
    easel.free()
    return out


func _one(image: Image, params: Dictionary, space: SaColorSpace = null, filter: SaFilter = null) -> Image:
    return _filtered(Vector2i(SIDE, SIDE), {Vector2i.ZERO: image}, params, space, filter)[Vector2i.ZERO]


# --- Colour ------------------------------------------------------------------


static func _encode(v: float) -> float:
    var m := absf(v)
    var e := 12.92 * m if m <= 0.0031308 else 1.055 * pow(m, 1.0 / 2.4) - 0.055
    return signf(v) * e


static func _decode(v: float) -> float:
    var m := absf(v)
    var d := m / 12.92 if m <= 0.04045 else pow((m + 0.055) / 1.055, 2.4)
    return signf(v) * d


## The gamma sRGB a document stores for the Oklab colour *lab*.
static func _stored(lab: Vector3, alpha: float = 1.0) -> Color:
    var linear := SaOklab.to_linear_srgb(lab)
    return Color(_encode(linear.x), _encode(linear.y), _encode(linear.z), alpha)


## The Oklab colour of the gamma sRGB *stored*.
static func _lab(stored: Color) -> Vector3:
    return SaOklab.from_linear_srgb(Vector3(_decode(stored.r), _decode(stored.g), _decode(stored.b)))


static func _distance(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


## The largest channel difference between *a* and *b* over *area*.
static func _worst(a: Image, b: Image, area: Rect2i) -> float:
    var worst := 0.0
    for y in range(area.position.y, area.end.y):
        for x in range(area.position.x, area.end.x):
            worst = maxf(worst, _distance(a.get_pixel(x, y), b.get_pixel(x, y)))
    return worst


# --- Pictures ----------------------------------------------------------------


## One chunk of *colour* everywhere.
static func _flat(colour: Color) -> Image:
    var image := Image.create(SIDE, SIDE, false, Image.FORMAT_RGBAF)
    image.fill(colour)
    return image


## A picture of *size* with detail at every scale and every tone: a ramp of
## lightness across, a slow wave of hue, and grain, the same for the same
## *seed*.
static func _textured(size: Vector2i, seed_value: int) -> Image:
    var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBAF)
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value
    for y in size.y:
        for x in size.x:
            var lightness := 0.2 + 0.6 * float(x) / float(size.x) + rng.randf_range(-0.06, 0.06)
            lightness += 0.08 * sin(float(y) * 0.11) * cos(float(x) * 0.05)
            var hue := float(x + y) * 0.013
            var lab := Vector3(lightness, 0.08 * cos(hue), 0.08 * sin(hue))
            image.set_pixel(x, y, _stored(lab))
    return image


## Grey of Oklab lightness *dark* on the columns before *at* and *bright* on the
## rest.
static func _step(dark: float, bright: float, at: int) -> Image:
    var image := _flat(_stored(Vector3(bright, 0.0, 0.0)))
    image.fill_rect(Rect2i(0, 0, at, SIDE), _stored(Vector3(dark, 0.0, 0.0)))
    return image


## Grey of Oklab lightness *mid*, every other pair of columns *amplitude* above
## it and the rest as far below.
static func _stripes(mid: float, amplitude: float) -> Image:
    var image := Image.create(SIDE, SIDE, false, Image.FORMAT_RGBAF)
    for x in SIDE:
        var lightness := mid + (amplitude if (x >> 1) % 2 == 0 else -amplitude)
        image.fill_rect(Rect2i(x, 0, 1, SIDE), _stored(Vector3(lightness, 0.0, 0.0)))
    return image


## Half the spread of Oklab lightness over the columns from 96 to 160 of row 128.
static func _amplitude(image: Image) -> float:
    var low := INF
    var high := -INF
    for x in range(96, 160):
        var lightness := _lab(image.get_pixel(x, 128)).x
        low = minf(low, lightness)
        high = maxf(high, lightness)
    return (high - low) * 0.5


# --- The suite ---------------------------------------------------------------


func test_the_controls_are_darktables_four_by_its_defaults() -> void:
    var filter := LocalContrastFilter.new()
    assert_eq(
        filter.parameters(),
        {"detail": 125.0, "highlights": 50.0, "shadows": 50.0, "midtone_range": 0.5},
        "With no dialog it answers Detail 125 %, Highlights and Shadows 50 % and Midtone range 0.5"
    )
    var params := LocalContrastFilter.params_for(filter.parameters(), null)
    assert_almost_eq(float(params["clarity"]), 0.25, 1e-6, "Detail 125 % is darktable's clarity of 0.25")
    assert_almost_eq(float(params["sigma"]), 0.5, 1e-6, "and the midtone range its sigma")
    assert_eq(filter.family(), &"sharpen", "It is listed under Sharpen")


func test_the_radius_is_the_reach_of_five_levels() -> void:
    # The coarsest lightness reads 2 * (2^4 - 1) out, and each collapse back up
    # adds the expansion's reach, 2^(l + 1) at level l.
    var reach := 2 * ((1 << (LocalContrastFilter.LEVELS - 1)) - 1)
    for level in range(LocalContrastFilter.LEVELS - 2, -1, -1):
        reach += 1 << (level + 1)
    assert_eq(reach, 60, "Five levels reach 60 texels")
    assert_eq(LocalContrastFilter.RADIUS, reach, "and the pass declares that radius")
    assert_eq(SaChunk.SIZE % (1 << (LocalContrastFilter.LEVELS - 1)), 0, "Chunk corners sit on the coarsest level's grid")


func test_a_flat_colour_reads_back_unchanged() -> void:
    var image := _flat(Color(0.62, 0.41, 0.3, 1.0))
    for params: Dictionary in [LocalContrastFilter.DEFAULTS, MORE_DETAIL]:
        var worst := _worst(_one(image, params), image, Rect2i(0, 0, SIDE, SIDE))
        assert_true(worst < 1e-4, "A flat colour is left as it was at %s, worst %f" % [params, worst])


## Paint on a transparent layer is filtered as if nothing lay round it, since
## every sum is weighted by alpha, so a flat patch stays flat to its edge and the
## transparent texels keep what they stored.
func test_a_flat_patch_on_a_transparent_layer_reads_back_unchanged() -> void:
    var image := _flat(Color(0.0, 1.0, 0.0, 0.0))
    image.fill_rect(Rect2i(60, 70, 90, 100), Color(0.62, 0.41, 0.3, 1.0))
    var worst := _worst(_one(image, MORE_DETAIL), image, Rect2i(0, 0, SIDE, SIDE))
    assert_true(worst < 1e-4, "A patch on transparency keeps its colour to its edge, worst %f" % worst)


func test_detail_and_both_slopes_at_100_give_any_picture_back() -> void:
    var image := _textured(Vector2i(SIDE, SIDE), 5)
    image.fill_rect(Rect2i(200, 0, 56, SIDE), Color(0.0, 1.0, 0.0, 0.0))
    image.fill_rect(Rect2i(180, 0, 20, SIDE), Color(0.9, 0.2, 0.1, 0.4))
    var worst := _worst(_one(image, IDENTITY), image, Rect2i(0, 0, SIDE, SIDE))
    assert_true(worst < 2e-4, "Every remap the identity gives the picture back, worst %f" % worst)


func test_fine_stripes_on_mid_grey_are_raised_at_detail_150() -> void:
    var image := _stripes(0.5, 0.05)
    var before := _amplitude(image)
    var after := _amplitude(_one(image, MORE_DETAIL))
    assert_almost_eq(before, 0.05, 1e-4, "The stripes are laid at an amplitude of 0.05")
    assert_true(after > before * 1.2, "Detail 150 %% raises them, %f to %f" % [before, after])


## How far the Oklab lightness of row 128 of *image* reads past *dark* below
## and *bright* above, the larger of the two.
static func _past(image: Image, dark: float, bright: float) -> float:
    var worst := 0.0
    for x in SIDE:
        var lightness := _lab(image.get_pixel(x, 128)).x
        worst = maxf(worst, maxf(dark - lightness, lightness - bright))
    return worst


## A hard step from lightness 0.2 to 0.8. No texel reads past the dark side
## below or the bright side above by more than BOUND, at the defaults and at
## Detail 150 %, where it reads nothing past either. An unsharp mask that raises
## the fine stripes no more than Detail 150 % raises them rings past both sides
## by more than RINGS, which is the halo this filter does not draw.
func test_a_hard_step_draws_no_halo() -> void:
    const BOUND := 0.005
    const RINGS := 0.05
    var step := _step(0.2, 0.8, 128)
    for params: Dictionary in [LocalContrastFilter.DEFAULTS, MORE_DETAIL]:
        var past := _past(_one(step, params), 0.2, 0.8)
        assert_true(past < BOUND, "Nothing reads past either side at %s, at most %f" % [params, past])
    var unsharp := {"kind": SaSharpenFilter.UNSHARP_MASK, "radius": 3, "amount": 40, "threshold": 0}
    var stripes := _stripes(0.5, 0.05)
    var raised := _amplitude(_one(stripes, unsharp, null, SaSharpenFilter.new()))
    var ours := _amplitude(_one(stripes, MORE_DETAIL))
    assert_true(raised <= ours, "The unsharp mask raises the stripes no more, %f against %f" % [raised, ours])
    var rang := _past(_one(step, unsharp, null, SaSharpenFilter.new()), 0.2, 0.8)
    assert_true(rang > RINGS, "and rings past the step's sides, by %f" % rang)


## Only the lightness moves: the a and b of a coloured picture come back as
## they went in, in a gamma sRGB document and an Oklab one, and the two read one
## lightness for one picture.
func test_a_and_b_are_kept_in_an_srgb_and_an_oklab_document() -> void:
    var image := _textured(Vector2i(SIDE, SIDE), 9)
    var stored_lab := Image.create(SIDE, SIDE, false, Image.FORMAT_RGBAF)
    for y in SIDE:
        for x in SIDE:
            var lab := _lab(image.get_pixel(x, y))
            stored_lab.set_pixel(x, y, Color(lab.x, lab.y, lab.z, 1.0))
    var srgb := _one(image, MORE_DETAIL)
    var oklab := _one(stored_lab, MORE_DETAIL, SaColorSpace.oklab())
    var moved := 0.0
    var hue_moved := 0.0
    var apart := 0.0
    for y in range(0, SIDE, 3):
        for x in range(0, SIDE, 3):
            var before := _lab(image.get_pixel(x, y))
            var after := _lab(srgb.get_pixel(x, y))
            var held := oklab.get_pixel(x, y)
            moved = maxf(moved, absf(after.x - before.x))
            hue_moved = maxf(hue_moved, maxf(absf(after.y - before.y), absf(after.z - before.z)))
            hue_moved = maxf(hue_moved, maxf(absf(held.g - before.y), absf(held.b - before.z)))
            apart = maxf(apart, absf(held.r - after.x))
    assert_true(moved > 0.01, "The run moved the lightness, by %f at most" % moved)
    assert_true(hue_moved < 1e-3, "and kept a and b in both documents, worst %f" % hue_moved)
    assert_true(apart < 1e-3, "and the two documents read one lightness, %f apart" % apart)


## The tile and overlap assertion. One picture over a document of four chunks,
## and the same picture cut to the middle of a document of one: the texels
## round the corner where the four meet, read from each of the four, equal the
## same texels read from the one chunk that holds them in its interior. The cut
## is 128 texels in, a multiple of the coarsest level's spacing, so both
## documents put the pyramid on one grid and the two read the same bits. A
## radius of 32 in place of the reach of 60 put them 1.2e-4 apart.
func test_a_texel_is_the_same_over_one_chunk_or_four() -> void:
    var picture := _textured(Vector2i(SIDE * 2, SIDE * 2), 23)
    var four := {}
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
        four[grid_pos] = picture.get_region(Rect2i(grid_pos * SIDE, Vector2i(SIDE, SIDE)))
    var shift := Vector2i(SIDE >> 1, SIDE >> 1)
    var one := picture.get_region(Rect2i(shift, Vector2i(SIDE, SIDE)))
    var tiled := _filtered(Vector2i(SIDE * 2, SIDE * 2), four, LocalContrastFilter.DEFAULTS)
    var alone := _one(one, LocalContrastFilter.DEFAULTS)
    var worst := 0.0
    var moved := 0.0
    for y in range(SIDE - 40, SIDE + 40):
        for x in range(SIDE - 40, SIDE + 40):
            var grid_pos := Vector2i(1 if x >= SIDE else 0, 1 if y >= SIDE else 0)
            var from_four: Color = (tiled[grid_pos] as Image).get_pixel(x - grid_pos.x * SIDE, y - grid_pos.y * SIDE)
            var from_one := alone.get_pixel(x - shift.x, y - shift.y)
            worst = maxf(worst, _distance(from_four, from_one))
            moved = maxf(moved, _distance(from_one, picture.get_pixel(x, y)))
    assert_true(moved > 0.01, "The run moved the texels it is compared on, %f" % moved)
    assert_true(worst < 1e-6, "and the four chunks agree with the one across the seams, worst %f" % worst)


## A paint over a small rectangle marks that rectangle dirty and no more, so
## the chain filters it again over the rectangle grown by the halo, while the
## frame's padding and the pyramid's buffer still hold what the run before left
## round it. What the canvas then shows round the paint is what a fresh run
## over the finished picture shows.
func test_a_repaint_of_a_small_rectangle_reads_as_a_fresh_run() -> void:
    var picture := _textured(Vector2i(SIDE, SIDE), 31)
    var patch := Rect2i(150, 90, 12, 9)
    var finished := picture.duplicate() as Image
    finished.fill_rect(patch, _stored(Vector3(0.9, 0.05, -0.03)))
    var painted := _attached(picture)
    var layer := painted.document.get_node("Background") as SaLayer
    var albedo := layer.get_or_create_chunk(Vector2i.ZERO).field(SaFieldSpec.ALBEDO)
    GlobalShaderCompiler.get_rd().texture_update(albedo.rid, 0, finished.get_data())
    painted.document.invalidate_chunk_regions({Vector2i.ZERO: patch}, layer)
    painted.process_pending_composite()
    var fresh := _attached(finished)
    var worst := 0.0
    var moved := 0.0
    for y in range(patch.position.y - 70, patch.end.y + 70, 3):
        for x in range(patch.position.x - 70, mini(patch.end.x + 70, SIDE), 3):
            var at := Vector2i(x, y)
            var shown := Bench.texel(painted.output, at)
            worst = maxf(worst, _distance(shown, Bench.texel(fresh.output, at)))
            moved = maxf(moved, _distance(shown, picture.get_pixelv(at)))
    layer = null
    painted.free()
    fresh.free()
    assert_true(moved > 0.01, "The paint and the filter moved the canvas round the patch, %f" % moved)
    assert_true(worst < 1e-5, "and the repaint reads as a fresh run, worst %f" % worst)


## An easel of one chunk holding *picture*, Local Contrast attached at its
## defaults and the whole canvas composited.
func _attached(picture: Image) -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(SIDE, SIDE))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    easel.compositor.filter_chain.registry = SaFilterRegistry.new()
    var filter := LocalContrastFilter.new()
    easel.compositor.filter_chain.registry.register(filter, OWNER)
    var layer := easel.document.get_node("Background") as SaLayer
    var chunk := layer.get_or_create_chunk(Vector2i.ZERO)
    GlobalShaderCompiler.get_rd().texture_update(chunk.field(SaFieldSpec.ALBEDO).rid, 0, picture.get_data())
    SaFilterOps.new(easel.document).attach(layer, SaFilterRegistry.key_for(OWNER, filter), LocalContrastFilter.DEFAULTS)
    Bench.composite(easel)
    return easel
