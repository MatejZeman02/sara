## Filter > Gradient Map lays a ramp over a layer's lightness.
##
## The last open half of the TODO's filter layer line, "gpu filter layers (blur,
## curves, gradient map) evaluated dynamically during compositing". A grey ramp
## from black to white across the chunk's first row is mapped through a two
## colour ramp and a three colour one, and the texels at its ends and its middle
## are held. The ends have to be the ramp's own two colours within one step of
## eight bits, which is what the note asks of a `texel` read, and every other
## texel is held to the ramp read at that texel's own Oklab lightness. Beside
## them: the amount blends over the original and an amount of nothing is the
## picture exactly, a stop at alpha nought leaves the lights as they were, the
## texel's own alpha is never touched, Apply is one history step, an Attach files
## the ramp it holds and never the empty one, and the kernel reads the same
## picture whichever space the document stores.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const BLUE := Color("#2040d0")
const ORANGE := Color("#f0a030")
const CREAM := Color("#f4ecd0")

## One step of eight bits, the note's own bound on how far an end may stand from
## the ramp's colour.
const STEP := 1.0 / 255.0

var _easel: SaEasel = null
var _doc: SaDocument = null
var _filter: SaGradientMapFilter = null


func before_each() -> void:
    _filter = SaGradientMapFilter.new()
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE, SaChunk.SIZE), null, SaColorSpace.srgb())
    _doc = _easel.document
    _doc.active_layer.fill(Color(0.5, 0.5, 0.5, 1.0))
    _put(_grey_ramp())


func after_each() -> void:
    _filter = null
    if _easel != null:
        _easel.free()
    _easel = null
    _doc = null


static func _lab(color: Color) -> Vector3:
    return OkhsvConversions.linear_srgb_to_oklab(OkhsvConversions.srgb_transfer_function_inv(Vector3(color.r, color.g, color.b)))


## The chunk's texels from its first, row by row, as many as *count*.
func _texels(count: int) -> Array[Color]:
    var texture := _doc.active_layer.get_field(Vector2i.ZERO)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var out: Array[Color] = []
    for i in count:
        out.append(SaFieldSpec.decode_texel(bytes, texture.format, i))
    return out


## Writes *colours* from the chunk's first texel on, row by row, at F32.
func _put(colours: Array[Color]) -> void:
    var texture := _doc.active_layer.get_field(Vector2i.ZERO)
    var rd := GlobalShaderCompiler.get_rd()
    var bytes := rd.texture_get_data(texture.rid, 0)
    for i in colours.size():
        for channel in 4:
            bytes.encode_float(i * 16 + channel * 4, colours[i][channel])
    rd.texture_update(texture.rid, 0, bytes)


## Black to white across the chunk's first row, one texel a step, in the
## document's own encoded values.
func _grey_ramp() -> Array[Color]:
    var out: Array[Color] = []
    for i in SaChunk.SIZE:
        var level := float(i) / float(SaChunk.SIZE - 1)
        out.append(Color(level, level, level, 1.0))
    return out


## What the ramp lays on *source*: the colour at the texel's own Oklab
## lightness, in the display encoding a texel of an sRGB document holds.
static func _wanted(ramp: SaColorRamp, source: Color) -> Color:
    return ramp.display_at(clampf(_lab(source).x, 0.0, 1.0))


static func _near(a: Color, b: Color, bound: float) -> bool:
    return absf(a.r - b.r) <= bound and absf(a.g - b.g) <= bound and absf(a.b - b.b) <= bound


func _apply(spec: Dictionary) -> bool:
    return _filter.capture_apply(_doc, spec)


func test_the_two_ends_of_a_grey_ramp_take_the_two_colours_of_a_blue_to_orange_map() -> void:
    assert_true(_apply({"colours": ["#2040d0", "#f0a030"]}), "the map ran")
    var row := _texels(SaChunk.SIZE)
    assert_true(_near(row[0], BLUE, STEP), "black is the ramp's blue within a step of 8 bits, read %s" % row[0])
    assert_true(
        _near(row[SaChunk.SIZE - 1], ORANGE, STEP), "white is the ramp's orange within a step, read %s" % row[SaChunk.SIZE - 1]
    )
    var ramp := SaColorRamp.from_pair(BLUE, ORANGE)
    for i: int in [32, 64, 99, 128, 192, 224]:
        var wanted := _wanted(ramp, _grey_ramp()[i])
        assert_true(_near(row[i], wanted, STEP), "texel %d is the ramp at its own lightness %s, read %s" % [i, wanted, row[i]])


func test_a_three_colour_map_holds_its_ends_and_its_middle() -> void:
    var colours := ["#2040d0", "#f4ecd0", "#f0a030"]
    assert_true(_apply({"colours": colours}), "the map ran")
    var row := _texels(SaChunk.SIZE)
    var ramp := SaGradientMapFilter.evenly(colours)
    assert_true(_near(row[0], BLUE, STEP), "black is the first colour, read %s" % row[0])
    assert_true(_near(row[SaChunk.SIZE - 1], ORANGE, STEP), "white is the last, read %s" % row[SaChunk.SIZE - 1])
    # The texel nearest an Oklab lightness of one half, which is where the
    # middle stop sits, so it reads the middle colour to the texel's own
    # distance from the half.
    var middle := 0
    var nearest := 1.0
    for i in SaChunk.SIZE:
        var gap := absf(_lab(_grey_ramp()[i]).x - 0.5)
        if gap < nearest:
            nearest = gap
            middle = i
    var middle_wanted := _wanted(ramp, _grey_ramp()[middle])
    assert_true(
        _near(row[middle], middle_wanted, STEP),
        "texel %d, at the middle stop, is %s, read %s" % [middle, middle_wanted, row[middle]]
    )
    assert_true(_near(row[middle], CREAM, 3.0 * STEP), "and that is the middle colour, read %s" % row[middle])
    for i: int in [16, 48, 140, 200]:
        var wanted := _wanted(ramp, _grey_ramp()[i])
        assert_true(
            _near(row[i], wanted, 2.0 * STEP), "texel %d is the ramp at its own lightness %s, read %s" % [i, wanted, row[i]]
        )


func test_the_map_reads_lightness_and_not_the_colour_it_replaces() -> void:
    # A saturated red and a grey of the same Oklab lightness land on one colour.
    var red := Color(0.9, 0.1, 0.1, 1.0)
    var level := OkhsvConversions.srgb_transfer_function(Vector3.ONE * pow(_lab(red).x, 3.0)).x
    _put([red, Color(level, level, level, 1.0)])
    assert_true(_apply({"colours": ["#2040d0", "#f0a030"]}), "the map ran")
    var row := _texels(2)
    assert_true(
        _near(row[0], row[1], 2.0 * STEP),
        "the red and the grey of its lightness take one colour, read %s and %s" % [row[0], row[1]]
    )


func test_a_texel_beyond_black_and_white_reads_the_ramps_ends() -> void:
    _put([Color(-0.4, -0.4, -0.4, 1.0), Color(3.0, 3.0, 3.0, 1.0)])
    assert_true(_apply({"colours": ["#2040d0", "#f0a030"]}), "the map ran")
    var row := _texels(2)
    assert_true(_near(row[0], BLUE, STEP), "a texel below black is the first colour, read %s" % row[0])
    assert_true(_near(row[1], ORANGE, STEP), "a texel above white is the last, read %s" % row[1])


func test_the_amount_blends_the_map_over_the_original() -> void:
    var original := _texels(SaChunk.SIZE)
    assert_true(_apply({"colours": ["#2040d0", "#f0a030"], "amount": 50}), "the half map ran")
    var row := _texels(SaChunk.SIZE)
    for i: int in [0, 100, 255]:
        var full := _wanted(SaColorRamp.from_pair(BLUE, ORANGE), original[i])
        var wanted := original[i].lerp(full, 0.5)
        assert_true(
            _near(row[i], wanted, 2.0 * STEP),
            "texel %d is halfway from its own grey to the map, wanted %s read %s" % [i, wanted, row[i]]
        )
    _doc.undo()
    assert_true(_apply({"colours": ["#2040d0", "#f0a030"], "amount": 0}), "the map at nothing ran")
    var untouched := _texels(SaChunk.SIZE)
    for i in SaChunk.SIZE:
        assert_true(_near(untouched[i], original[i], 0.0), "texel %d is the picture exactly at an amount of nothing" % i)


func test_a_stop_at_alpha_nothing_leaves_the_lights_as_they_were() -> void:
    var original := _texels(SaChunk.SIZE)
    var stops := [
        {"position": 0.0, "color": [BLUE.r, BLUE.g, BLUE.b, 1.0]},
        {"position": 1.0, "color": [ORANGE.r, ORANGE.g, ORANGE.b, 0.0]},
    ]
    assert_true(_apply({"ramp": stops}), "the fading map ran")
    var row := _texels(SaChunk.SIZE)
    assert_true(_near(row[0], BLUE, STEP), "black is the opaque stop's blue, read %s" % row[0])
    assert_true(
        _near(row[SaChunk.SIZE - 1], original[SaChunk.SIZE - 1], STEP), "white is as it was, read %s" % row[SaChunk.SIZE - 1]
    )


func test_the_texels_own_alpha_is_never_touched() -> void:
    _put([Color(0.2, 0.2, 0.2, 0.25), Color(0.8, 0.8, 0.8, 0.0), Color(0.5, 0.5, 0.5, 1.0)])
    assert_true(_apply({"colours": ["#2040d0", "#f0a030"]}), "the map ran")
    var row := _texels(3)
    assert_eq(snappedf(row[0].a, 0.0001), 0.25, "a quarter opaque stays a quarter opaque")
    assert_eq(snappedf(row[1].a, 0.0001), 0.0, "a clear texel stays clear")
    assert_eq(snappedf(row[2].a, 0.0001), 1.0, "an opaque one stays opaque")


func test_apply_is_one_history_step_and_one_undo_puts_the_picture_back() -> void:
    var original := _texels(SaChunk.SIZE)
    var before := _doc.history.step_count()
    assert_true(_apply({"colours": ["#2040d0", "#f0a030"]}), "the map ran")
    assert_eq(_doc.history.step_count(), before + 1, "Apply is one step")
    _doc.undo()
    var restored := _texels(SaChunk.SIZE)
    for i in SaChunk.SIZE:
        assert_true(_near(restored[i], original[i], 0.0), "texel %d is as it was after one undo" % i)


func test_the_kernel_lands_on_the_same_colour_in_a_linear_and_in_an_oklab_document() -> void:
    var spaces: Array[SaColorSpace] = [
        SaColorSpace.linear_srgb().with_depth(SaColorSpace.Depth.F32),
        SaColorSpace.oklab_srgb_gamma30().with_depth(SaColorSpace.Depth.F32),
    ]
    for space in spaces:
        _easel.free()
        _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE, SaChunk.SIZE), null, space)
        _doc = _easel.document
        _doc.active_layer.fill(Color(0.5, 0.5, 0.5, 1.0))
        var recorded := SaGradientMapFilter.record(SaGradientMapFilter.spec_values({"colours": ["#2040d0", "#f0a030"]}), space)
        assert_true(recorded != null, "a pass is recorded for %s" % space)
        # A black and a white texel written in this document's own values.
        var black := space.from_display(Color.BLACK)
        var white := space.from_display(Color.WHITE)
        _put([black, white])
        assert_true(
            SaFilterApply.apply_point(_doc, _doc.active_layer, recorded, SaCompute.new(SaGradientMapFilter.SHADER), "E1"),
            "the map ran on %s" % space
        )
        var row := _texels(2)
        var dark := space.to_display(row[0])
        var light := space.to_display(row[1])
        assert_true(_near(dark, BLUE, STEP), "black is the blue on %s, read %s" % [space, dark])
        assert_true(_near(light, ORANGE, STEP), "white is the orange on %s, read %s" % [space, light])


func test_reverse_swaps_the_two_ends_and_keeps_each_stops_alpha() -> void:
    var ramp := SaColorRamp.from_pair(BLUE, Color(ORANGE, 0.5))
    ramp.add_stop(0.25, CREAM)
    var flipped := SaGradientMapFilter.reversed(ramp)
    assert_eq(flipped.size(), 3, "every stop is kept")
    assert_eq(float(flipped[0]["position"]), 0.0, "the first stop is at the dark end")
    assert_eq(Color(flipped[0]["color"]), Color(ORANGE, 0.5), "and is the old last colour with its alpha")
    assert_eq(float(flipped[1]["position"]), 0.75, "the cream stop moved from a quarter to three quarters")
    assert_eq(float(flipped[2]["position"]), 1.0, "the last stop is at the light end")
    assert_eq(Color(flipped[2]["color"]), BLUE, "and is the old first colour")


func test_the_panel_reverses_and_lays_the_stock_ramps_across_the_picked_pair() -> void:
    var panel := SaGradientMapPanel.new()
    panel.set_ramp(SaColorRamp.from_pair(BLUE, ORANGE))
    var heard := [0]
    panel.changed.connect(func() -> void: heard[0] += 1)
    panel.reverse()
    assert_eq(Color(panel.ramp.color_of(0)), ORANGE, "Reverse puts the orange at the dark end")
    assert_eq(Color(panel.ramp.color_of(1)), BLUE, "and the blue at the light")
    assert_eq(heard[0], 1, "and says so once")
    assert_true(panel.choose_stock(&"foreground_to_background"), "the first stock ramp is chosen")
    assert_eq(Color(panel.ramp.color_of(0)), Color(SaColors.foreground, 1.0), "it starts on the foreground")
    assert_eq(Color(panel.ramp.color_of(1)), Color(SaColors.background, 1.0), "and ends on the background")
    assert_true(panel.choose_stock(&"foreground_to_transparent"), "the second is chosen")
    assert_eq(panel.ramp.color_of(1).a, 0.0, "it fades to nothing at the light end")
    assert_false(panel.choose_stock(&"not_a_stock"), "a name that is no stock is refused")
    assert_eq(heard[0], 3, "the two stock ramps said so once each")
    var library := panel.find_child("LibraryRow", true, false) as Control
    assert_true(
        library != null and not library.visible, "the control's library row, whose stock rows would do nothing, is put away"
    )
    panel.free()


func test_a_dialog_opens_on_the_picked_pair_and_an_attach_files_the_ramp_it_holds() -> void:
    var open := _filter.values()
    var ramp := SaColorRamp.from_array(open["ramp"] as Array)
    assert_eq(ramp.size(), 2, "an unedited map is the two picked colours")
    assert_eq(Color(ramp.color_of(0)), Color(SaColors.foreground, 1.0), "the dark end is the foreground")
    assert_eq(Color(ramp.color_of(1)), Color(SaColors.background, 1.0), "the light end is the background")
    assert_eq(float(open["amount"]), 100.0, "at the whole amount")
    var empty := _filter.parameters()
    assert_true(
        (empty["ramp"] as Array).is_empty(), "while the dialog itself holds the empty list, so the pair is read when it is read"
    )
    var filed := _filter.filed_as(&"sara-base-modules.gradient_map")
    assert_eq(filed.key, &"sara-base-modules.gradient_map", "the record is the filter's own")
    assert_false((filed.parameters["ramp"] as Array).is_empty(), "and holds the ramp as it stood, never the empty list")
    _filter.set_parameters({"ramp": SaGradientMapFilter.evenly(["#2040d0", "#f0a030"]).to_array(), "amount": 60})
    assert_eq(float(_filter.values()["amount"]), 60.0, "a record's amount comes back as it was filed")
    assert_eq(Color(SaColorRamp.from_array(_filter.values()["ramp"] as Array).color_of(0)), BLUE, "and its ramp")


func test_a_record_that_never_named_a_ramp_reads_as_the_picked_pair() -> void:
    _filter.set_parameters({})
    assert_true((_filter.parameters()["ramp"] as Array).is_empty(), "an older file's record holds no ramp")
    assert_eq(SaGradientMapFilter.ramp_of(_filter.values()).size(), 2, "and reads as the picked pair")
    assert_eq(SaGradientMapFilter.ramp_of({"ramp": "a stray word"}).size(), 2, "so does a ramp that is not a list")
    assert_eq(SaGradientMapFilter.ramp_of({"ramp": [{"position": 0.5}]}).size(), 2, "and a list with no readable stop in it")
