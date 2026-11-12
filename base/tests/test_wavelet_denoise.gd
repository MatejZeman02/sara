## Wavelet Denoise. The filter is attached to a layer and the chain's answer
## for each chunk is read back: an identity at zero strength, a noisy field
## made quieter, a hard edge kept, and the tile and overlap assertion, a texel
## that reads the same whether its chunk was run alone or among its
## neighbours. The attached form and the one-shot run the same pass
## (`SaNeighbourhoodPass.Runner`), so this reads both.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const WaveletDenoiseFilter = preload("res://modules/sara-base-modules/base/usual/wavelet_denoise_filter.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const MODULE_DIR := "res://modules/sara-base-modules"
const CENTRE := Vector2i(128, 128)

var _dir_was_set: bool = false


func before_each() -> void:
    _dir_was_set = ModuleLoader.module_dirs.has(OWNER)
    if not _dir_was_set:
        ModuleLoader.module_dirs[OWNER] = MODULE_DIR


func after_each() -> void:
    if not _dir_was_set:
        ModuleLoader.module_dirs.erase(OWNER)


## Paints *images*, grid position -> Image, into a fresh document of *size*,
## attaches the wavelet denoise with *params* and answers the chain's reading
## of every painted chunk by grid position.
func _denoised(size: Vector2i, images: Dictionary, params: Dictionary) -> Dictionary:
    var easel := Bench.easel(size)
    var filter := WaveletDenoiseFilter.new()
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
    Bench.composite(easel)
    var out := {}
    for grid_pos: Vector2i in images:
        var answer := easel.compositor.filter_chain.filtered(layer, layer.get_field(grid_pos), grid_pos, SaDocument.WHOLE_CHUNK)
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(answer.rid, 0)
        out[grid_pos] = Image.create_from_data(SaChunk.SIZE, SaChunk.SIZE, false, Image.FORMAT_RGBAF, bytes)
    layer = null
    easel.free()
    return out


func _one(image: Image, params: Dictionary) -> Image:
    var side := Vector2i(SaChunk.SIZE, SaChunk.SIZE)
    return _denoised(side, {Vector2i.ZERO: image}, params)[Vector2i.ZERO]


## Grey 0.5 with uniform grain of *spread* either side in each colour channel,
## over *size*, the same grain for the same *seed*.
func _noise(size: Vector2i, spread: float, seed_value: int) -> Image:
    var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBAF)
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value
    for y in size.y:
        for x in size.x:
            var grain := Color(
                0.5 + rng.randf_range(-spread, spread),
                0.5 + rng.randf_range(-spread, spread),
                0.5 + rng.randf_range(-spread, spread),
                1.0
            )
            image.set_pixel(x, y, grain)
    return image


func _distance(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


## The red channel's variance over the four by four texels round the centre.
func _variance(image: Image) -> float:
    var values: Array[float] = []
    for y in range(CENTRE.y - 2, CENTRE.y + 2):
        for x in range(CENTRE.x - 2, CENTRE.x + 2):
            values.append(image.get_pixel(x, y).r)
    var mean := 0.0
    for value in values:
        mean += value
    mean /= values.size()
    var sum := 0.0
    for value in values:
        sum += (value - mean) * (value - mean)
    return sum / values.size()


func test_the_filter_answers_the_numbers_it_was_handed() -> void:
    var denoise := WaveletDenoiseFilter.new()
    assert_eq(denoise.parameters(), {"levels": 4.0, "strength": 30.0}, "With no dialog it answers its defaults")
    denoise.set_parameters({"levels": 2, "strength": 80})
    assert_eq(denoise.parameters(), {"levels": 2.0, "strength": 80.0}, "and what it was handed")
    denoise.set_parameters({"radius": 9})
    assert_eq(denoise.parameters(), {"levels": 4.0, "strength": 30.0}, "and forgets the last record")


## A record's numbers reach the rows a dialog built, and through them the control
## each row draws, which is what a painter reads the number off. The order is the
## panel's and the editor's: `build`, then `set_parameters`, then the page is
## realized.
func test_a_records_numbers_reach_the_rows_and_their_controls() -> void:
    var denoise := WaveletDenoiseFilter.new()
    var dialog := SaDialog.for_filter(denoise)
    var host := VBoxContainer.new()
    denoise.set_parameters({"levels": 2, "strength": 80})
    dialog.realize(host)

    var levels := dialog.row(&"levels")
    assert_eq(float(levels.read()), 2.0, "The record's levels are on the row")
    assert_eq((levels.custom_control as FactorSlider).value, 2.0, "and on the control it built")
    var strength := dialog.row(&"strength")
    assert_eq(float(strength.read()), 80.0, "The record's strength is on the row")
    assert_eq((strength.custom_control as FactorSlider).value, 80.0, "and on the control it built")
    host.free()


func test_the_reach_is_the_cascade_support() -> void:
    assert_eq(WaveletDenoiseFilter.reach(1), 2, "One level reads two texels out")
    assert_eq(WaveletDenoiseFilter.reach(4), 30, "four read 30, as the page says")
    assert_eq(WaveletDenoiseFilter.reach(5), 62, "and five read 62, inside one ring of chunks")


func test_zero_strength_reconstructs_the_input_at_every_level_count() -> void:
    var image := _noise(Vector2i(SaChunk.SIZE, SaChunk.SIZE), 0.2, 7)
    # A stroke's edge against texels that are transparent and store green,
    # which an untouched texel must give back as it stored it.
    image.fill_rect(Rect2i(200, 0, 56, SaChunk.SIZE), Color(0.0, 1.0, 0.0, 0.0))
    image.fill_rect(Rect2i(180, 0, 20, SaChunk.SIZE), Color(0.9, 0.2, 0.1, 0.4))
    for levels in range(1, 6):
        var out := _one(image, {"levels": levels, "strength": 0})
        var worst := 0.0
        for probe: Vector2i in [CENTRE, Vector2i(0, 0), Vector2i(190, 40), Vector2i(199, 90), Vector2i(230, 128)]:
            worst = maxf(worst, _distance(out.get_pixelv(probe), image.get_pixelv(probe)))
        assert_true(worst < 1e-5, "%d levels at zero strength give the input back, worst %f" % [levels, worst])


func test_a_noisy_field_loses_more_than_half_its_variance() -> void:
    var image := _noise(Vector2i(SaChunk.SIZE, SaChunk.SIZE), 0.05, 11)
    var before := _variance(image)
    var after := _variance(_one(image, WaveletDenoiseFilter.DEFAULTS))
    assert_true(after < before * 0.5, "The default halves the grain at least, %f to %f" % [before, after])
    var mean := _one(image, WaveletDenoiseFilter.DEFAULTS).get_pixelv(CENTRE)
    assert_true(absf(mean.r - 0.5) < 0.05, "and leaves the field grey, %s" % mean)


## The two texels astride the edge keep their sides within a hundredth, and the
## texels a few out move a little more, 0.0163 at two out, where the coarse
## details that reach them are small beside their thresholds. A soft threshold,
## a first choice that was tried, moved the two astride by 0.056.
func test_a_hard_edge_keeps_both_its_sides() -> void:
    var image := Image.create(SaChunk.SIZE, SaChunk.SIZE, false, Image.FORMAT_RGBAF)
    image.fill(Color(0.0, 0.0, 0.0, 1.0))
    image.fill_rect(Rect2i(0, 0, CENTRE.x, SaChunk.SIZE), Color(1.0, 1.0, 1.0, 1.0))
    var out := _one(image, WaveletDenoiseFilter.DEFAULTS)
    for x in range(CENTRE.x - 40, CENTRE.x + 40):
        var want := Color(1.0, 1.0, 1.0, 1.0) if x < CENTRE.x else Color(0.0, 0.0, 0.0, 1.0)
        var got := out.get_pixel(x, CENTRE.y)
        var bound := 0.01 if x == CENTRE.x - 1 or x == CENTRE.x else 0.02
        assert_true(_distance(got, want) < bound, "The edge keeps its side at x %d, %s" % [x, got])


## The tile and overlap assertion. One grain over a document of four chunks,
## and the same grain cut to the middle of a document of one: the texels round
## the corner where the four meet, read from each of the four, equal the same
## texels read from the one chunk that holds them all in its interior.
func test_a_texel_is_the_same_over_one_chunk_or_four() -> void:
    var side := SaChunk.SIZE
    var grain := _noise(Vector2i(side * 2, side * 2), 0.1, 23)
    var four := {}
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
        four[grid_pos] = grain.get_region(Rect2i(grid_pos * side, Vector2i(side, side)))
    var shift := Vector2i(side >> 1, side >> 1)
    var one := grain.get_region(Rect2i(shift, Vector2i(side, side)))
    var tiled := _denoised(Vector2i(side * 2, side * 2), four, WaveletDenoiseFilter.DEFAULTS)
    var alone := _one(one, WaveletDenoiseFilter.DEFAULTS)
    var worst := 0.0
    var moved := 0.0
    for y in range(side - 4, side + 4):
        for x in range(side - 4, side + 4):
            var grid_pos := Vector2i(1 if x >= side else 0, 1 if y >= side else 0)
            var from_four: Color = (tiled[grid_pos] as Image).get_pixel(x - grid_pos.x * side, y - grid_pos.y * side)
            var from_one := alone.get_pixel(x - shift.x, y - shift.y)
            worst = maxf(worst, _distance(from_four, from_one))
            moved = maxf(moved, _distance(from_one, grain.get_pixel(x, y)))
    assert_true(moved > 0.01, "The run moved the texels it is compared on, %f" % moved)
    assert_true(worst < 1e-5, "and the four chunks agree with the one across the seams, worst %f" % worst)
