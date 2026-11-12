## A Drifting Noise filter moves with its time.
##
## The filter adds a value noise to the layer at the time its record holds,
## the time the filter's time row plays and scrubs. Over a grey layer two chunks wide, this
## runs it one-shot as Apply does at times nought and one and reads two
## pictures, at one twice and reads the same bytes, and at a speed of nought
## and reads the picture at nought whatever the time. It reads the noise moved
## along the direction the painter set, across the seam between the chunks,
## the attached record redrawn by a write of its time, and the time row in the
## filter's dialog. The running app's half is
## `scenarios/a-drifting-noise-filter-moves-with-its-time.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const MODULE_ID: StringName = &"sara-base-modules"
const MODULE_DIR := "res://modules/sara-base-modules/base"
const KEY: StringName = &"sara-base-modules.drifting_noise"
const GREY := Color(0.5, 0.5, 0.5, 1.0)
## Two chunks side by side, so a drift is read across the seam between them.
const GRIDS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
## How far a second of the drift test carries the field, in document pixels.
const SHIFT := 32
## Rows the drift is read along, in both chunks.
const ROWS: Array[int] = [40, 101, 170, 210]

var _easel: SaEasel = null
var _layer: SaLayer = null


func before_each() -> void:
    if not ModuleLoader.module_dirs.has(MODULE_ID):
        ModuleLoader.module_dirs[MODULE_ID] = MODULE_DIR
    _easel = SaEasel.create_default(Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE))
    _layer = _easel.document.active_layer
    _grey()


func after_each() -> void:
    _layer = null
    _easel.free()
    _easel = null


## The layer as it stands before every run: the two chunks grey and opaque,
## and nothing else.
func _grey() -> void:
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    for grid_pos in GRIDS:
        _layer.get_or_create_chunk(grid_pos).clear(GREY)


func _values(seconds: float, speed: float = 24.0, direction: float = 0.0) -> Dictionary:
    return {"amount": 100.0, "scale": 32.0, "speed": speed, "direction": direction, "t": seconds}


## Runs the filter one-shot with *values* over a grey layer, as Apply does, and
## answers the bytes of both chunks, the first then the second.
func _picture(values: Dictionary) -> Array[PackedByteArray]:
    _grey()
    var filter := SaDriftingNoiseFilter.new()
    filter.set_parameters(values)
    var ctx := SaFilterContext.new(_easel.document, _layer, MODULE_ID, "Drifting Noise")
    filter.run(ctx)
    assert_true(SaFilterApply.apply(ctx, "Drifting Noise"), "Drifting Noise applies at %s" % values)
    var out: Array[PackedByteArray] = []
    for grid_pos in GRIDS:
        var texture := (_layer.chunks[grid_pos] as SaChunk).field(SaFieldSpec.ALBEDO)
        out.append(GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0))
    return out


## The red of the document pixel *x*, *y* in *picture*, the two chunks read
## as one strip.
func _red(picture: Array[PackedByteArray], x: int, y: int) -> float:
    var chunk := _layer.chunks[GRIDS[0]] as SaChunk
    var side := chunk.pixel_size()
    var texture := chunk.field(SaFieldSpec.ALBEDO)
    return SaFieldSpec.decode_texel(picture[floori(float(x) / float(side))], texture.format, y * side + x % side).r


## The red of every texel of *picture* on [const ROWS] and on the rows
## [const SHIFT] above and below them, by document pixel.
func _rows(picture: Array[PackedByteArray]) -> Dictionary[Vector2i, float]:
    var out: Dictionary[Vector2i, float] = {}
    for row in ROWS:
        for y: int in [row - SHIFT, row, row + SHIFT]:
            for x in GRIDS.size() * SaChunk.SIZE:
                out[Vector2i(x, y)] = _red(picture, x, y)
    return out


## The mean gap between *later* and *earlier* read *offset* back, over every
## texel of [const ROWS] whose earlier one is on the strip.
static func _gap(later: Dictionary[Vector2i, float], earlier: Dictionary[Vector2i, float], offset: Vector2i) -> float:
    var total := 0.0
    var count := 0
    for at: Vector2i in later:
        if ROWS.has(at.y) and earlier.has(at - offset):
            total += absf(later[at] - earlier[at - offset])
            count += 1
    return total / maxf(float(count), 1.0)


func test_times_nought_and_one_are_two_pictures() -> void:
    var nought := _picture(_values(0.0))
    var one := _picture(_values(1.0))
    var rows := _rows(nought)
    var widest := 0.0
    for at: Vector2i in rows:
        widest = maxf(widest, absf(rows[at] - GREY.r))
    assert_true(widest > 0.2, "The filter added a noise to the grey, %s at most" % widest)
    var moved := 0
    var later := _rows(one)
    for at: Vector2i in rows:
        if absf(later[at] - rows[at]) > 1e-3:
            moved += 1
    assert_true(moved * 10 > rows.size() * 9, "and a second on, %d of %d texels are another value" % [moved, rows.size()])
    assert_true(nought[0] != one[0], "so the first chunk is another picture")
    assert_true(nought[1] != one[1], "and so is the second")


func test_the_same_time_gives_the_same_texels() -> void:
    var first := _picture(_values(1.0))
    var second := _picture(_values(1.0))
    assert_eq(first[0], second[0], "Two runs at one second write the same bytes in the first chunk")
    assert_eq(first[1], second[1], "and in the second")
    var late := _picture(_values(1234.5))
    var again := _picture(_values(1234.5))
    assert_eq(late[0], again[0], "and so do two at twenty minutes, frame n as frame one")


func test_at_a_speed_of_nought_every_time_is_the_picture_at_nought() -> void:
    var nought := _picture(_values(0.0))
    for seconds: float in [1.0, 2.0, 600.0]:
        var still := _picture(_values(seconds, 0.0))
        assert_eq(still[0], nought[0], "At a speed of nought, %s seconds is the picture at nought" % seconds)
        assert_eq(still[1], nought[1], "in both chunks")


## A second at [const SHIFT] pixels a second carries the field that far, so the
## picture at one is the picture at nought moved along the direction, give or
## take what turned over, and much nearer it than the picture standing still or
## moved the other way.
func test_the_noise_drifts_along_its_direction() -> void:
    var speed := float(SHIFT)
    var nought := _rows(_picture(_values(0.0, speed)))
    var right := _rows(_picture(_values(1.0, speed, 0.0)))
    var along := _gap(right, nought, Vector2i(SHIFT, 0))
    var still := _gap(right, nought, Vector2i.ZERO)
    var back := _gap(right, nought, Vector2i(-SHIFT, 0))
    assert_true(along * 2.0 < still, "Rightwards, the field moved right: %f against %f standing still" % [along, still])
    assert_true(along * 2.0 < back, "and %f against %f moved left" % [along, back])
    var up := _rows(_picture(_values(1.0, speed, 90.0)))
    var raised := _gap(up, nought, Vector2i(0, -SHIFT))
    var lowered := _gap(up, nought, Vector2i(0, SHIFT))
    assert_true(raised * 2.0 < _gap(up, nought, Vector2i.ZERO), "At ninety degrees it moved up, %f" % raised)
    assert_true(raised * 2.0 < lowered, "and not down, %f" % lowered)


## Every frame is the same pass: one kernel over the dirty rectangle with no
## halo, its time a number in the params, whatever the time.
func test_frame_n_is_the_pass_frame_one_is() -> void:
    var passes: Array[SaNeighbourhoodPass] = []
    for seconds: float in [0.0, 3000.0]:
        var filter := SaDriftingNoiseFilter.new()
        filter.set_parameters(_values(seconds))
        var ctx := SaFilterContext.new(_easel.document, _layer, MODULE_ID, "Drifting Noise")
        filter.run(ctx)
        passes.append(ctx.point as SaNeighbourhoodPass)
    assert_not_null(passes[0], "The run records a pass the neighbourhood runner takes")
    if passes[0] == null or passes[1] == null:
        return
    assert_eq(passes[1].steps.size(), passes[0].steps.size(), "At fifty minutes the pass has the steps it had at nought")
    assert_eq(passes[0].radius, 0, "and reads no neighbour")
    assert_eq(passes[1].radius, 0, "at either time")
    assert_almost_eq(float(passes[1].params["seconds"]), 3000.0, 1e-3, "and the time is the one number that moved")


func test_an_unpainted_texel_stays_empty() -> void:
    _grey()
    _layer.get_or_create_chunk(GRIDS[1]).clear(Color(0.0, 0.0, 0.0, 0.0))
    var filter := SaDriftingNoiseFilter.new()
    filter.set_parameters(_values(1.0))
    var ctx := SaFilterContext.new(_easel.document, _layer, MODULE_ID, "Drifting Noise")
    filter.run(ctx)
    assert_true(SaFilterApply.apply(ctx, "Drifting Noise"), "Drifting Noise applies")
    var texture := (_layer.chunks[GRIDS[1]] as SaChunk).field(SaFieldSpec.ALBEDO)
    for at: Vector2i in [Vector2i(0, 0), Vector2i(77, 140), Vector2i(255, 255)]:
        assert_eq(Bench.texel(texture, at), Color(0.0, 0.0, 0.0, 0.0), "Transparent stays transparent at %s" % at)


## An attached record is redrawn at the time a write gives it, the write the
## time row's play and scrub make through the panel.
func test_the_attached_record_redraws_at_its_time() -> void:
    _easel.compositor.set_registry(Bench.Fixtures.make_registries().blend_modes)
    var filters := SaFilterRegistry.new()
    filters.register(SaDriftingNoiseFilter.new(), MODULE_ID)
    _easel.compositor.filter_chain.registry = filters
    var record := SaFilterOps.new(_easel.document).attach(_layer, KEY, _values(0.0))
    var at := Vector2i(300, 60)
    Bench.composite(_easel)
    var nought := Bench.texel(_easel.output, at)
    assert_true(absf(nought.r - GREY.r) > 1e-4 or absf(nought.g - GREY.g) > 1e-4, "The attached noise shows: %s" % nought)
    SaFilterOps.new(_easel.document).set_parameters(record, _values(2.0))
    Bench.composite(_easel)
    var two := Bench.texel(_easel.output, at)
    assert_true(two != nought, "Two seconds on the composite is another picture: %s against %s" % [two, nought])
    SaFilterOps.new(_easel.document).set_parameters(record, _values(0.0))
    Bench.composite(_easel)
    assert_eq(Bench.texel(_easel.output, at), nought, "and back at nought it is the first again")


func test_the_dialog_shows_the_time_row_and_a_scrub_moves_the_time() -> void:
    var filter := SaDriftingNoiseFilter.new()
    var dialog := SaDialog.for_filter(filter)
    var page := VBoxContainer.new()
    dialog.realize(page)
    var scrubber := page.find_child(SaTimeRow.Scrubber.NODE_NAME, true, false) as SaTimeRow.Scrubber
    assert_not_null(scrubber, "The dialog holds the time row's scrubber")
    if scrubber != null:
        assert_not_null(scrubber.find_child("TimePlay", true, false), "with its play button")
        scrubber.slider.set_value_no_signal(2.0)
        scrubber.slider.value_changed.emit(2.0)
        dialog.flush_rerun()
        assert_almost_eq(SaTyped.real(filter.parameter(SaTimeRow.KEY)), 2.0, 1e-6, "and scrubbing to two sets the time to two")
    for key: StringName in [&"amount", &"scale", &"speed", &"direction"]:
        assert_eq(dialog.widget_name(key), "slider", "%s is a slider row" % key)
    page.free()
