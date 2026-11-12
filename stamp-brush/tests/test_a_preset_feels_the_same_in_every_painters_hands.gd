## A stamp preset carries the pressure table it was made under, so it answers
## the same brush output in every painter's hands.
##
## Painter A's table and painter B's are two tables set in `SaTablet.correction`
## one after the other, which is what two machines are to the stroke: the
## maximum is the hardware's and is held at 1.0 throughout, so what differs is
## the hand alone. The first two tests are the row's promise, measured on every
## option with a pressure sensor and then on the paint itself. Each also reads
## the same thing through B's own table, so it cannot pass by measuring nothing.
## The last two are the curve moving under a painter who changes it.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const SaMakerCurveScript = preload("res://modules/sara-base-modules/stamp-brush/sa_maker_curve.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The second test's proof is paint in a chunk, so this needs a real
## RenderingDevice.
const REQUIRES_GPU := true

## Never the real preset folder, for the reason `test_brush_presets.gd` gives.
static var scratch_dir: String = SaDataRoot.path("test_s5_a_preset_feels_the_same")

## The row's tolerance on an option's reading.
const TOLERANCE: float = 1e-5

## The stroke, left to right in document pixels, with the pressure ramping from
## nothing to full along it, so every stretch of the paint reads the table at
## another pressure.
const FROM_X: float = 40.0
const TO_X: float = 440.0
const STROKE_Y: float = 128.0
const STEP: float = 4.0
const SEED: int = 25

## Where the paint is read, five points along the stroke's line. The fourth
## is 332 because every rotated dab turns the way the kernel draws, which
## leaves 320 in a gap between two scattered dabs.
const READ_AT: Array[float] = [80.0, 160.0, 240.0, 332.0, 400.0]

var _correction := PackedFloat32Array()
var _max_pressure: float = 1.0


func before_each() -> void:
    _correction = SaTablet.correction
    _max_pressure = SaSettings.tablet_max_pressure
    SaSettings.tablet_max_pressure = 1.0
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    SaTablet.correction = _correction
    SaSettings.tablet_max_pressure = _max_pressure
    ScratchFolder.clear(scratch_dir)


## Size, opacity, flow and every other option with a pressure sensor, at the
## raw pressures 0 to 1 in steps of 0.05, read what they read under the table
## the preset was saved under.
func test_every_pressure_option_reads_what_it_read_under_the_makers_table() -> void:
    SaTablet.correction = _table_a()
    var made := _pressure_brush()
    var before := _readings(made, PackedFloat32Array(), false)
    _store().save_preset("Made by A", made)

    SaTablet.correction = _table_b()
    var loaded: SaStampBrushSettings = _store().load_preset("Made by A")
    var after := _readings(loaded, loaded.maker_pressure_curve, true)
    var painters := _readings(loaded, PackedFloat32Array(), false)

    assert_eq(after.size(), before.size(), "The same options read in both hands, %d readings" % before.size())
    var worst := 0.0
    var apart := 0.0
    for key: String in before:
        worst = maxf(worst, absf(float(after[key]) - float(before[key])))
        apart = maxf(apart, absf(float(painters[key]) - float(before[key])))
    assert_true(worst <= TOLERANCE, "Every pressure option reads as it did under A's table, worst %f" % worst)
    assert_true(apart > 0.05, "where B's own table would have moved them by %f" % apart)


## One scripted stroke painted under each painter's table leaves equal texels at
## five points along it.
func test_one_stroke_paints_the_same_texels_under_either_table() -> void:
    SaTablet.correction = _table_a()
    _store().save_preset("Made by A", _pressure_brush())
    var in_a := _paint_loaded()

    SaTablet.correction = _table_b()
    var in_b := _paint_loaded()
    var loaded: SaStampBrushSettings = _store().load_preset("Made by A")
    loaded.maker_pressure_curve = SaTablet.stamp()
    var through_b := _paint(loaded)

    var worst := 0.0
    var apart := 0.0
    var painted := 0
    for i in READ_AT.size():
        worst = maxf(worst, _difference(in_a[i], in_b[i]))
        apart = maxf(apart, _difference(in_a[i], through_b[i]))
        if in_a[i].a > 0.01:
            painted += 1
    assert_eq(painted, READ_AT.size(), "The stroke left paint at all five points")
    assert_true(worst <= TOLERANCE, "and the texels there are the same in either hand, worst %f" % worst)
    assert_true(apart > 0.01, "where B's own table would have painted them %f apart" % apart)


## A preset stamped with the painter's table follows the painter's next table,
## the brush in hand at once and the stored preset when the store is walked,
## and a preset stamped with another painter's keeps its maker's.
func test_the_painters_own_presets_follow_their_next_curve_and_anothers_do_not() -> void:
    SaTablet.save_correction(_table_a())
    var store := _store()
    var held := SaStampBrushSettings.new()
    store.save_preset("Mine", SaStampBrushSettings.new())
    var theirs := SaStampBrushSettings.new()
    theirs.maker_pressure_curve = _table_c()
    store.save_preset("Theirs", theirs)
    var holder: Array[Resource] = [held]
    var maker := SaMakerCurveScript.new(holder, scratch_dir)

    SaTablet.save_correction(_table_b())

    assert_true(SaTablet.same_table(held.maker_pressure_curve, _table_b()), "The brush in hand follows at once")
    assert_eq(maker.flush(), 1, "and walking the store rewrites one preset")
    var mine: SaStampBrushSettings = store.load_preset("Mine")
    var kept: SaStampBrushSettings = store.load_preset("Theirs")
    assert_true(SaTablet.same_table(mine.maker_pressure_curve, _table_b()), "which is the painter's own")
    assert_true(SaTablet.same_table(kept.maker_pressure_curve, _table_c()), "while another painter's keeps its maker's")
    maker.detach()
    SaTablet.save_correction(PackedFloat32Array())


## A brush in hand from another painter is left alone too, and a save that
## changes nothing announces nothing.
func test_a_brush_in_hand_from_another_painter_keeps_its_makers_curve() -> void:
    SaTablet.save_correction(_table_a())
    var held := SaStampBrushSettings.new()
    held.maker_pressure_curve = _table_c()
    var holder: Array[Resource] = [held]
    var maker := SaMakerCurveScript.new(holder, scratch_dir)
    var heard: Array[int] = [0]
    var count := func(_was: PackedFloat32Array, _now: PackedFloat32Array) -> void: heard[0] += 1
    SaTablet.curve_changes.changed.connect(count)

    SaTablet.save_correction(_table_a())
    assert_eq(heard[0], 0, "Saving the same curve again announces nothing")
    SaTablet.save_correction(_table_b())
    assert_eq(heard[0], 1, "and a new one announces once")
    assert_true(SaTablet.same_table(held.maker_pressure_curve, _table_c()), "and the other painter's brush keeps its curve")

    SaTablet.curve_changes.changed.disconnect(count)
    maker.detach()
    SaTablet.save_correction(PackedFloat32Array())


# --- Helpers ------------------------------------------------------------------


## Painter A presses lightly, so their table lifts the low end.
static func _table_a() -> PackedFloat32Array:
    return _table(0.4)


## Painter B presses hard, so their table holds the low end down.
static func _table_b() -> PackedFloat32Array:
    return _table(2.5)


## A third painter, for the preset nobody here made.
static func _table_c() -> PackedFloat32Array:
    return _table(1.6)


static func _table(exponent: float) -> PackedFloat32Array:
    var table := PackedFloat32Array()
    for i in range(256):
        table.append(pow(float(i) / 255.0, exponent))
    return table


## A fresh brush with a pressure sensor on every option and a bent curve on
## each, so every option answers the pressure and none of them the diagonal.
static func _pressure_brush() -> SaStampBrushSettings:
    var settings := SaStampBrushSettings.new()
    settings.radius = 0.04
    for option: SaCurveOption in settings.options().values():
        if option == null:
            continue
        option.enabled = true
        option.set_sensor(SaSensor.create(SaSensor.Id.PRESSURE, true))
        option.common_curve = PackedVector2Array([Vector2(0.0, 0.1), Vector2(0.35, 0.6), Vector2(1.0, 1.0)])
    return settings


## Every pressure option's two readings at every raw pressure, by name. With
## *through* false the painter's own table is read, which is how a stroke read
## before the row.
static func _readings(settings: SaStampBrushSettings, table: PackedFloat32Array, through: bool) -> Dictionary:
    var readings := {}
    var options := settings.options()
    for i in range(21):
        var raw := float(i) * 0.05
        var info := SaStrokeInfo.new()
        info.begin(Vector2.ZERO, SEED)
        if through:
            info.feed(Vector2.ZERO, raw, Vector2.ZERO, 0.0, 0.0, table)
        else:
            info.feed(Vector2.ZERO, raw, Vector2.ZERO, 0.0, 0.0)
        info.hovering = false
        for key: String in options:
            var option: SaCurveOption = options[key]
            if option == null or option.sensor_for(SaSensor.Id.PRESSURE) == null:
                continue
            option.begin_stroke()
            readings["%s size %.2f" % [key, raw]] = option.size_like(info)
            readings["%s turn %.2f" % [key, raw]] = option.rotation_like(info, 0.0, false)
    return readings


## The stroke painted with the preset as this machine loads it.
func _paint_loaded() -> Array[Color]:
    return _paint(_store().load_preset("Made by A") as SaStampBrushSettings)


## One stroke with *settings* on a fresh document, read at the five points.
func _paint(settings: SaStampBrushSettings) -> Array[Color]:
    var surface := Fixtures.make_surface(Vector2i(512, 256))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool
    brush.settings = settings
    brush.stroke_seed = SEED
    var was := SaColors.foreground
    SaColors.foreground = Color(1.0, 1.0, 1.0, 1.0)
    surface.view.mouse_position = Vector2(FROM_X, STROKE_Y)
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = surface.view.mouse_position
    brush.handle_input(press)
    var x := FROM_X
    while x < TO_X:
        x = minf(TO_X, x + STEP)
        surface.view.mouse_position = Vector2(x, STROKE_Y)
        var motion := InputEventMouseMotion.new()
        motion.position = surface.view.mouse_position
        motion.pressure = (x - FROM_X) / (TO_X - FROM_X)
        brush.handle_input(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    brush.handle_input(release)
    SaColors.foreground = was
    var texels: Array[Color] = []
    for at_x in READ_AT:
        texels.append(_texel(surface.easel.document, Vector2i(int(at_x), int(STROKE_Y))))
    Fixtures.teardown(surface, machine)
    return texels


## The active layer's colour at *at*, read off the chunk that holds it at the
## chunk's own pixel size.
static func _texel(doc: SaDocument, at: Vector2i) -> Color:
    var side := SaChunk.new().pixel_size()
    var grid := Vector2i(floori(float(at.x) / float(side)), floori(float(at.y) / float(side)))
    if not doc.active_layer.chunks.has(grid):
        return Color(0.0, 0.0, 0.0, 0.0)
    var chunk: SaChunk = doc.active_layer.chunks[grid]
    var texture: SaTexture = chunk.field(SaFieldSpec.ALBEDO)
    if texture == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var offset := ((at.y - grid.y * side) * side + (at.x - grid.x * side)) * 16
    return Color(
        data.decode_float(offset), data.decode_float(offset + 4), data.decode_float(offset + 8), data.decode_float(offset + 12)
    )


static func _difference(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store
