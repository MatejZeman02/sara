## Add Noise at any seed of its range: White and Salt and pepper draw rows that
## owe nothing to the rows before them, Film grain is as smooth across the edge
## of a lattice cell as inside one, and a seed still draws one picture however
## the dispatch is cut. A draw that hashes floats fed the seed in the sum kept a
## hundredth of a pixel past a seed of about 3000, so rows 97 apart drew alike,
## and a corner two cells share rounded two ways, a step at every edge.
extends "res://tests/test_framework.gd"

const AddNoiseFilter = preload("res://modules/sara-base-modules/base/usual/add_noise_filter.gd")

const REQUIRES_GPU := true

const MODULE_ID: StringName = &"sara-base-modules"
const MODULE_DIR := "res://modules/sara-base-modules/base"
const GREY := Color(0.5, 0.5, 0.5, 1.0)
const GRID := Vector2i(0, 0)
const SEEDS: Array[float] = [1.0, 3000.0, 9999.0]
const LAGS := 128
## Every column. Every other one halved the time and left chance spread
## near enough to the bound that salt and pepper at seed 3000 read 0.027.
const COLUMN_STEP := 1
## The largest correlation between rows at any lag from 1 to 128 that a seed
## may show. Seed 1 read 0.0145 at most under White and 0.0134 under Salt and
## pepper, chance over 128 lags of 33,000 to 65,000 pairs each, and the 97 row
## repeat read 0.64 to 0.82, so a bound of about twice seed 1's own holds chance
## and fails the repeat by twenty times over.
const ROW_CORRELATION_BOUND := 0.03
## Film grain's lattice cell, in document pixels.
const GRAIN_SIZE := 16
## How much the largest step between two rows across a cell edge may pass the
## largest inside a cell. The integer lattice read 0.040 to 0.044 across an
## edge against 0.071 to 0.084 inside, as the smoothstep that flattens a cell's
## value towards its edge would have it, and the float hash 0.41 to 0.48 across
## against 0.18 to 0.26 inside.
const EDGE_STEP_SLACK := 0.01

var _easel: SaEasel = null
var _layer: SaLayer = null


func before_each() -> void:
    if not ModuleLoader.module_dirs.has(MODULE_ID):
        ModuleLoader.module_dirs[MODULE_ID] = MODULE_DIR
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE, SaChunk.SIZE))
    _layer = _easel.document.active_layer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    _layer.get_or_create_chunk(GRID).clear(GREY)


func after_each() -> void:
    _layer = null
    _easel.free()
    _easel = null


func _context(values: Dictionary) -> SaFilterContext:
    var filter := AddNoiseFilter.new()
    filter.set_parameters(values)
    var ctx := SaFilterContext.new(_easel.document, _layer, MODULE_ID, "Add Noise")
    filter.run(ctx)
    return ctx


## The red channel of the chunk after *values* is applied, row by row, and the
## document as it was again.
func _applied(values: Dictionary) -> PackedFloat32Array:
    assert_true(SaFilterApply.apply(_context(values), "Add Noise"), "%s applies" % values)
    var reds := _reds(_layer.get_field(GRID))
    _easel.document.undo()
    return reds


func _reds(texture: SaTexture) -> PackedFloat32Array:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out := PackedFloat32Array()
    out.resize(texture.size.x * texture.size.y)
    for i in out.size():
        out[i] = SaFieldSpec.decode_texel(bytes, texture.format, i).r
    return out


## The largest Pearson correlation, by its size, between the texel at (x, y)
## and the texel at (x, y + lag) over the chunk, for every lag from 1 to LAGS.
static func _largest_row_correlation(reds: PackedFloat32Array) -> float:
    var side := SaChunk.SIZE
    var mean := 0.0
    for v in reds:
        mean += v
    mean /= float(reds.size())
    var centred := PackedFloat32Array()
    centred.resize(reds.size())
    var spread := 0.0
    for i in reds.size():
        centred[i] = reds[i] - mean
        spread += centred[i] * centred[i]
    spread /= float(reds.size())
    var most := 0.0
    for lag in range(1, LAGS + 1):
        var sum := 0.0
        var pairs := 0
        for y in side - lag:
            var row := y * side
            var below := (y + lag) * side
            for x in range(0, side, COLUMN_STEP):
                sum += centred[row + x] * centred[below + x]
            @warning_ignore("integer_division")
            pairs += side / COLUMN_STEP
        most = maxf(most, absf(sum / float(pairs) / spread))
    return most


func _assert_no_row_correlation(kind: String, amount: float) -> void:
    for grain_seed: float in SEEDS:
        var values := {"kind": kind, "monochrome": true, "amount": amount, "seed": grain_seed}
        var most := _largest_row_correlation(_applied(values))
        print("    %s at seed %d: the largest correlation between rows is %.4f" % [kind, grain_seed, most])
        assert_true(
            most < ROW_CORRELATION_BOUND,
            "%s at seed %d correlates rows by %.4f at most, under %.2f" % [kind, grain_seed, most, ROW_CORRELATION_BOUND]
        )


func test_white_noise_draws_rows_that_never_repeat_at_any_seed() -> void:
    _assert_no_row_correlation("white", 20.0)


func test_salt_and_pepper_draws_rows_that_never_repeat_at_any_seed() -> void:
    _assert_no_row_correlation("salt_and_pepper", 50.0)


## Film grain at Size 16: the largest step between two neighbouring rows where
## they straddle a cell edge, against the largest where both are in one cell.
func test_film_grain_steps_no_more_at_a_cell_edge_than_inside_a_cell() -> void:
    var side := SaChunk.SIZE
    for grain_seed: float in SEEDS:
        var values := {"kind": "film_grain", "monochrome": true, "amount": 100.0, "size": float(GRAIN_SIZE), "seed": grain_seed}
        var reds := _applied(values)
        var at_edge := 0.0
        var inside := 0.0
        for y in side - 1:
            var step := 0.0
            for x in side:
                step = maxf(step, absf(reds[(y + 1) * side + x] - reds[y * side + x]))
            if (y + 1) % GRAIN_SIZE == 0:
                at_edge = maxf(at_edge, step)
            else:
                inside = maxf(inside, step)
        print("    film grain at seed %d: %.4f across an edge, %.4f inside a cell" % [grain_seed, at_edge, inside])
        assert_true(inside > 0.0, "Film grain at seed %d moved the texels" % grain_seed)
        assert_true(
            at_edge <= inside + EDGE_STEP_SLACK,
            "Film grain at seed %d steps %.4f across a cell edge against %.4f inside a cell" % [grain_seed, at_edge, inside]
        )


func test_one_seed_paints_the_same_pixels_twice_and_however_the_dispatch_is_cut() -> void:
    for kind: String in AddNoiseFilter.KINDS:
        var values := {"kind": kind, "monochrome": false, "amount": 60.0, "size": float(GRAIN_SIZE), "seed": 9999.0}
        assert_eq(_applied(values), _applied(values), "%s at seed 9999 paints the same pixels in two applications" % kind)
        var ctx := _context(values)
        var recorded := ctx.point as SaNeighbourhoodPass
        var compute := ctx.kernel(recorded.shader)
        var runner := SaNeighbourhoodPass.Runner.new()
        var source := _layer.get_field(GRID)
        var mask := _easel.document.selection.texture_for(GRID)
        var whole := SaTexture.new(Vector2i(SaChunk.SIZE, SaChunk.SIZE), source.format)
        var split := SaTexture.new(whole.size, whole.format)
        runner.run(recorded, compute, whole, source, _layer.get_field, GRID, Rect2i(0, 0, 256, 256), mask)
        runner.run(recorded, compute, split, source, _layer.get_field, GRID, Rect2i(0, 0, 256, 97), mask)
        runner.run(recorded, compute, split, source, _layer.get_field, GRID, Rect2i(0, 97, 256, 159), mask)
        var from_whole := _reds(whole)
        assert_eq(_reds(split), from_whole, "%s split into two rectangles paints what one dispatch does" % kind)
        assert_true(from_whole[200 * SaChunk.SIZE + 13] != GREY.r, "and %s is noise" % kind)
