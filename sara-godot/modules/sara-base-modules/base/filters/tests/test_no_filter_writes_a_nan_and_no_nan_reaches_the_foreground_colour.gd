## No filter writes a NaN, and no NaN reaches the foreground colour.
##
## A note on the symptom: "Levels on equalize lightness + curves only raises value
## effects made these weird black artifacts on the canvas", and the Info docker
## read the foreground as nan, nan, nan after a pick. The black was NaN, born in
## the Oklab safety net: `sa_positive_oklab` desaturates a colour past the
## spectral locus until its lowest LMS channel is zero, the float rounding left
## it a hair below, and the cube root of that is NaN. Equalize on Lightness
## pushes a photograph's darkest levels to an L near zero with their chroma
## kept, which is where the net fires.
##
## So every `SaPointAdjust` kind runs here at the ends of its controls, Equalize
## on every channel included, over a chunk holding flat runs, zero, deep
## shadows, negative channels and values far above one, at four depths and
## coordinate systems, and every output texel has to be finite. The chain of
## the note runs too, Levels and then Curves over the same chunk. A record
## whose output does hold a NaN says so once through the notice door, which is
## held with a NaN put in on purpose. Last, the colour store refuses a colour
## that is not finite, and the eyedropper refuses to pick one.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")

## The chunk's distinct colours, one texel each along its first row, in the
## document's own coordinates. Below them the chunk is one flat run of a light
## grey, the white wall of a photograph.
const COLOURS: Array[Color] = [
    Color(0.0, 0.0, 0.0, 1.0),
    Color(1e-6, 1e-6, 1e-6, 1.0),
    Color(0.0, 0.0, 1.0 / 255.0, 1.0),
    Color(0.0, 1.0 / 255.0, 4.0 / 255.0, 1.0),
    Color(0.2863, 0.0, 0.2, 1.0),
    Color(0.01, 0.0, 0.0, 1.0),
    Color(0.25, 0.25, 0.25, 1.0),
    Color(0.5, 0.5, 0.5, 1.0),
    Color(1.0, 1.0, 1.0, 1.0),
    Color(1.0, 0.0, 0.0, 1.0),
    Color(0.0, 1.0, 0.0, 1.0),
    Color(0.0, 0.0, 1.0, 1.0),
    Color(1.0, 1.0, 0.0, 1.0),
    Color(0.0, 1.0, 1.0, 1.0),
    Color(1.0, 0.0, 1.0, 1.0),
    Color(-0.8, 0.9, 0.9, 1.0),
    Color(-2.0, 0.9, 0.9, 1.0),
    Color(-0.05, -0.05, -0.05, 1.0),
    Color(0.2, -0.1, 0.5, 1.0),
    Color(-1.0, -1.0, -1.0, 1.0),
    Color(2.5, 1.2, 0.4, 1.0),
    Color(4.0, 4.0, 4.0, 1.0),
    Color(16.0, 0.5, 0.1, 1.0),
    Color(1.2, 1.0, -0.3, 1.0),
    Color(1000.0, 1000.0, 1000.0, 1.0),
    Color(0.4, 0.2, 0.1, 0.5),
    Color(0.3, 0.6, 0.9, 0.0),
]

## The flat run under the first row.
const FLAT := Color(0.9, 0.9, 0.9, 1.0)

## The four documents: the default, Oklab over sRGB's gamut at F16, and sRGB
## and linear sRGB at F16, where a value past 65504 has no number, and sRGB at
## F32.
var _spaces: Array[SaColorSpace] = [
    SaColorSpace.oklab_srgb_gamma30().with_depth(SaColorSpace.Depth.F16),
    SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F16),
    SaColorSpace.linear_srgb().with_depth(SaColorSpace.Depth.F16),
    SaColorSpace.srgb(),
]

var _easel: SaEasel = null
var _doc: SaDocument = null
var _engine: SaPointAdjust = null


func before_each() -> void:
    _engine = SaPointAdjust.new()


func after_each() -> void:
    _engine = null
    _close()


func _open(space: SaColorSpace) -> void:
    _close()
    _easel = SaEasel.create_default(Vector2i(SaChunk.SIZE, SaChunk.SIZE), null, space)
    _doc = _easel.document
    _doc.active_layer.fill(FLAT)
    _put_colours(COLOURS)


func _close() -> void:
    if _easel != null:
        _easel.free()
    _easel = null
    _doc = null


## Writes *colours* along the chunk's first row, at the field's own depth.
func _put_colours(colours: Array[Color]) -> void:
    var texture := _doc.active_layer.get_field(Vector2i.ZERO)
    var rd := GlobalShaderCompiler.get_rd()
    var bytes := rd.texture_get_data(texture.rid, 0)
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var stride := 8 if half else 16
    for i in colours.size():
        for channel in 4:
            var at := i * stride + channel * (2 if half else 4)
            if half:
                bytes.encode_half(at, colours[i][channel])
            else:
                bytes.encode_float(at, colours[i][channel])
    rd.texture_update(texture.rid, 0, bytes)


## How many channels of the chunk are not finite, alpha included, read off the
## bits: a float whose exponent is all ones is an infinity or a NaN, at either
## depth.
func _not_finite() -> int:
    var texture := _doc.active_layer.get_field(Vector2i.ZERO)
    var words := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0).to_int32_array()
    var count := 0
    if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
        for word in words:
            count += int((word & 0x7C00) == 0x7C00) + int(((word >> 16) & 0x7C00) == 0x7C00)
    else:
        for word in words:
            count += int((word & 0x7F800000) == 0x7F800000)
    return count


## The first row's texel *i*, for a message.
func _texel(i: int) -> Color:
    var texture := _doc.active_layer.get_field(Vector2i.ZERO)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, i)


## The first texel of the first row that is not finite, or minus one.
func _first_bad() -> int:
    for i in COLOURS.size():
        var texel := _texel(i)
        for channel in 4:
            if not is_finite(texel[channel]):
                return i
    return -1


## Runs *kind* with *values* over the chunk as one step, asserts every texel
## came out finite, and undoes it.
func _holds(kind: StringName, values: Dictionary, said: String) -> void:
    assert_true(_engine.apply(_doc, _doc.active_layer, kind, values, "N1"), "%s ran" % said)
    var bad := _not_finite()
    var first := _first_bad()
    var shown := "%s from %s" % [_texel(first), COLOURS[first]] if first >= 0 else "in the flat run"
    assert_eq(bad, 0, "%s on %s left every channel finite, the first bad %s" % [said, _doc.color_space.id, shown])
    _doc.undo()


## Counts *cdf_map* turns into a map: a photograph's, most of it a light wall
## and a little shadow, a dark one, and two flat runs at the two ends.
static func _maps() -> Array:
    var wall := PackedInt32Array()
    var dark := PackedInt32Array()
    var ends := PackedInt32Array()
    for i in SaPointAdjust.EQUALIZE_SAMPLES:
        wall.append(40000 if i > 200 else (3 if i > 8 else 0))
        dark.append(40000 if i < 12 else 2)
        ends.append(1000 if i == 0 or i == SaPointAdjust.EQUALIZE_SAMPLES - 1 else 0)
    return [SaLevelsFilter.cdf_map(wall), SaLevelsFilter.cdf_map(dark), SaLevelsFilter.cdf_map(ends)]


## Levels' handles at their ends: a span of one step with the gamma at either
## end, the two input handles crossed and met, and the output range turned over.
const LEVELS_HANDLES: Array[Dictionary] = [
    {"in_black": 0.995, "in_white": 1.0, "gamma": 0.1},
    {"in_black": 0.995, "in_white": 1.0, "gamma": 4.0},
    {"in_black": 1.0, "in_white": 0.0, "gamma": 0.1},
    {"in_black": 0.5, "in_white": 0.5, "gamma": 4.0},
    {"in_black": 0.0, "in_white": 1.0, "gamma": 1.0, "out_black": 1.0, "out_white": 0.0},
]


func test_levels_with_and_without_equalize_stays_finite_at_every_end() -> void:
    var maps := _maps()
    for space: SaColorSpace in _spaces:
        _open(space)
        for channel: String in SaPointAdjust.CHANNELS:
            for handles: Dictionary in LEVELS_HANDLES:
                var values := handles.duplicate()
                values["channel"] = channel
                _holds(SaPointAdjust.LEVELS, values, "Levels on %s at %s" % [channel, handles])
            for map: Array in maps:
                var equalized := {"channel": channel, "equalize": map, "equalize_channel": channel}
                _holds(SaPointAdjust.LEVELS, equalized, "Equalize on %s" % channel)
                equalized.merge(LEVELS_HANDLES[0])
                _holds(SaPointAdjust.LEVELS, equalized, "Equalize on %s under a one-step span" % channel)


## A lookup of *samples* sample by sample from *at*, which takes the place.
static func _curve(at: Callable) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    var count := SaCurveEditor.SAMPLES
    for i in count:
        out.append(float(at.call(float(i) / float(count - 1))))
    return out


func test_curves_on_every_channel_stay_finite_at_every_shape() -> void:
    var shapes := {
        "black": _curve(func(_x: float) -> float: return 0.0),
        "white": _curve(func(_x: float) -> float: return 1.0),
        "turned over": _curve(func(x: float) -> float: return 1.0 - x),
        "a step": _curve(func(x: float) -> float: return 0.0 if x < 0.5 else 1.0),
        "raised": _curve(func(x: float) -> float: return minf(1.0, x * 1.75)),
    }
    for space: SaColorSpace in _spaces:
        _open(space)
        for channel: String in SaPointAdjust.CHANNELS:
            for shape: String in shapes:
                _holds(SaPointAdjust.CURVES, {"curves": {channel: shapes[shape]}}, "Curves %s on %s" % [shape, channel])


## The note's chain itself: Equalize on Lightness, then a Lightness curve that
## only raises, over the same chunk.
func test_the_notes_chain_of_equalize_and_a_raising_curve_stays_finite() -> void:
    var raised := _curve(func(x: float) -> float: return minf(1.0, x * 1.75))
    for space: SaColorSpace in _spaces:
        _open(space)
        for map: Array in _maps():
            var levels := {"channel": "lightness", "equalize": map, "equalize_channel": "lightness"}
            assert_true(_engine.apply(_doc, _doc.active_layer, SaPointAdjust.LEVELS, levels, "N1"), "Levels ran")
            _holds(SaPointAdjust.CURVES, {"curves": {"lightness": raised}}, "Curves after Equalize")
            _doc.undo()


func test_brightness_and_contrast_stay_finite_at_both_ends_of_either_formula() -> void:
    for space: SaColorSpace in _spaces:
        _open(space)
        for brightness: float in [-1.0, 1.0]:
            for contrast: float in [0.0, 2.0]:
                var old := {"brightness": brightness, "contrast": contrast}
                _holds(SaPointAdjust.BRIGHTNESS_CONTRAST, old, "The old formula at %s" % old)
        for brightness: float in [1.0 / 64.0, 64.0]:
            for contrast: float in [0.0, 2.0]:
                var light := {"brightness": brightness, "contrast": contrast, "formula": 1.0}
                _holds(SaPointAdjust.BRIGHTNESS_CONTRAST, light, "The formula in light at %s" % light)


func test_hue_saturation_and_lightness_stay_finite_at_their_ends() -> void:
    for space: SaColorSpace in _spaces:
        _open(space)
        for hue: float in [-180.0, 180.0]:
            for saturation: float in [0.0, 2.0]:
                for lightness: float in [-1.0, 1.0]:
                    var values := {"hue": hue, "saturation": saturation, "lightness": lightness}
                    _holds(SaPointAdjust.HUE_SATURATION_LIGHTNESS, values, "Hue saturation lightness at %s" % values)


func test_colour_balance_stays_finite_with_every_amount_at_either_end() -> void:
    for space: SaColorSpace in _spaces:
        _open(space)
        for amount: float in [-1.0, 1.0]:
            for preserve: bool in [false, true]:
                var values := {"preserve_luminosity": preserve}
                for band: String in SaPointAdjust.BALANCE_BANDS:
                    for axis: String in SaPointAdjust.BALANCE_AXES:
                        values["%s_%s" % [band, axis]] = amount
                _holds(SaPointAdjust.COLOR_BALANCE, values, "Colour balance at %s" % amount)


func test_the_colour_lookup_stays_finite_at_full_pull_and_reach() -> void:
    var palette := [Color.BLACK, Color.WHITE, Color.RED, Color(0.0, 0.0, 1.0)]
    for space: SaColorSpace in _spaces:
        _open(space)
        for influence: float in [SaPointAdjust.INFLUENCE_MAX, 0.0]:
            var values := {"palette": palette, "shadows": 1.0, "midtones": 1.0, "highlights": 1.0, "influence": influence}
            _holds(SaPointAdjust.PALETTE, values, "The colour lookup at influence %s" % influence)


## A thousand in light raised six stops with the contrast at its top is 3.5e8,
## which an F16 document has no number for. The kernel stores the largest it
## has, 65504, rather than leave the conversion to the device, which may give
## an infinity, and an infinity is NaN in the next filter's arithmetic.
func test_an_f16_document_stores_a_value_past_its_largest_as_its_largest() -> void:
    _open(SaColorSpace.linear_srgb().with_depth(SaColorSpace.Depth.F16))
    var thousand := COLOURS.find(Color(1000.0, 1000.0, 1000.0, 1.0))
    var values := {"brightness": 64.0, "contrast": 2.0, "formula": 1.0}
    assert_true(_engine.apply(_doc, _doc.active_layer, SaPointAdjust.BRIGHTNESS_CONTRAST, values, "N1"), "ran")
    var stored := _texel(thousand)
    assert_eq(stored.r, SaPointAdjust.F16_LARGEST, "Red is the largest a half float holds: %s" % stored)
    assert_eq(stored.b, SaPointAdjust.F16_LARGEST, "and so is blue")
    _doc.undo()
    var guard := SaPointAdjust.guard_bytes(SaColorSpace.srgb())
    var bound := guard.decode_float(0)
    assert_almost_eq(bound / SaPointAdjust.F32_LARGEST, 1.0, 1e-6, "An F32 document's bound is the float's own largest")
    assert_eq(guard.decode_u32(4), 0, "and a record starts with no mark")


## Every kind moves mid grey at a setting that should, so the checks above are
## of a kernel that ran: a kernel that failed to compile leaves the chunk as it
## was, which is finite too.
func test_every_kind_moves_mid_grey_so_the_checks_above_are_not_empty() -> void:
    var settings := {
        SaPointAdjust.BRIGHTNESS_CONTRAST: {"brightness": 2.0, "contrast": 1.0, "formula": 1.0},
        SaPointAdjust.HUE_SATURATION_LIGHTNESS: {"lightness": 0.2},
        SaPointAdjust.COLOR_BALANCE: {"midtones_cr": 1.0},
        SaPointAdjust.LEVELS: {"gamma": 2.0},
        SaPointAdjust.CURVES: {"curves": {"master": _curve(func(x: float) -> float: return minf(1.0, x * 1.75))}},
        SaPointAdjust.PALETTE: {"palette": [Color.RED], "midtones": 1.0},
    }
    var grey := COLOURS.find(Color(0.5, 0.5, 0.5, 1.0))
    for space: SaColorSpace in _spaces:
        _open(space)
        var before := _texel(grey)
        for kind: StringName in settings:
            assert_true(_engine.apply(_doc, _doc.active_layer, kind, settings[kind], "N1"), "%s ran" % kind)
            var after := _texel(grey)
            assert_true(not after.is_equal_approx(before), "%s moved mid grey on %s: %s" % [kind, space.id, after])
            _doc.undo()


## A record over a texel that already holds a NaN writes one back, because the
## kernel does not hide one, and says so: its guard reads the mark, and tells
## the notice door once, naming the filter.
##
## The record is the one the filter chain holds, from Levels' own run through a
## previewing context, because the context builds a pass of its own from the
## record's parts. A record that asked after its own binds was never bound in
## the running app, and only the guard travels with the copy.
func test_a_record_that_writes_a_nan_says_so_once_naming_the_filter() -> void:
    _open(SaColorSpace.srgb())
    _put_colours([Color(NAN, 0.5, 0.5, 1.0)])
    var recorded := _chained(SaLevelsFilter.new(), {"gamma": 2.0})
    var guard := _guard_of(recorded)
    var watched := _watch_of(guard)
    assert_true(watched != null, "The pass the chain holds binds a guard the engine watches")
    if watched == null:
        return
    assert_true(SaFilterApply.apply_point(_doc, _doc.active_layer, recorded, SaCompute.new(SaPointAdjust.SHADER), "N1"), "ran")
    var notices: Array[String] = []
    var heard := func(line: String) -> void: notices.append(line)
    EventBus.corner_notice.connect(heard)
    watched.heard(guard.read())
    watched.heard(guard.read())
    EventBus.corner_notice.disconnect(heard)
    assert_eq(notices.size(), 1, "One notice for the record, however often it is read")
    assert_true(notices.size() == 1 and notices[0].contains("Levels"), "naming the filter: %s" % [notices])
    _doc.undo()


func test_a_clean_record_says_nothing() -> void:
    _open(SaColorSpace.srgb())
    var recorded := _chained(SaCurvesFilter.new(), {})
    var guard := _guard_of(recorded)
    var watched := _watch_of(guard)
    assert_true(watched != null, "The pass the chain holds binds a guard the engine watches")
    if watched == null:
        return
    assert_true(SaFilterApply.apply_point(_doc, _doc.active_layer, recorded, SaCompute.new(SaPointAdjust.SHADER), "N1"), "ran")
    var notices: Array[String] = []
    var heard := func(line: String) -> void: notices.append(line)
    EventBus.corner_notice.connect(heard)
    watched.heard(guard.read())
    EventBus.corner_notice.disconnect(heard)
    assert_eq(notices, [] as Array[String], "A record that wrote only numbers tells nobody anything")
    _doc.undo()


## The pass *filter* records with *values* through a previewing context, the
## way the filter chain asks for one.
func _chained(filter: SaFilter, values: Dictionary) -> SaPointPass:
    filter.set_parameters(values)
    var ctx := SaFilterContext.new(_doc, _doc.active_layer, &"sara-base-modules", filter.title(), true)
    filter.run(ctx)
    return ctx.point


func _guard_of(recorded: SaPointPass) -> SaCompute.Buffer:
    if recorded == null:
        return null
    return recorded.buffers.get(SaPointAdjust.GUARD_BINDING) as SaCompute.Buffer


## The engine's watch over *guard*, null when nothing watches it.
func _watch_of(guard: SaCompute.Buffer) -> SaPointAdjust.Watch:
    for watched: SaPointAdjust.Watch in SaPointAdjust._watches:
        if guard != null and watched.guard.get_ref() == guard:
            return watched
    return null


## The store keeps the pair it had when handed a colour with a channel that is
## not a number or is infinite, and says nothing on the bus.
func test_the_store_keeps_its_pair_when_handed_a_colour_that_is_not_finite() -> void:
    var store := SaColorStore.new()
    store.path = SaDataRoot.path("test_n1_colors.cfg")
    store.foreground = Color(0.2, 0.4, 0.6)
    store.background = Color(0.9, 0.8, 0.7)
    var seen: Array[Color] = []
    var listener := func(color: Color) -> void: seen.append(color)
    EventBus.color_picked.connect(listener)
    EventBus.background_color_changed.connect(listener)
    for wrong: Color in [Color(NAN, 0.0, 0.0), Color(0.0, NAN, 0.0), Color(INF, 0.0, 0.0), Color(0.0, 0.0, -INF)]:
        store.foreground = wrong
        store.background = wrong
        assert_eq(store.foreground, Color(0.2, 0.4, 0.6), "The foreground stays as it was for %s" % wrong)
        assert_eq(store.background, Color(0.9, 0.8, 0.7), "and so does the background")
    store.note_used(Color(NAN, 0.0, 0.0))
    EventBus.color_picked.disconnect(listener)
    EventBus.background_color_changed.disconnect(listener)
    assert_eq(seen, [] as Array[Color], "Nothing was announced")
    assert_eq(store.recent, [] as Array[Color], "and a colour that is not finite was never used")
    assert_true(SaColorStore.finite(Color(4.0, -1.0, 0.0)), "A colour past white or below zero is a colour")
    store.free()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(SaDataRoot.path("test_n1_colors.cfg")))


## A pick announced on the bus by someone else, which the store follows, is
## refused the same way, and a file that holds one loads without it.
func test_the_listener_and_the_load_refuse_one_too() -> void:
    var path := SaDataRoot.path("test_n1_colors.cfg")
    var store := SaColorStore.new()
    store.path = path
    store._ready()
    store.foreground = Color(0.2, 0.4, 0.6)
    EventBus.color_picked.emit(Color(NAN, NAN, NAN))
    assert_eq(store.foreground, Color(0.2, 0.4, 0.6), "The listener keeps the foreground it had")
    var config := ConfigFile.new()
    config.set_value("pair", "foreground", Color(NAN, NAN, NAN))
    config.set_value("lists", "recent", [Color.RED, Color(NAN, 0.0, 0.0)])
    config.save(path)
    var loaded := SaColorStore.new()
    loaded.load_from(path)
    assert_eq(loaded.foreground, SaColorStore.DEFAULT_FOREGROUND, "A saved NaN foreground loads as the default")
    assert_eq(loaded.recent, [Color.RED] as Array[Color], "and a saved NaN in the recent list is left out")
    loaded.free()
    store.free()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The eyedropper over a texel that is not a number picks nothing: the bus
## hears nothing and the painter's foreground stays.
func test_the_eyedropper_over_a_nan_texel_leaves_the_foreground() -> void:
    var surface := Fixtures.make_surface(Vector2i(64, 64))
    GlobalShaderCompiler.get_rd().texture_clear(surface.easel.output.rid, Color(NAN, 0.5, 0.5, 1.0), 0, 1, 0, 1)
    var eyedropper := StateEyedropperScript.new()
    eyedropper.surface = surface
    eyedropper.sample_from = StateEyedropperScript.SampleFrom.VIEW
    var before := SaColors.foreground
    var seen: Array[Color] = []
    var listener := func(color: Color) -> void: seen.append(color)
    EventBus.color_picked.connect(listener)
    eyedropper._sample_color_at_mouse(Vector2(32, 32))
    EventBus.color_picked.disconnect(listener)
    assert_eq(seen, [] as Array[Color], "The pick announced nothing")
    assert_eq(SaColors.foreground, before, "and the foreground is the one the painter had")
    surface.get_document().free()
    surface.easel.free()
