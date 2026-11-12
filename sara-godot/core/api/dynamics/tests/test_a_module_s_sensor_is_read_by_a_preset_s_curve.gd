## A sensor a module registers is read by a preset's curve.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The sensor fixture registers Across through its context, as any module
## would, and a curve option ticks it by its key, draws a falling curve over
## it, and is read at dabs across the canvas. The option is then saved as a
## preset's `.tres` and loaded again, and once the module unloads the same
## option reads nought from the sensor, as a built-in with no input does. The
## running app's half, a stamp preset's opacity following it along a real
## stroke, is `scenarios/sensors-are-registered.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const SensorFixture = preload("res://tests/fixtures/sensor/modules/sensor-fixture/module.gd")

## The curve the preset draws over Across: full at the left edge, none at the right.
const FALLING: PackedVector2Array = [Vector2(0.0, 1.0), Vector2(1.0, 0.0)]

var _registries: SaRegistries = null
var _module: SaModule = null
var _context: SaContext = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _module = SensorFixture.new()
    _context = _registries.context.for_module(_module.get_id())
    _module.register(_context)


func after_each() -> void:
    _context.remove_all_registrations()
    _context = null
    _module = null
    _registries = null


func _info(x: float) -> SaStrokeInfo:
    var info := SaStrokeInfo.new()
    info.begin(Vector2(x, 40.0), 639)
    info.hovering = false
    info.pressure = 0.5
    return info


## An option reading Across alone under the falling curve, as a preset ticks it.
func _option() -> SaCurveOption:
    var option := SaCurveOption.new()
    var id := SaSensor.id_of(SensorFixture.KEY)
    option.set_sensor(SaSensor.create(id as SaSensor.Id, true))
    option.common_curve = FALLING.duplicate()
    return option


func test_the_module_s_key_names_an_id_past_the_built_ins_and_back() -> void:
    var id := SaSensor.id_of(SensorFixture.KEY)
    assert_true(id >= SaSensorRegistry.FIRST_ID, "The fixture's key names an id past the twenty, %d" % id)
    assert_eq(id, SaSensorRegistry.id_for(SensorFixture.KEY), "the id its key answers on every run")
    assert_eq(SaSensor.key_of(id as SaSensor.Id), SensorFixture.KEY, "and the id names the key again")
    assert_eq(_registries.sensors.keys(), [SensorFixture.KEY] as Array[String], "The app's registry lists it")
    assert_eq(SaSensor.id_of("pressure"), int(SaSensor.Id.PRESSURE), "A built-in's key still names its ordinal")


func test_the_sensor_reads_the_dab_s_place() -> void:
    var sensor := SaSensor.create(SaSensor.id_of(SensorFixture.KEY) as SaSensor.Id, true)
    assert_almost_eq(sensor.value(_info(250.0)), 0.25, 1e-6, "Across at 250 px reads a quarter")
    assert_almost_eq(sensor.value(_info(1500.0)), 1.0, 1e-6, "and one past a thousand")
    assert_false(sensor.is_additive(), "A sensor registered plain multiplies")


func test_a_preset_s_curve_reads_the_module_s_sensor() -> void:
    var option := _option()
    option.begin_stroke()
    assert_almost_eq(option.size_like(_info(0.0)), 1.0, 1e-3, "The falling curve answers one at the left edge")
    assert_almost_eq(option.size_like(_info(250.0)), 0.75, 1e-2, "three quarters a quarter across")
    assert_almost_eq(option.size_like(_info(750.0)), 0.25, 1e-2, "a quarter three quarters across")
    assert_almost_eq(option.size_like(_info(1000.0)), 0.0, 1e-3, "and nought at the right")


func test_a_saved_preset_keeps_the_sensor_and_reads_it_after_a_load() -> void:
    var path := SaDataRoot.path("a_preset_reading_a_module_s_sensor.tres")
    assert_eq(ResourceSaver.save(_option(), path), OK, "The preset saves")
    var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SaCurveOption
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    assert_not_null(loaded, "and loads")
    var keys: Array[String] = []
    for sensor: SaSensor in loaded.active_sensors():
        keys.append(SaSensor.key_of(sensor.id))
    assert_eq(keys, [SensorFixture.KEY] as Array[String], "with the module's sensor ticked")
    loaded.begin_stroke()
    assert_almost_eq(loaded.size_like(_info(500.0)), 0.5, 1e-2, "and its curve reads it halfway across")


func test_an_additive_sensor_sums_through_the_curve_s_square() -> void:
    var lean := func(_sample: SaStrokeInfo, _sensor: SaSensor) -> float: return -0.5
    var id := _context.sensors.register("fixture_lean", lean, true)
    var sensor := SaSensor.create(id as SaSensor.Id, true)
    assert_true(sensor.is_additive(), "A sensor registered additive sums")
    assert_almost_eq(sensor.parameter(_info(10.0)), -0.5, 1e-6, "and its identity curve answers its reading")
    sensor.curve = PackedVector2Array([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
    assert_almost_eq(sensor.parameter(_info(10.0)), 0.5, 1e-2, "and a falling curve turns it the other way")


func test_a_key_a_built_in_holds_or_another_module_holds_is_refused() -> void:
    assert_eq(_context.sensors.register("pressure", SensorFixture.across), -1, "A built-in's key is refused")
    var other := _registries.context.for_module(&"another-module")
    assert_eq(other.sensors.register(SensorFixture.KEY, SensorFixture.across), -1, "and so is another module's")
    var again := _context.sensors.register(SensorFixture.KEY, SensorFixture.across)
    assert_eq(again, SaSensor.id_of(SensorFixture.KEY), "while the same module registers its own again")


func test_a_module_that_unloads_takes_its_sensor_and_the_preset_reads_nought() -> void:
    var option := _option()
    _context.remove_all_registrations()
    assert_eq(SaSensor.id_of(SensorFixture.KEY), -1, "The key names nothing once the module is gone")
    option.begin_stroke()
    assert_almost_eq(option.size_like(_info(750.0)), 1.0, 1e-3, "and the falling curve reads nought, so answers one")
