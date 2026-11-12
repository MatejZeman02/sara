## Lens Correction, Wobble, Drifting Noise and Add Noise's film grain on a
## layer at the document's density and on one at twice it: in a chunk of the
## second column and the second row, every document pixel at twice the density
## shows what it shows at the document's density, within a bound each test
## states.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The neighbourhood pass hands a kernel the chunk's corner in the chunk's own
## texels, 512 a chunk at twice the density, and these four kernels took it for
## document pixels, so every chunk but the top left one thought itself twice as
## far from the origin. Lens Correction then read past the padded source and
## went transparent towards the bottom and the right, Wobble's waves jumped at
## each seam and the two noises were laid at the wrong place. The pictures the
## readers are given are ramps written at every texel's document place, so a
## channel's value says where it was read from.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## Real dispatches into real chunks.
const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
## Three chunks across and two down.
const CANVAS := Vector2i(768, 512)
## The chunk measured, the second column of the second row, which the old
## arithmetic placed at (512, 512) at twice the density instead of (256, 256).
const BLOCK := Rect2i(Vector2i(256, 256), Vector2i(256, 256))
## How far a read place may stray between the two densities, in document
## pixels. A half float holds a ramp near one to about a third of a pixel of
## this canvas, and at twice the density a document pixel is the mean of four
## reads whose places a warp spreads by under a pixel.
const NEAR := 0.75
## Wobble's bound. Its kernel places a texel by its corner and not its centre,
## so at twice the density a document pixel is the mean of four corners a
## quarter pixel on from the one its own corner is at, and a wave of 20 px
## over 48 px bends by up to 2.6 px a pixel, which puts 0.65 px on the ramp's
## 0.75. The old arithmetic was out by 40 px here.
const WAVE_NEAR := 1.5
## How far a noise may differ between the two densities, as a share of the
## noise's own reach. At twice the density a document pixel is the mean of
## four samples a half pixel apart of a field whose features are many pixels
## across, so the field and its mean at a pixel stay close, where a field laid
## at the wrong place differs by its whole reach.
const NOISE_SHARE := 0.25
## Film grain's share. Its kernel places a texel by its corner, as Wobble's
## does, and its finer lattice is half the size across, 2 px at a size of 4,
## so the quarter pixel between the two densities' corners is an eighth of a
## clump. The old arithmetic was out by more than the grain's whole reach.
const GRAIN_SHARE := 0.35
## A flat grey for the noises to lay over.
const GREY := Color(0.5, 0.5, 0.5, 1.0)

var _easel: SaEasel = null


func after_each() -> void:
    _close()


func _close() -> void:
    if _easel != null:
        _easel.free()
    _easel = null


## Red holds the document place's x and green its y, each over the canvas.
static func _ramp(place: Vector2) -> Color:
    return Color(place.x / CANVAS.x, place.y / CANVAS.y, 0.5, 1.0)


static func _grey(_place: Vector2) -> Color:
    return GREY


static func _image_format(format: int) -> Image.Format:
    return Image.FORMAT_RGBAH if format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## The canvas composited with *filter* at *values* attached to a new layer at
## *scale*, every texel of which holds *picture* at its centre's document place.
func _attached(filter: SaFilter, values: Dictionary, scale: float, picture: Callable) -> Image:
    _close()
    _easel = SaEasel.create_default(CANVAS)
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var registry := SaFilterRegistry.new()
    registry.register(filter, OWNER)
    var key := SaFilterRegistry.key_for(OWNER, filter)
    _easel.compositor.filter_chain.registry = registry
    var doc := _easel.document
    doc.color_space = SaColorSpace.linear_srgb()
    var layer := SaLayerOps.new(doc).add(&"", null, scale)
    doc.active_layer = layer
    @warning_ignore("integer_division")
    var grid := Vector2i(CANVAS.x / SaChunk.SIZE, CANVAS.y / SaChunk.SIZE)
    for gy in grid.y:
        for gx in grid.x:
            var grid_pos := Vector2i(gx, gy)
            var chunk := layer.get_or_create_chunk(grid_pos)
            var texture := chunk.albedo()
            var side := chunk.pixel_size()
            var density := float(side) / SaChunk.SIZE
            var image := Image.create_empty(side, side, false, _image_format(texture.format))
            for y in side:
                for x in side:
                    var place := Vector2(grid_pos * SaChunk.SIZE) + (Vector2(x, y) + Vector2(0.5, 0.5)) / density
                    image.set_pixel(x, y, picture.call(place))
            GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
            layer.mark_unresolved(grid_pos)
    doc.invalidate_chunks(layer.chunks.keys())
    var record := SaFilterOps.new(doc).attach(layer, key, values)
    assert_not_null(record, "%s attaches at %.1f" % [filter.title(), scale])
    Bench.composite(_easel)
    var output := _easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(output.rid, 0)
    var seen := Image.create_from_data(output.size.x, output.size.y, false, _image_format(output.format), bytes)
    seen.convert(Image.FORMAT_RGBAF)
    return seen


## The widest distance between the places the two pictures read each pixel of
## [const BLOCK] from, with the pixel it is at, and the lowest alpha either
## shows there.
static func _read_places(once: Image, twice: Image) -> Dictionary:
    var worst := 0.0
    var at := Vector2i(-1, -1)
    var alpha := 1.0
    for y in range(BLOCK.position.y, BLOCK.end.y):
        for x in range(BLOCK.position.x, BLOCK.end.x):
            var a := once.get_pixel(x, y)
            var b := twice.get_pixel(x, y)
            alpha = minf(alpha, minf(a.a, b.a))
            var gap := Vector2((a.r - b.r) * CANVAS.x, (a.g - b.g) * CANVAS.y).length()
            if gap > worst:
                worst = gap
                at = Vector2i(x, y)
    return {"worst": worst, "at": at, "alpha": alpha}


## The widest difference in red between the two pictures over [const BLOCK],
## and the noise's reach there at the document's density, the widest red's
## distance from the grey under it.
static func _noise_gap(once: Image, twice: Image) -> Dictionary:
    var worst := 0.0
    var reach := 0.0
    for y in range(BLOCK.position.y, BLOCK.end.y):
        for x in range(BLOCK.position.x, BLOCK.end.x):
            var a := once.get_pixel(x, y)
            worst = maxf(worst, absf(a.r - twice.get_pixel(x, y).r))
            reach = maxf(reach, absf(a.r - GREY.r))
    return {"worst": worst, "reach": reach}


func _check_reader(filter_at: Callable, values: Dictionary, near: float) -> void:
    var once := _attached(filter_at.call() as SaFilter, values, 1.0, _ramp)
    var twice := _attached(filter_at.call() as SaFilter, values, 2.0, _ramp)
    var title := (filter_at.call() as SaFilter).title()
    var found := _read_places(once, twice)
    var words := "%s reads each pixel of the second column and row from one place at either density"
    words += ", within %.2f px, worst %.3f at %s"
    assert_true(float(found["worst"]) <= near, words % [title, near, found["worst"], found["at"]])
    assert_true(float(found["alpha"]) >= 0.99, "and leaves every pixel there painted, lowest alpha %.4f" % found["alpha"])


func _check_noise(filter_at: Callable, values: Dictionary, share: float) -> void:
    var once := _attached(filter_at.call() as SaFilter, values, 1.0, _grey)
    var twice := _attached(filter_at.call() as SaFilter, values, 2.0, _grey)
    var title := (filter_at.call() as SaFilter).title()
    var found := _noise_gap(once, twice)
    var reach := float(found["reach"])
    assert_true(reach > 0.02, "%s lays a noise that can be seen, reach %.4f" % [title, reach])
    var words := "%s lays the same noise over the second column and row at either density"
    words += ", within %.0f %% of its reach %.4f, worst %.4f"
    assert_true(float(found["worst"]) <= share * reach, words % [title, share * 100.0, reach, found["worst"]])


func test_lens_correction_reads_a_double_resolution_texel_from_its_document_place() -> void:
    _check_reader(SaLensCorrectionFilter.new, {"amount": 10.0}, NEAR)


func test_wobble_reads_a_double_resolution_texel_from_its_document_place() -> void:
    _check_reader(SaWobbleFilter.new, {"amplitude": 20.0, "wavelength": 48.0, "turbulence": 40.0}, WAVE_NEAR)


func test_drifting_noise_lays_its_field_at_the_document_place_at_either_density() -> void:
    _check_noise(SaDriftingNoiseFilter.new, {"amount": 40.0, "scale": 24.0}, NOISE_SHARE)


## Film grain's clumps are measured in document pixels, so a fixed seed and a
## size above one lay the same grain at either density.
func test_film_grain_lays_the_same_clumps_at_either_density() -> void:
    _check_noise(SaAddNoiseFilter.new, {"kind": "film_grain", "amount": 60.0, "size": 4.0, "seed": 7.0}, GRAIN_SHARE)
