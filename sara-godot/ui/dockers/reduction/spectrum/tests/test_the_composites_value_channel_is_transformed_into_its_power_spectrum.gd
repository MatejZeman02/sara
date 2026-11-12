## The composite's value channel is transformed on the GPU into its power
## spectrum.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The three cases, each over a real easel, a real composite and the
## real kernels. Vertical stripes of a known period read their peak at that
## frequency on the horizontal axis and the radial average's at that scale, a
## flat colour reads all its power at the zero frequency, and a small random
## picture reads the spectrum the suite works out itself on the CPU in doubles,
## to within a part in a thousand. Then the schedule: a stroke held open beside
## a reduction that sets the per-frame pace, as the graph docker's pass does,
## and the transform waits for the idle clock to fire after the stroke closes.
##
## The suite builds a service and a clock of its own, as the service's suite
## does, so a frame is a call to `tick` and seconds pass in the clock's `tick`.
extends "res://tests/test_framework.gd"

## Real composites and real kernels over them.
const REQUIRES_GPU := true

## Two chunks by two, so the square is 256 texels of two document pixels each.
const SIZE := Vector2i(512, 512)

## The stripes' period in document pixels, half white and half black.
const PERIOD := 32

## A frame at sixty a second, in milliseconds.
const FRAME_MSEC := 16

## The random picture's side, a canvas the square covers texel for texel.
const SMALL := 32

## A part in a thousand.
const TOLERANCE := 1e-3

var _easel: SaEasel = null
var _clock: SaIdleClock = null
var _service: SaReductionService = null


func after_each() -> void:
    if _service != null:
        _service.free()
    if _clock != null:
        _clock.free()
    if _easel != null:
        _easel.free()
    _service = null
    _clock = null
    _easel = null


## An easel of *size* in *space*, sRGB at floats when null, a clock watching
## its document and a service deciding by both, as the service's own suite
## builds them.
func _build(size: Vector2i, space: SaColorSpace = null) -> void:
    _easel = SaEasel.create_default(size, null, space)
    _easel.process_pending_composite()
    _clock = SaIdleClock.new()
    _clock.follow_settings = false
    _clock.follow_main = false
    _clock.idle_seconds = 5.0
    _clock.attach(_easel.document)
    _service = SaReductionService.new()
    _service.watch(_easel)
    _service.listen(_clock)


func _spectrum() -> SaPowerSpectrum:
    var spectrum := SaPowerSpectrum.new(_clock)
    spectrum.read_at_once = true
    return spectrum


## Fires the clock as the painter stopping after an edit does.
func _stop() -> bool:
    _clock.note_edit()
    return _clock.tick(_clock.idle_seconds)


## Writes *texels*, RGBA floats row by row over the whole chunk, into the paint
## layer's chunk at *grid_pos* and tells the document, as a dab inside it would.
func _upload(grid_pos: Vector2i, texels: PackedFloat32Array) -> void:
    var document := _easel.document
    var chunk := document.active_layer.get_or_create_chunk(grid_pos)
    var albedo := chunk.albedo()
    assert_eq(albedo.format, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, "The default document stores floats")
    GlobalShaderCompiler.get_rd().texture_update(albedo.rid, 0, texels.to_byte_array())
    document.invalidate_chunk_regions({grid_pos: Rect2i(Vector2i.ZERO, Vector2i.ONE * chunk.pixel_size())})


## Vertical stripes over every chunk of the canvas, white for the first half of
## each period and black for the second, by the document's own x.
func _paint_stripes() -> void:
    for grid_pos: Vector2i in SaLayer.grid_positions(SIZE):
        var side := _easel.document.active_layer.get_or_create_chunk(grid_pos).pixel_size()
        var row := PackedFloat32Array()
        for x in side:
            var lit := 1.0 if 2 * posmod(grid_pos.x * side + x, PERIOD) < PERIOD else 0.0
            row.append_array(PackedFloat32Array([lit, lit, lit, 1.0]))
        var texels := PackedFloat32Array()
        for y in side:
            texels.append_array(row)
        _upload(grid_pos, texels)


## Oklab L of a colour *stored* in the easel's document, worked on the CPU.
func _lightness(stored: Color) -> float:
    var space := _easel.document.color_space
    var curve := space.transfer
    var linear := Vector3(curve.decode(stored.r), curve.decode(stored.g), curve.decode(stored.b))
    return SaOklab.from_linear_srgb(space.to_linear_srgb_matrix() * linear).x * stored.a


## The whole spectrum's power outside the zero frequency, each column of the
## half standing for itself and its mirror.
static func _power_beside_zero(spectrum: SaPowerSpectrum) -> float:
    var rest := 0.0
    var columns := SaPowerSpectrum.columns_for(spectrum.side)
    for v in spectrum.side:
        for u in columns:
            if u == 0 and v == 0:
                continue
            rest += spectrum.power[v * columns + u] * (1.0 if u == 0 or u == columns - 1 else 2.0)
    return rest


func test_vertical_stripes_peak_at_their_frequency_across_and_at_their_scale_in_the_rings() -> void:
    _build(SIZE)
    var spectrum := _spectrum()
    _service.add(spectrum)
    _paint_stripes()
    assert_true(_stop(), "The clock fires")
    assert_eq(spectrum.transforms, 1, "and the spectrum is transformed once")
    assert_eq(spectrum.side, 256, "over a square of 256 texels")
    assert_almost_eq(spectrum.document_pixels_per_texel, 2.0, 1e-6, "each two document pixels across")

    var peak := Vector2i(-1, -1)
    var most := -1.0
    var columns := SaPowerSpectrum.columns_for(spectrum.side)
    for v in spectrum.side:
        for u in columns:
            if (u != 0 or v != 0) and spectrum.power[v * columns + u] > most:
                most = spectrum.power[v * columns + u]
                peak = Vector2i(u, v)
    var across := roundi(float(SIZE.x) / float(PERIOD))
    assert_eq(peak, Vector2i(across, 0), "The power peaks %d cycles across and none down, at %s" % [across, peak])
    # A row of 8 white texels and 8 black: its first harmonic's amplitude is
    # 1 / (16 sin(pi / 16)), and the power is that squared.
    var expected := pow(1.0 / (16.0 * sin(PI / 16.0)), 2.0)
    assert_almost_eq(most, expected, expected * TOLERANCE, "at the square wave's first harmonic, %f" % most)
    assert_almost_eq(spectrum.power_at(-across, 0), most, 1e-9, "and its mirror reads the same")

    var ring := -1
    var loudest := -1.0
    for r in range(1, spectrum.radial.size()):
        if spectrum.radial[r] > loudest:
            loudest = spectrum.radial[r]
            ring = r
    assert_eq(ring, across, "The radial average peaks at ring %d" % ring)
    assert_almost_eq(spectrum.period_of(ring), float(PERIOD), 1e-6, "which is a period of %d document pixels" % PERIOD)
    _service.leave(spectrum)


func test_a_flat_colour_puts_all_its_power_at_the_zero_frequency() -> void:
    _build(SIZE)
    var spectrum := _spectrum()
    _service.add(spectrum)
    var grey := Color(0.5, 0.5, 0.5, 1.0)
    _easel.document.fill_layer(grey)
    assert_true(_stop(), "The clock fires")
    assert_eq(spectrum.transforms, 1, "and the spectrum is transformed")
    var lightness := _lightness(grey)
    var zero := spectrum.power_at(0, 0)
    assert_almost_eq(zero, lightness * lightness, lightness * lightness * TOLERANCE, "The zero frequency is L squared, %f" % zero)
    var rest := _power_beside_zero(spectrum)
    assert_true(rest <= zero * 1e-9, "and every other frequency together holds %s of it" % (rest / zero))
    assert_almost_eq(spectrum.radial[0], zero, 1e-9, "The first ring is the zero frequency alone")

    assert_true(_stop(), "The clock fires again with nothing painted")
    assert_eq(spectrum.transforms, 1, "and the picture already read is not transformed again")
    _service.leave(spectrum)


func test_the_apps_own_space_is_read_in_its_oklab_coordinates_at_half_floats() -> void:
    var space := SaEasel.default_space()
    assert_eq(space.coordinates, SaColorSpace.Coordinates.OKLAB, "The app paints in Oklab")
    _build(SIZE, space)
    assert_eq(_easel.output.format, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, "and composites at half floats")
    var spectrum := _spectrum()
    _service.add(spectrum)
    var stored := space.from_display(Color(0.3, 0.6, 0.2, 1.0))
    _easel.document.fill_layer(Color(0.3, 0.6, 0.2, 1.0))
    assert_true(_stop(), "The clock fires")
    assert_eq(spectrum.transforms, 1, "and the spectrum is transformed")
    # The stored lightness is the triple's first, as the composite holds it.
    var half := PackedByteArray()
    half.resize(2)
    half.encode_half(0, stored.r)
    var lightness := half.decode_half(0)
    var zero := spectrum.power_at(0, 0)
    assert_almost_eq(zero, lightness * lightness, lightness * lightness * TOLERANCE, "The zero frequency is L squared, %f" % zero)
    var rest := _power_beside_zero(spectrum)
    assert_true(rest <= zero * 1e-9, "and every other frequency together holds %s of it" % (rest / zero))
    _service.leave(spectrum)


func test_a_canvas_wider_than_tall_is_reflected_into_its_square_and_a_flat_colour_stays_flat() -> void:
    _build(Vector2i(SIZE.x, SIZE.y >> 2))
    var spectrum := _spectrum()
    _service.add(spectrum)
    _easel.document.fill_layer(Color(0.8, 0.2, 0.1, 1.0))
    assert_true(_stop(), "The clock fires")
    assert_eq(spectrum.side, 256, "The square is as wide as the canvas")
    assert_eq(
        SaPowerSpectrum.square_over(_easel.document.canvas_size), Rect2(0, -192, 512, 512), "and overhangs it above and below"
    )
    var zero := spectrum.power_at(0, 0)
    var rest := _power_beside_zero(spectrum)
    assert_true(
        zero > 0.0 and rest <= zero * 1e-9, "The reflection adds no edge, %s of the power off the zero frequency" % (rest / zero)
    )
    _service.leave(spectrum)


func test_a_small_random_picture_reads_the_spectrum_worked_on_the_cpu() -> void:
    _build(Vector2i(SMALL, SMALL))
    var spectrum := _spectrum()
    _service.add(spectrum)
    var side := _easel.document.active_layer.get_or_create_chunk(Vector2i.ZERO).pixel_size()
    var random := RandomNumberGenerator.new()
    random.seed = 43
    var texels := PackedFloat32Array()
    for y in side:
        for x in side:
            texels.append_array(PackedFloat32Array([random.randf(), random.randf(), random.randf(), 1.0]))
    _upload(Vector2i.ZERO, texels)
    assert_true(_stop(), "The clock fires")
    assert_eq(spectrum.side, SMALL, "The square is the canvas, texel for texel")

    # The lightness of the texels the canvas shows, from the floats the GPU
    # was handed, and the real transform along the rows and the complex one
    # down the columns, in doubles. A coefficient is its real part and then
    # its imaginary one, because a Vector2 holds floats.
    var columns := SaPowerSpectrum.columns_for(SMALL)
    var rows: Array[PackedFloat64Array] = []
    for y in SMALL:
        var row := PackedFloat64Array()
        row.resize(2 * columns)
        row.fill(0.0)
        for x in SMALL:
            var at := (y * side + x) * 4
            var value := _lightness(Color(texels[at], texels[at + 1], texels[at + 2], texels[at + 3]))
            for u in columns:
                var angle := -TAU * float(u * x) / float(SMALL)
                row[2 * u] += cos(angle) * value
                row[2 * u + 1] += sin(angle) * value
        rows.append(row)
    var worst := 0.0
    var cpu_power := PackedFloat64Array()
    cpu_power.resize(columns * SMALL)
    for u in columns:
        for v in SMALL:
            var real := 0.0
            var imaginary := 0.0
            for y in SMALL:
                var angle := -TAU * float(v * y) / float(SMALL)
                var z_real := rows[y][2 * u]
                var z_imaginary := rows[y][2 * u + 1]
                real += z_real * cos(angle) - z_imaginary * sin(angle)
                imaginary += z_real * sin(angle) + z_imaginary * cos(angle)
            real /= float(SMALL * SMALL)
            imaginary /= float(SMALL * SMALL)
            var worked := real * real + imaginary * imaginary
            cpu_power[v * columns + u] = worked
            worst = maxf(worst, absf(spectrum.power[v * columns + u] - worked) / worked)
    assert_true(worst <= TOLERANCE, "Every coefficient's power is the CPU's to a part in a thousand, the worst %s off" % worst)

    var worst_ring := 0.0
    for ring in columns:
        var sum := 0.0
        var weight := 0.0
        for v in SMALL:
            for u in columns:
                var down := v if 2 * v < SMALL else v - SMALL
                if roundi(sqrt(float(u * u + down * down))) != ring:
                    continue
                var counts := 1.0 if u == 0 or u == columns - 1 else 2.0
                sum += counts * cpu_power[v * columns + u]
                weight += counts
        var mean := sum / weight
        worst_ring = maxf(worst_ring, absf(spectrum.radial[ring] - mean) / mean)
    assert_true(worst_ring <= TOLERANCE, "and every ring's mean is too, the worst %s off" % worst_ring)
    _service.leave(spectrum)


func test_a_stroke_held_open_beside_the_graphs_pace_waits_for_the_clock_after_it_closes() -> void:
    _build(SIZE)
    var paced := SaReductionService.Reduction.new(true)
    var spectrum := _spectrum()
    _service.add(paced)
    _service.add(spectrum)
    var now := 1000
    assert_true(_service.tick(now), "With the graph open the service runs every reduction")
    assert_eq(spectrum.runs, 1, "the spectrum's among them")
    assert_eq(spectrum.transforms, 0, "and it transforms nothing while the painter has not stopped")
    assert_true(_clock.tick(_clock.idle_seconds), "The clock fires")
    now += FRAME_MSEC
    assert_true(_service.tick(now), "and the spectrum asks the service for a run")
    assert_eq(spectrum.transforms, 1, "which transforms the picture")

    var document := _easel.document
    document.stroke_transaction.direct_paint = true
    for frame in 12:
        document.fill_layer(Color(float(frame) / 12.0, 0.3, 0.6, 1.0))
        _easel.process_pending_composite()
        now += FRAME_MSEC
        _service.tick(now)
    assert_true(paced.runs > 2, "The graph's pass kept running through the stroke, %d runs" % paced.runs)
    assert_eq(spectrum.transforms, 1, "and the spectrum did not, before the clock heard the stroke")
    assert_false(_clock.tick(30.0), "Half a minute with the stroke open and the clock stays quiet")
    now += FRAME_MSEC
    spectrum.stale()
    _service.tick(now)
    assert_eq(spectrum.transforms, 1, "and a run asked for then transforms nothing")

    document.stroke_transaction.direct_paint = false
    for frame in 4:
        now += FRAME_MSEC
        spectrum.stale()
        _service.tick(now)
    assert_false(_clock.tick(4.0), "With the stroke closed the clock waits its five seconds")
    now += FRAME_MSEC
    spectrum.stale()
    _service.tick(now)
    assert_eq(spectrum.transforms, 1, "and nothing is transformed before they are up")
    assert_true(_clock.tick(1.0), "Then the clock fires")
    now += FRAME_MSEC
    _service.tick(now)
    assert_eq(spectrum.transforms, 2, "and the next frame transforms the picture the stroke left")
    _service.leave(spectrum)
    _service.leave(paced)


func test_the_answer_comes_back_on_a_later_frame() -> void:
    _build(SIZE)
    var spectrum := SaPowerSpectrum.new(_clock)
    _service.add(spectrum)
    var heard: Array[int] = []
    spectrum.arrived.connect(func() -> void: heard.append(1))
    _paint_stripes()
    assert_true(GlobalShaderCompiler.get_rd() == RenderingServer.get_rendering_device(), "The suites run on the main device")
    assert_true(_stop(), "The clock fires")
    assert_eq(spectrum.waiting, 1, "The transform asked the device for its answer")
    assert_true(heard.is_empty() and spectrum.power.is_empty(), "and returned without waiting for it")
    var loop := Engine.get_main_loop() as SceneTree
    assert_true(
        loop.process_frame.is_connected(spectrum.draw_while_owed), "While the answer is owed it hears every turn of the loop"
    )
    # A suite runs in one frame and draws none, as an idle window in low
    # processor mode draws none, so each call here is a turn that drew nothing.
    var turns := 0
    while spectrum.waiting > 0 and turns < 8:
        spectrum.draw_while_owed()
        turns += 1
    assert_eq(spectrum.waiting, 0, "The frames it drew had the device answer, in %d turns" % turns)
    assert_eq(heard.size(), 1, "and the spectrum arrived once")
    spectrum.draw_while_owed()
    assert_false(loop.process_frame.is_connected(spectrum.draw_while_owed), "With nothing owed the next turn lets go of the loop")
    var at_once := _spectrum()
    at_once.run(_easel, 0)
    assert_eq(at_once.transforms, 1, "A second spectrum reads the same picture at once")
    assert_eq(spectrum.power, at_once.power, "and the power the device handed back later is the same")
    assert_eq(spectrum.radial, at_once.radial, "and so are the rings")
    at_once.let_go()
    _service.leave(spectrum)
