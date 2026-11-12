## The graph docker draws the spectrogram and its radial average.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The second case matters most: the mode built and handed a known
## spectrum through the reduction's own answer, reading the image's centre
## texel brightest and the curve's first point highest. Around it, the mode is a
## row of the docker's dropdown shown in place of the pictures, it says it waits
## until the first answer, the mirror puts a coefficient and its twin opposite
## each other, and painted stripes reach the image and the curve through the
## real transform on the GPU.
extends "res://tests/test_framework.gd"

## The known spectrum's side, so the image is 17 texels a side, and half of
## it, the centre texel's place on both axes and the rings past the first.
const SIDE := 16
const HALF := SIDE >> 1

## Document pixels a texel of the known spectrum's square spans.
const SPAN := 2.0

## The coefficient of the known spectrum lifted off its slope, across and down,
## and how far.
const BUMP := Vector2i(3, -2)
const BUMP_POWER := 0.02

## The painted canvas, the stripes' period on it in document pixels, as the graph
## suites paint them.
const CANVAS := Vector2i(512, 512)
const PERIOD := 32


## A power falling with the frequency as a painting's does, `1 / (1 + f²)²`,
## with [constant BUMP] lifted, as the half spectrum and its rings
## `SaPowerSpectrum` hands back: `SIDE` rows of `HALF + 1` and then the
## rings from the zero frequency.
static func _known_answer() -> PackedByteArray:
    var columns := SaPowerSpectrum.columns_for(SIDE)
    var floats := PackedFloat32Array()
    for row in SIDE:
        var v := row if row < HALF else row - SIDE
        for u in columns:
            var power := 1.0 / pow(1.0 + float(u * u + v * v), 2.0)
            if Vector2i(u, v) == BUMP:
                power += BUMP_POWER
            floats.append(power)
    for ring in columns:
        floats.append(1.0 / pow(1.0 + float(ring * ring), 2.0))
    return floats.to_byte_array()


## Only the zero frequency, as a flat picture of lightness one half answers.
static func _flat_answer() -> PackedByteArray:
    var floats := PackedFloat32Array()
    floats.resize(SaPowerSpectrum.columns_for(SIDE) * (SIDE + 1))
    floats.fill(0.0)
    floats[0] = 0.25
    floats[SaPowerSpectrum.columns_for(SIDE) * SIDE] = 0.25
    return floats.to_byte_array()


func _grey(image: Image, at: Vector2i) -> float:
    return image.get_pixelv(at).r


func test_the_mode_is_a_row_of_the_dropdown_and_shows_in_place_of_the_pictures() -> void:
    var docker := GraphDocker.new()
    var mode_button := docker.find_child("ModeButton", true, false) as SaChoiceButton
    assert_true(mode_button.choice_values().has(SaGraphSpectrogram.MODE), "The dropdown offers the spectrogram")
    assert_true(mode_button.choice_labels().has("Spectrogram"), "by its name")
    var pictures := docker.find_child("Pictures", true, false) as Control
    var source := docker.find_child("SourceButton", true, false) as Control
    assert_false(docker.spectrogram.visible, "A docker opens on the waveform with the spectrogram hidden")

    docker.show_mode(SaGraphSpectrogram.MODE)
    assert_eq(docker.graph_mode, SaGraphSpectrogram.MODE, "Chosen as the others are, the mode is the spectrogram")
    assert_eq(mode_button.selected_value(), SaGraphSpectrogram.MODE, "and the dropdown says so")
    assert_true(docker.spectrogram.visible, "Its view is shown")
    assert_false(pictures.visible, "in place of the binning kernel's pictures")
    assert_false(source.visible, "and without the source, since the spectrum is of the canvas")
    assert_true(docker.view_report().has("spectrogram"), "The docker's state dump carries the view's report")

    docker.show_mode("histogram")
    assert_false(docker.spectrogram.visible, "Another mode hides the view")
    assert_true(pictures.visible, "and shows the pictures again")
    assert_true(source.visible, "with the source")
    docker.free()


func test_a_known_spectrum_draws_its_centre_texel_brightest_and_its_curve_highest_first() -> void:
    var view := SaGraphSpectrogram.new()
    view.spectrum.heard(0, SIDE, SPAN, _known_answer())
    assert_eq(view.drawn, 1, "The answer is drawn once")
    var image := view.image
    assert_eq(image.get_size(), Vector2i(SIDE + 1, SIDE + 1), "The whole spectrum, both highest frequencies drawn")

    var centre := Vector2i(HALF, HALF)
    assert_almost_eq(_grey(image, centre), 1.0, 1e-6, "The zero frequency is white")
    var brightest_elsewhere := -1.0
    for y in image.get_height():
        for x in image.get_width():
            if Vector2i(x, y) != centre:
                brightest_elsewhere = maxf(brightest_elsewhere, _grey(image, Vector2i(x, y)))
    assert_true(_grey(image, centre) > brightest_elsewhere, "and the centre texel is the brightest of all")

    var bump := centre + BUMP
    var twin := centre - BUMP
    assert_almost_eq(_grey(image, bump), _grey(image, twin), 1e-6, "A coefficient and its twin opposite are one grey")
    assert_true(_grey(image, bump) > _grey(image, bump + Vector2i(1, 0)), "lifted above the slope beside it")
    var falling := image.get_pixel(centre.x + 1, centre.y).r > image.get_pixel(centre.x + 4, centre.y).r
    assert_true(falling, "and the power falls away from the centre")

    assert_eq(view.curve.size(), HALF, "The curve has a point for every ring from the first")
    var highest := 0
    for index in view.curve.size():
        if view.curve[index].y < view.curve[highest].y:
            highest = index
    assert_eq(highest, 0, "and its first point is the highest")
    assert_almost_eq(view.curve[0].x, 0.0, 1e-6, "at the left")
    assert_almost_eq(view.curve[view.curve.size() - 1].x, 1.0, 1e-6, "the finest ring at the right")
    assert_eq(view.ticks.size(), 4, "The scale is named at rings 1, 2, 4 and 8")
    assert_almost_eq(view.ticks[0].y, SIDE * SPAN, 1e-4, "the first being the whole square, 32 document pixels")
    assert_almost_eq(view.ticks[3].y, 2.0 * SPAN, 1e-4, "and the last two texels of it")
    view.free()


## The picture reaches the texture the view shows at the flush, and a later
## answer of the same size is written into that texture rather than lost.
func test_each_answer_reaches_the_texture_on_screen() -> void:
    if GlobalShaderCompiler.get_rd() == null:
        skip("no rendering device to read the texture back from")
        return
    var view := SaGraphSpectrogram.new()
    var picture := view.find_child("SpectrumImage", true, false) as TextureRect
    view.spectrum.heard(0, SIDE, SPAN, _known_answer())
    view.put_on_screen()
    var texture := picture.texture
    assert_eq(Vector2i(texture.get_size()), Vector2i(SIDE + 1, SIDE + 1), "The first answer's picture is on screen")
    assert_true(texture.get_image().get_pixel(0, 0).r > SaGraphPlot.BACKGROUND + 0.01, "with power in its corner")
    view.spectrum.heard(0, SIDE, SPAN, _flat_answer())
    view.put_on_screen()
    assert_eq(picture.texture, texture, "The second answer is written into the same texture")
    var corner := texture.get_image().get_pixel(0, 0).r
    assert_almost_eq(corner, SaGraphPlot.BACKGROUND, 1e-3, "and the corner reads the flat picture's grey")
    view.free()


func test_a_flat_spectrum_is_one_white_texel_on_the_graphs_grey() -> void:
    var view := SaGraphSpectrogram.new()
    view.spectrum.heard(0, SIDE, SPAN, _flat_answer())
    var image := view.image
    var others := 0
    for y in image.get_height():
        for x in image.get_width():
            if Vector2i(x, y) != Vector2i(HALF, HALF) and is_equal_approx(_grey(image, Vector2i(x, y)), SaGraphPlot.BACKGROUND):
                others += 1
    assert_almost_eq(_grey(image, Vector2i(HALF, HALF)), 1.0, 1e-6, "The zero frequency is white")
    assert_eq(others, image.get_width() * image.get_height() - 1, "and every other texel the background grey")
    for point: Vector2 in view.curve:
        assert_almost_eq(point.y, 1.0, 1e-6, "Every ring of nothing lies on the floor")
    view.free()


func test_before_an_answer_the_mode_says_it_waits_for_the_painter_to_stop() -> void:
    var view := SaGraphSpectrogram.new()
    var words := view.find_child("Waiting", true, false) as Label
    var picture := view.find_child("SpectrumImage", true, false) as Control
    assert_true(words.visible, "With no answer yet the view says why it is empty")
    assert_true(words.text.contains("stop painting"), "which is that it waits for the painter to stop")
    assert_false(picture.visible, "and shows no image")
    assert_true(view.report()["waiting"], "and its report says it waits")
    view.spectrum.heard(0, SIDE, SPAN, _known_answer())
    assert_false(words.visible, "The first answer takes the words away")
    assert_true(picture.visible, "for the image")
    view.free()


## The whole road on the GPU: painted stripes of 32 document pixels, the real
## composite and kernels, and the clock firing, as the other graph suites paint them.
func test_painted_stripes_reach_the_image_and_the_curve_through_the_transform() -> void:
    if GlobalShaderCompiler.get_rd() == null:
        skip("no rendering device for the transform")
        return
    var easel := SaEasel.create_default(CANVAS)
    easel.process_pending_composite()
    var clock := SaIdleClock.new()
    clock.follow_settings = false
    clock.follow_main = false
    clock.attach(easel.document)
    var service := SaReductionService.new()
    service.watch(easel)
    service.listen(clock)
    var view := SaGraphSpectrogram.new(clock)
    view.spectrum.read_at_once = true
    service.add(view.spectrum)

    for grid_pos: Vector2i in SaLayer.grid_positions(CANVAS):
        var chunk := easel.document.active_layer.get_or_create_chunk(grid_pos)
        var side := chunk.pixel_size()
        var row := PackedFloat32Array()
        for x in side:
            var lit := 1.0 if 2 * posmod(grid_pos.x * side + x, PERIOD) < PERIOD else 0.0
            row.append_array(PackedFloat32Array([lit, lit, lit, 1.0]))
        var texels := PackedFloat32Array()
        for y in side:
            texels.append_array(row)
        GlobalShaderCompiler.get_rd().texture_update(chunk.albedo().rid, 0, texels.to_byte_array())
        easel.document.invalidate_chunk_regions({grid_pos: Rect2i(Vector2i.ZERO, Vector2i.ONE * side)})
    assert_true(view.image == null, "Nothing is drawn while the painter has not stopped")
    clock.note_edit()
    assert_true(clock.tick(clock.idle_seconds), "The clock fires")
    assert_eq(view.drawn, 1, "and the transform's answer is drawn")

    var image := view.image
    assert_eq(image.get_size(), Vector2i(257, 257), "over the square of 256 and its mirror")
    var centre := Vector2i(128, 128)
    # Sixteen periods across the square, so the first harmonic is sixteen
    # texels either side of the zero frequency on the horizontal axis.
    var brightest := Vector2i(-1, -1)
    for y in image.get_height():
        for x in image.get_width():
            var at := Vector2i(x, y)
            if at != centre and (brightest.x < 0 or _grey(image, at) > _grey(image, brightest)):
                brightest = at
    assert_true(
        brightest == centre + Vector2i(16, 0) or brightest == centre - Vector2i(16, 0),
        "The peak off the centre is the stripes' frequency across, %s" % brightest
    )
    assert_almost_eq(_grey(image, centre + Vector2i(16, 0)), _grey(image, centre - Vector2i(16, 0)), 1e-6, "on both sides of it")
    assert_true(
        _grey(image, centre + Vector2i(0, 16)) < _grey(image, centre + Vector2i(16, 0)),
        "and not down, since the stripes are vertical"
    )
    var lowest := 0
    for index in view.curve.size():
        if view.curve[index].y < view.curve[lowest].y:
            lowest = index
    assert_eq(lowest + 1, 16, "The curve peaks at ring 16")
    assert_almost_eq(float(view.report()["peak_period"]), float(PERIOD), 1e-4, "which is a scale of 32 document pixels")

    service.free()
    clock.free()
    view.free()
    easel.free()
