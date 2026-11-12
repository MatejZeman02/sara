## A gradient-map brush paints its tip's lightness through the preset's ramp.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The tip mode on the stamp settings, Krita's brush application: Mask lays the
## brush's colour through the picture's coverage, Lightness Map moves it by the
## picture's lightness, and Gradient Map takes each texel's colour from the
## preset's ramp at that lightness. What this holds is the three readings of the
## note's first clause, the mask's texels to the bit against the binding every
## dab had before the mode, the walk's one dispatch against one a dab, when the
## ramp goes to the card, the migration of a file from before the mode, and the
## row on the Brush Tip page.
##
## **The picture is a ramp with three flat runs**, black, a grey of 128 and
## white, joined by short ramps, so each reading lands on a lightness the suite
## knows rather than one the sampler's filter blends between two columns. One
## corner texel is transparent and tinted, because `SaTipImage` reads a picture
## whose every texel is grey as a mask with a mid grey lightness throughout, and
## the corner is what makes it a picture that carries colour.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## The module that brings the Brush Tip page's rows, loaded by path the way
## `test_a_stamp_brush_preset_carries_a_gradient.gd` loads it.
const BASE_MODULE: String = "res://modules/sara-base-modules/base/module.gd"

## Never anything a painter owns, for the reason `test_dab_image_tip.gd` gives.
static var scratch_path: String = SaDataRoot.path("test_b1_ramp_tip.png")
## The picture's side, and where its three flat runs start and end.
const PICTURE_SIDE: int = 64
const BLACK_TO: int = 16
const GREY_FROM: int = 24
const GREY_TO: int = 40
const WHITE_FROM: int = 48
## The grey of the middle run as the PNG stores it, whose Rec. 709 luminance on
## the values as stored is the lightness the middle reading is taken at.
const GREY: float = 128.0 / 255.0

## The texture one dab is painted into, the dab centred in it at 48 px, so the
## picture's 64 columns land three to every four texels.
const SIDE: int = 64
const CENTRE := Vector2(32, 32)
const HALF_EXTENT := Vector2(24, 24)
## Texels on the middle row inside the black, grey and white runs.
const BLACK_X: int = 12
const GREY_X: int = 32
const WHITE_X: int = 52
const ROW: int = 32

## The brush's own colour, a green no stop of the ramp holds, so a texel that
## reads it was painted as a mask.
const BRUSH := Color(0.1, 0.8, 0.2, 1.0)
const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)

## The mask the last dab bound, kept the way the brush keeps its own, because
## the ramp a press settles hangs on it.
var _mask: SaBrushTipMask = null


func before_each() -> void:
    _mask = SaBrushTipMask.new()


func after_each() -> void:
    _mask = null
    if FileAccess.file_exists(scratch_path):
        DirAccess.remove_absolute(scratch_path)


## The picture the note names, a black-to-white ramp, written once a test.
static func _write_picture() -> String:
    var image := Image.create_empty(PICTURE_SIDE, PICTURE_SIDE, false, Image.FORMAT_RGBA8)
    for x in PICTURE_SIDE:
        var v := 0.0
        if x >= WHITE_FROM:
            v = 1.0
        elif x >= GREY_TO:
            v = lerpf(GREY, 1.0, float(x - GREY_TO + 1) / float(WHITE_FROM - GREY_TO + 1))
        elif x >= GREY_FROM:
            v = GREY
        elif x >= BLACK_TO:
            v = lerpf(0.0, GREY, float(x - BLACK_TO + 1) / float(GREY_FROM - BLACK_TO + 1))
        image.fill_rect(Rect2i(x, 0, 1, PICTURE_SIDE), Color(v, v, v, 1.0))
    image.set_pixel(0, 0, Color(1.0, 0.0, 0.0, 0.0))
    image.save_png(scratch_path)
    return scratch_path


## A picture tip of the ramp at *half_extent*, hard to its edge so the coverage
## is the picture's alpha alone.
static func _tip(half_extent: Vector2 = HALF_EXTENT, lightness: float = 0.0) -> Resource:
    var tip: Resource = SaBrushTipScript.new()
    tip.diameter = half_extent.x * 2.0
    tip.horizontal_fade = 1.0
    tip.vertical_fade = 1.0
    tip.generator = SaDabGeometry.Generator.IMAGE
    tip.image_path = _write_picture()
    tip.lightness_strength = lightness
    return tip


## Stamp settings in *mode* over a red-to-blue ramp, or *ramp* when given.
static func _settings(mode: SaStampBrushSettings.TipMode, ramp: SaColorRamp = null) -> SaStampBrushSettings:
    var settings := SaStampBrushSettings.new()
    settings.tip_mode = mode
    settings.gradient = (ramp if ramp != null else SaColorRamp.from_pair(RED, BLUE)).to_array()
    return settings


static func _selection() -> SaTexture:
    var selection := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    selection.clear(Color(1.0, 1.0, 1.0, 1.0))
    return selection


## The bindings the brush's `_bind_tip` makes that are not the canvas or the
## selection, through the door it makes them through.
func _bind_shared(compute: SaCompute, tip: Resource, space: SaColorSpace = null) -> void:
    _mask = SaStampBindings.bind(compute, tip, _mask, null, null, space)


## One dab of *tip* under *settings*, settled the way the brush's press settles
## it and read back raw. Null *settings* is a press that settles no mode, which
## is every caller from before the mode.
func _paint(tip: Resource, settings: SaStampBrushSettings, space: SaColorSpace = null) -> PackedByteArray:
    SaStampBindings.of(_mask).ramp.settle(settings, space)
    return _paint_settled(tip, space)


## One dab with whatever ramp the last press settled, which is what every dab
## of a stroke after its first is.
func _paint_settled(tip: Resource, space: SaColorSpace = null) -> PackedByteArray:
    var rd := GlobalShaderCompiler.get_rd()
    var canvas := SaTexture.new(Vector2i(SIDE, SIDE))
    rd.texture_clear(canvas.rid, Color(0, 0, 0, 0), 0, 1, 0, 1)
    var compute := SaCompute.new("dab")
    compute.set_texture(0, canvas.rid)
    # Held to the dispatch, because the texture is freed with its last reference.
    var selection := _selection()
    compute.set_texture(SaSelection.BINDING, selection.rid)
    _bind_shared(compute, tip, space)
    var params := SaDabPacking.pack_dab_params(
        CENTRE,
        Vector2.ZERO,
        BRUSH,
        tip.half_extent(),
        0.0,
        tip.effective_fade(),
        1.0,
        SaDabGeometry.PaintMode.OVER,
        false,
        tip,
        0.0,
        0.0,
        0.0
    )
    compute.set_push_constant_float_array(params)
    @warning_ignore("integer_division")
    compute.dispatch_kernel("dab", SIDE / SaPaintContext.WORKGROUP, SIDE / SaPaintContext.WORKGROUP, 1)
    return rd.texture_get_data(canvas.rid, 0)


static func _rgba(data: PackedByteArray, x: int, y: int) -> Color:
    var at := (y * SIDE + x) * 16
    return Color(data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8), data.decode_float(at + 12))


## The ramp the kernel samples, read at *lightness* the way a linear sampler
## clamped to its edge reads it, from the texels the bindings upload.
static func _ramp_at(settings: SaStampBrushSettings, lightness: float, space: SaColorSpace = null) -> Color:
    var texels := SaStampBindings.Ramp.texels(settings.gradient_ramp(), space)
    @warning_ignore("integer_division")
    var count := texels.size() / 4
    var x := clampf(lightness * count - 0.5, 0.0, count - 1.0)
    var low := mini(int(floor(x)), count - 2)
    var t := x - low
    var a := Color(texels[low * 4], texels[low * 4 + 1], texels[low * 4 + 2], texels[low * 4 + 3])
    var b := Color(texels[low * 4 + 4], texels[low * 4 + 5], texels[low * 4 + 6], texels[low * 4 + 7])
    return a.lerp(b, t)


static func _near(a: Color, b: Color, within: float) -> bool:
    return absf(a.r - b.r) <= within and absf(a.g - b.g) <= within and absf(a.b - b.b) <= within


## The note's first clause: red where the tip is black, blue where it is white
## and the ramp's middle between, with the coverage as before.
func test_a_gradient_map_dab_reads_red_where_the_tip_is_black_and_blue_where_it_is_white() -> void:
    var tip := _tip()
    var settings := _settings(SaStampBrushSettings.TipMode.GRADIENT_MAP)
    var mapped := _paint(tip, settings)
    var black := _rgba(mapped, BLACK_X, ROW)
    var grey := _rgba(mapped, GREY_X, ROW)
    var white := _rgba(mapped, WHITE_X, ROW)

    assert_true(_near(black, RED, 0.01), "Where the tip is black the dab reads red: %s" % black)
    assert_true(_near(white, BLUE, 0.01), "where it is white blue: %s" % white)
    assert_true(_near(black, _ramp_at(settings, 0.0), 2e-3), "and each is the ramp's own end, %s" % black)
    assert_true(_near(white, _ramp_at(settings, 1.0), 2e-3), "at both ends, %s" % white)
    var middle := _ramp_at(settings, SaTipImage.luminance_of(Color(GREY, GREY, GREY)))
    assert_true(_near(grey, middle, 2e-3), "The grey run reads the ramp at its lightness, %s against %s" % [grey, middle])
    assert_true(grey.r > 0.2 and grey.b > 0.2, "which is neither end but between them: %s" % grey)
    assert_true(grey.r < 0.9 and grey.b < 0.9, "and no end at all")

    # Coverage, opacity and blend as before: only the colour is the ramp's, so
    # the alpha every texel takes is the alpha the mask laid there.
    var masked := _paint(tip, _settings(SaStampBrushSettings.TipMode.MASK))
    var moved := 0
    for at in range(12, masked.size(), 16):
        if absf(masked.decode_float(at) - mapped.decode_float(at)) > 1e-6:
            moved += 1
    assert_eq(moved, 0, "and every texel's coverage is the one the mask laid")
    assert_true(_near(_rgba(masked, GREY_X, ROW), BRUSH, 1e-4), "where the mask laid the brush's own green")


## The note's second clause, first half: mask mode reads the texels it read
## before this row. Before it every dab bound a ramp that was not there, which is
## a press that settles no mode, and the mask is that to the bit. A tip whose
## Lightness row stands above nought paints the same as a mask, because the row
## is Lightness Map's alone now.
func test_a_mask_dab_paints_the_texels_it_painted_before_the_mode() -> void:
    var before := _paint(_tip(), null)
    var masked := _paint(_tip(), _settings(SaStampBrushSettings.TipMode.MASK))
    var lit := _paint(_tip(HALF_EXTENT, 1.0), _settings(SaStampBrushSettings.TipMode.MASK))
    var mapped := _paint(_tip(HALF_EXTENT, 1.0), _settings(SaStampBrushSettings.TipMode.LIGHTNESS_MAP))

    assert_true(_near(_rgba(before, GREY_X, ROW), BRUSH, 1e-4), "Before the mode a dab laid the brush's colour")
    assert_eq(masked, before, "and a mask lays every float of every texel it laid, to the bit")
    assert_eq(lit, before, "with the Lightness row above nought as well, which a mask does not read")
    assert_true(mapped != before, "where Lightness Map reads the row and moves the colour")
    assert_true(_rgba(mapped, WHITE_X, ROW).g > BRUSH.g + 0.05, "lighter where the tip is white")


## A grey picture carries no lightness of its own and maps to the ramp's middle,
## which is what the Mode row's tooltip tells the painter.
func test_a_grey_picture_maps_to_the_ramps_middle() -> void:
    var tip := _tip()
    tip.image_path = SaDataRoot.path("test_b1_grey_tip.png")
    var image := Image.create_empty(PICTURE_SIDE, PICTURE_SIDE, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.0, 0.0, 0.0, 1.0))
    image.save_png(tip.image_path)
    var settings := _settings(SaStampBrushSettings.TipMode.GRADIENT_MAP)
    var mapped := _paint(tip, settings)
    DirAccess.remove_absolute(tip.image_path)
    var middle := _ramp_at(settings, SaTipImage.NEUTRAL_LIGHTNESS)
    assert_true(_near(_rgba(mapped, GREY_X, ROW), middle, 2e-3), "A grey picture paints the ramp at its middle")


## The ramp is in the document's encoding through the document's space, as
## Gradient Map's is: an Oklab document takes the Lab values themselves.
func test_the_ramp_is_in_the_documents_encoding() -> void:
    var tip := _tip()
    var settings := _settings(SaStampBrushSettings.TipMode.GRADIENT_MAP)
    var space := SaColorSpace.oklab()
    var mapped := _paint(tip, settings, space)
    var black := _rgba(mapped, BLACK_X, ROW)
    var lab := SaColorRamp.from_pair(RED, BLUE).oklab_at(0.0)

    assert_true(_near(black, _ramp_at(settings, 0.0, space), 2e-3), "An Oklab document reads the ramp it was sent, %s" % black)
    assert_true(_near(black, lab, 2e-3), "which is red's Oklab coordinates, %s against %s" % [black, lab])
    assert_true(not _near(black, RED, 0.05), "and not sRGB's numbers for it")


## Nothing clamps: a stop brighter than white is painted brighter than one.
func test_a_stop_past_white_is_painted_past_one() -> void:
    var bright := Color(1.6, 0.2, 0.0, 1.0)
    var settings := _settings(SaStampBrushSettings.TipMode.GRADIENT_MAP, SaColorRamp.from_pair(bright, BLUE))
    var black := _rgba(_paint(_tip(), settings), BLACK_X, ROW)
    assert_true(black.r > 1.3, "The bright end reads past one, %f" % black.r)
    assert_true(_near(black, _ramp_at(settings, 0.0), 2e-3), "as the ramp holds it, %s" % black)


## Hard rule 1: the ramp goes to the card at the press when it has changed, and
## a dab binds what the press sent and sends nothing.
func test_the_ramp_goes_to_the_card_at_a_press_that_changes_it_and_never_at_a_dab() -> void:
    var ramp := SaStampBindings.Ramp.new()
    var settings := _settings(SaStampBrushSettings.TipMode.GRADIENT_MAP)
    assert_eq(ramp.rid(), SaBrushTipMask.stand_in().rid, "Before any press the stand-in is bound")
    assert_true(ramp.settle(settings, null), "The first press of a gradient map sends its ramp")
    var held := ramp.rid()
    assert_true(held != SaBrushTipMask.stand_in().rid, "into a texture of its own")
    assert_false(ramp.settle(settings, null), "A second press with the same ramp sends nothing")
    settings.gradient = SaColorRamp.from_pair(BLUE, RED).to_array()
    assert_true(ramp.settle(settings, null), "A press after the ramp changed sends it")
    assert_eq(ramp.rid(), held, "into the texture it holds")
    assert_true(ramp.settle(settings, SaColorSpace.oklab()), "and so does a press into a document of another space")
    assert_false(ramp.settle(_settings(SaStampBrushSettings.TipMode.MASK), null), "A mask sends nothing")
    assert_eq(ramp.rid(), SaBrushTipMask.stand_in().rid, "and binds the stand-in")

    # The stroke's dabs after the press: the ramp changes under them and they
    # paint the one the press sent, because a bind never sends one.
    var tip := _tip()
    var pressed := _settings(SaStampBrushSettings.TipMode.GRADIENT_MAP)
    var first := _paint(tip, pressed)
    pressed.gradient = SaColorRamp.from_pair(BRUSH, BRUSH).to_array()
    assert_eq(_paint_settled(tip), first, "A dab inside the stroke paints the ramp its press sent")
    assert_true(_paint(tip, pressed) != first, "and the next press sends the new one")


## The box a dab at *centre* dispatches over, out to whole workgroups.
static func _box(centre: Vector2, reach: float) -> Rect2i:
    var low := ((centre - Vector2(reach, reach)) / SaPaintContext.WORKGROUP).floor() * SaPaintContext.WORKGROUP
    var high := ((centre + Vector2(reach, reach)) / SaPaintContext.WORKGROUP).ceil() * SaPaintContext.WORKGROUP
    return Rect2i(Vector2i(low), Vector2i(high - low))


static func _target(texture: SaTexture, selection: SaTexture, box: Rect2i, centre: Vector2) -> SaPaintContext.Target:
    var target := SaPaintContext.Target.new()
    target.texture = texture
    target.mask = selection
    target.render_offset = Vector2(box.position)
    @warning_ignore("integer_division")
    target.groups_x = box.size.x / SaPaintContext.WORKGROUP
    @warning_ignore("integer_division")
    target.groups_y = box.size.y / SaPaintContext.WORKGROUP
    target.local_center = centre
    return target


## Dab *i* of the walk below, at a strength under one so the dabs it overlaps
## blend rather than cover.
static func _pack(i: int, target: SaPaintContext.Target, tip: Resource) -> PackedFloat32Array:
    return SaDabPacking.pack_dab_params(
        target.local_center,
        target.render_offset,
        Color(BRUSH.r, BRUSH.g, BRUSH.b, 0.6),
        tip.half_extent(),
        0.4 * i,
        tip.effective_fade(),
        0.7,
        SaDabGeometry.PaintMode.OVER,
        false,
        tip,
        0.0,
        0.0,
        float(i)
    )


## The note's second clause, second half: the walk's one dispatch of the
## batched kernel paints the picture one dispatch a dab painted, to the bit.
func test_the_walks_one_dispatch_paints_the_gradient_map_one_a_dab_painted() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var tip := _tip(Vector2(10, 10))
    SaStampBindings.of(_mask).ramp.settle(_settings(SaStampBrushSettings.TipMode.GRADIENT_MAP), null)
    var selection := _selection()
    var alone := SaTexture.new(Vector2i(SIDE, SIDE))
    var held := SaTexture.new(Vector2i(SIDE, SIDE))
    for texture: SaTexture in [alone, held]:
        rd.texture_clear(texture.rid, Color(0, 0, 0, 0), 0, 1, 0, 1)

    var compute := SaCompute.new("dab")
    _bind_shared(compute, tip)
    var batch := SaWalkBatch.new(SaDynamics.new(), SaDabPattern.new())
    batch.open(null)
    var bind := _bind_shared.bind(tip)
    for i in 12:
        var centre := Vector2(12.0 + 3.5 * i, 14.0 + 3.0 * i)
        var box := _box(centre, 12.0)
        compute.set_texture(0, alone.rid)
        compute.set_texture(SaSelection.BINDING, selection.rid)
        var target := _target(alone, selection, box, centre)
        compute.set_push_constant_float_array(_pack(i, target, tip))
        compute.dispatch_kernel("dab", target.groups_x, target.groups_y, 1)
        var paint := SaPaintContext.new()
        paint.targets.append(_target(held, selection, box, centre))
        var pack := func(on: SaPaintContext.Target) -> PackedFloat32Array: return _pack(i, on, tip)
        assert_true(batch.hold(paint, pack, 0.0, false, bind), "Dab %d is held for the walk's end" % i)
    var before: Dictionary = SaCompute.kernel_counters().get("dabs/dabs", {})
    batch.close(bind)
    batch.flush()
    var after: Dictionary = SaCompute.kernel_counters().get("dabs/dabs", {})
    assert_eq(int(after.get("dispatches", 0)) - int(before.get("dispatches", 0)), 1, "The twelve go as one dispatch")

    var one_a_dab := rd.texture_get_data(alone.rid, 0)
    var one_a_walk := rd.texture_get_data(held.rid, 0)
    var differing := 0
    var painted := 0
    var green := 0
    for at in range(0, one_a_dab.size(), 16):
        if one_a_dab.slice(at, at + 16) != one_a_walk.slice(at, at + 16):
            differing += 1
        if one_a_dab.decode_float(at + 12) > 0.0:
            painted += 1
            if one_a_dab.decode_float(at + 4) > 0.5:
                green += 1
    assert_true(painted > 600, "The twelve dispatches painted the diagonal, %d texels" % painted)
    assert_eq(green, 0, "in the ramp's colours and nowhere the brush's green")
    assert_eq(differing, 0, "and the one dispatch painted each float of each texel the same, to the bit")


## A file from before the mode reads it off the Lightness row it holds: a tip
## that moved the colour is a lightness map, and every other a mask.
func test_a_file_from_before_the_mode_reads_it_off_the_lightness_row() -> void:
    var lit := SaStampBrushSettings.new()
    lit.format_version = 12
    lit.tip.lightness_strength = 0.6
    lit.tip_mode = SaStampBrushSettings.TipMode.MASK
    assert_true(lit.migrate(), "A resource at 12 migrates")
    assert_eq(lit.tip_mode, SaStampBrushSettings.TipMode.LIGHTNESS_MAP, "into a lightness map when its row stood above nought")
    var flat := SaStampBrushSettings.new()
    flat.format_version = 12
    flat.tip_mode = SaStampBrushSettings.TipMode.GRADIENT_MAP
    flat.migrate()
    assert_eq(flat.tip_mode, SaStampBrushSettings.TipMode.MASK, "and into a mask when it stood at nought")
    assert_eq(SaStampBrushSettings.new().tip_mode, SaStampBrushSettings.TipMode.MASK, "which a new brush is")


## The note's Brush Tip page entry: a Mode row whose third choice is Gradient
## Map, on the settings and shown for a picture tip, with the Lightness row
## live in Lightness Map alone.
func test_the_brush_tip_page_offers_gradient_map_for_a_picture_tip() -> void:
    var roles := SaRoleRegistry.new()
    var context := SaContext.create(
        SaToolRegistry.new(),
        SaBlendModeRegistry.new(),
        SaCommandRegistry.new(),
        SaLayerTypeRegistry.new(),
        SaUIRegistry.new(),
        null,
        Callable(),
        Callable(),
        null,
        roles
    )
    var base: SaModule = load(BASE_MODULE).new()
    base.register(context.for_module(base.get_id()))
    var machine := ToolMachine.new(false)
    machine.name = "ToolMachine"
    machine._ready()
    machine.bind(null, Fixtures.make_tool_registry(), roles)
    var mode: SaOptionSpec = null
    var lightness: SaOptionSpec = null
    for each: SaOptionSpec in machine.get_descriptor(&"brush").options:
        if each.key == &"tip_mode":
            mode = each
        if each.key == &"tip_lightness":
            lightness = each
    assert_not_null(mode, "The brush declares a Mode row")
    assert_not_null(lightness, "and lists the Lightness row beside it")
    if mode != null and lightness != null:
        assert_eq(mode.property, ^"tip_mode", "on the stamp settings and not on the tip")
        var labels := {}
        for choice: Dictionary in mode.choices:
            labels[choice["id"]] = choice["label"]
        var gradient_map := int(SaStampBrushSettings.TipMode.GRADIENT_MAP)
        assert_eq(labels.get(gradient_map), "Gradient Map", "whose third entry is Gradient Map")
        assert_eq(mode.section, lightness.section, "in the Brush Tip page's section the Lightness row is in")
        assert_eq(mode.shown_when.get("value"), lightness.shown_when.get("value"), "shown for a picture tip as that row is")
        assert_eq(lightness.enabled_when, &"tip_mode", "and the Lightness row follows the mode")
        assert_eq(lightness.enabled_when_values, [int(SaStampBrushSettings.TipMode.LIGHTNESS_MAP)], "live in Lightness Map alone")
    machine.free()
    base.unregister(context)
