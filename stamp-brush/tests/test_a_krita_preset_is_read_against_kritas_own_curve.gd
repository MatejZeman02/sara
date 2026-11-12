## A Krita preset imports stamped with Krita's own pressure curve, read from a
## `kritarc`, so it answers in Sara what it answered in Krita whatever table
## the importing painter has.
##
## The preset is the round fixture, whose Opacity follows pressure through
## `0,0;0.5,0.75;1,1;` and whose Size follows it through the diagonal. The
## `kritarc` is written here with a curve that is not linear, and with a trap
## under a section of its own, which is another group's key and not Krita's
## curve. The expected readings are computed from the two point lists alone,
## the option's curve applied to the `kritarc`'s, and never from anything the
## import wrote.
extends "res://tests/test_framework.gd"

const KppFixtures = preload("res://modules/sara-base-modules/stamp-brush/tests/kpp_fixtures.gd")

static var scratch_preset_dir: String = SaDataRoot.path("test_s6_presets")
static var scratch_dir: String = SaDataRoot.path("test_s6_kritarc")

## The row's tolerance on an option's reading.
const TOLERANCE: float = 1e-4

## Krita's curve on the machine the preset came from, bent well away from the
## diagonal so a reading that ignored it could not pass.
const KRITA_CURVE: String = "0,0;0.25,0.6;1,1;"

## Each pressure option of the round fixture and its curve as the fixture
## writes it.
const OPTION_CURVES: Dictionary = {
    "opacity": "0,0;0.5,0.75;1,1;",
    "size": "0,0;1,1;",
}

## Samples the test reads an exact curve through, fine enough that reading
## between two of them is the spline to far below the tolerance.
const FINE: int = 100001

var _correction := PackedFloat32Array()
var _max_pressure: float = 1.0


func before_each() -> void:
    _correction = SaTablet.correction
    _max_pressure = SaSettings.tablet_max_pressure
    SaSettings.tablet_max_pressure = 1.0
    _clear()


func after_each() -> void:
    SaTablet.correction = _correction
    SaSettings.tablet_max_pressure = _max_pressure
    _clear()


## The row's promise: every pressure option at 0 to 1 in steps of 0.05 reads
## the preset's curve applied to the `kritarc`'s, under two different tables
## of Sara's in turn, where the painter's own table would have read otherwise.
func test_every_pressure_option_reads_its_curve_over_kritas() -> void:
    var kritarc := _write(
        "kritarc",
        (
            "canvasState=OPENGL_SUCCESS\n%s=%s\ncursorStyleDef=1\n[advancedColorSelector]\n%s=0,1;1,0;\n"
            % [SaKritarc.KEY, KRITA_CURVE, SaKritarc.KEY]
        )
    )
    var results := SaKppImport.import_path(_write_kpp(), _store(), null, true, kritarc)
    assert_eq(results.size(), 1, "The fixture imports as one preset")
    var line := SaKppImport.describe(results[0])
    var named := line.contains(KRITA_CURVE) and line.contains(kritarc)
    assert_true(named, "The console line names the curve and its file: %s" % line)

    var worst := 0.0
    var apart := 0.0
    var read := 0
    for table: PackedFloat32Array in [_table(0.4), _table(2.5)]:
        SaTablet.correction = table
        var loaded: SaStampBrushSettings = _store().load_preset(String(results[0]["name"]))
        var options := loaded.options()
        for key: String in OPTION_CURVES:
            var option: SaCurveOption = options[key]
            assert_true(option != null and option.sensor_for(SaSensor.Id.PRESSURE) != null, "%s follows pressure" % key)
            for i in range(21):
                var raw := float(i) * 0.05
                var through_krita := _exact(SaKppSensors.parse_curve(KRITA_CURVE), raw)
                var own := _exact(SaKppSensors.parse_curve(OPTION_CURVES[key]), through_krita)
                var expected := clampf(own, option.strength_min, option.strength_max)
                worst = maxf(worst, absf(_reading(option, raw, loaded.maker_pressure_curve) - expected))
                apart = maxf(apart, absf(_reading(option, raw, SaTablet.correction) - expected))
                read += 1
    assert_eq(read, 2 * 21 * OPTION_CURVES.size(), "Both options read at 21 pressures under both tables")
    assert_true(worst <= TOLERANCE, "Every reading is the option's curve over Krita's, worst %f" % worst)
    assert_true(apart > 0.05, "where the painter's own table would have moved them by %f" % apart)


## No `kritarc` is Krita's default, the diagonal, and the console line says so.
func test_no_kritarc_reads_as_linear_and_says_so() -> void:
    var missing := scratch_dir.path_join("no-such-kritarc")
    var results := SaKppImport.import_path(_write_kpp(), _store(), null, true, missing)
    var line := SaKppImport.describe(results[0])
    var said := line.contains("read as linear, no kritarc at %s" % missing)
    assert_true(said, "The line says the curve was linear and why: %s" % line)
    var loaded: SaStampBrushSettings = _store().load_preset(String(results[0]["name"]))
    var diagonal := SaTablet.same_table(loaded.maker_pressure_curve, PackedFloat32Array([0.0, 1.0]))
    assert_true(diagonal, "and the preset carries the diagonal")


## A `kritarc` without the key, or with it only under another group, is linear
## too, and says which of the two it was.
func test_a_kritarc_without_the_key_reads_as_linear() -> void:
    var kritarc := _write("kritarc", "[advancedColorSelector]\n%s=0,1;1,0;\n" % SaKritarc.KEY)
    var read := SaKritarc.read(kritarc)
    var said := String(read["said"])
    assert_true(said.contains("no %s in %s" % [SaKritarc.KEY, kritarc]), "The phrase names the missing key: %s" % said)
    assert_true(SaTablet.same_table(read["table"], PackedFloat32Array([0.0, 1.0])), "and the table is the diagonal")


## The table is the size the painter's own correction is, so the two are read
## the same way.
func test_the_table_is_the_size_sara_keeps() -> void:
    assert_eq(SaKritarc.SAMPLES, SaTabletSweep.SAMPLES, "One size for Krita's table and the painter's")
    var read := SaKritarc.read(_write("kritarc", "%s=%s\n" % [SaKritarc.KEY, KRITA_CURVE]))
    assert_eq((read["table"] as PackedFloat32Array).size(), SaTabletSweep.SAMPLES, "and the read table has it")


# --- Helpers ------------------------------------------------------------------


## *option*'s reading at *raw* with pressure through *table*, strength left out
## so the reading is the curve's alone.
static func _reading(option: SaCurveOption, raw: float, table: PackedFloat32Array) -> float:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 6)
    info.feed(Vector2.ZERO, raw, Vector2.ZERO, 0.0, 0.0, table)
    info.hovering = false
    option.begin_stroke()
    return option.size_like(info, false)


## The monotone cubic through *points* at *x*, the way Sara draws every curve,
## read between two of [constant FINE] samples.
static func _exact(points: PackedVector2Array, x: float) -> float:
    var samples := SaMonotoneCurve.sample(points, FINE)
    var at := clampf(x, 0.0, 1.0) * float(FINE - 1)
    var low := int(floor(at))
    var high := mini(low + 1, FINE - 1)
    return lerpf(samples[low], samples[high], at - float(low))


static func _table(exponent: float) -> PackedFloat32Array:
    var table := PackedFloat32Array()
    for i in range(256):
        table.append(pow(float(i) / 255.0, exponent))
    return table


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_preset_dir
    return store


func _write_kpp() -> String:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join("sara-round.kpp")
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(KppFixtures.round_kpp())
    file.close()
    return path


func _write(file_name: String, text: String) -> String:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join(file_name)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(text)
    file.close()
    return path


func _clear() -> void:
    for folder: String in [scratch_preset_dir, scratch_dir]:
        if DirAccess.dir_exists_absolute(folder):
            var dir := DirAccess.open(folder)
            for file in dir.get_files():
                dir.remove(file)
            DirAccess.remove_absolute(folder)
