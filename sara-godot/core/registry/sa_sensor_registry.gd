## The seventeenth registry: the sensors a module adds to the twenty `SaSensor`
## reads itself, so a curve option can follow a reading Sara never knew. A
## module registers one with `context.sensors.register(key, reading)`, the
## door's call, and a preset ticks it by its key as it ticks pressure.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The twenty built-ins stay in `SaSensor`'s match, and only a module's sensor
## is read through here.** A dab asks every ticked sensor of every option, and
## the built-ins are a jump table there. A built-in read through a callable
## would cost every stroke a call per sensor per dab for a door none of them
## needs, so the registry is the place a module's sensor lives and the match's
## last branch is the one that asks it. A stroke with no module sensor ticked
## never reaches this file.
##
## **A module's sensor has an id that is a function of its key.** A preset's
## `.tres` stores a sensor as its id, the enum's ordinal for a built-in, so an id
## handed out in registration order would mean another sensor the day two
## modules load in the other order. [method id_for] answers the same number for
## the same key on every run and machine, above [constant FIRST_ID], and a key
## whose number another key already holds is refused rather than shadowed.
##
## **Asked without an app.** A dab runs in a suite, a worker and a tool script
## alike, so `SaSensor` asks through [method shared]. `SaRegistries` installs the
## app's own, held weakly, so a suite that built registries of its own and let
## them go leaves nothing behind. With none installed, [method shared] answers a
## registry of this class's own, empty unless a suite registered into it.
##
## **A view per module.** [method for_module] hands a module a view that files
## what it registers under the module and shares one table with the app's own,
## so a module that unloads takes its sensors with it, and a preset ticking one
## reads nought from then on, the answer the match gives an id it does not know.
class_name SaSensorRegistry
extends RefCounted

## The lowest id a module's sensor is given, `SaSensor`'s, which a dab
## compares against before it asks here.
const FIRST_ID: int = SaSensor.FIRST_MODULE_ID

## How many ids above [constant FIRST_ID] a key can land on.
const ID_SPAN: int = 1 << 24

## The registry the app installed, weakly, or null.
static var _installed: WeakRef = null
## The registry answered while no app installed one.
static var _own: SaSensorRegistry = null

## Id -> [SaSensorRegistry.Sensor], one dictionary shared by every module's
## view, because the dab looks a sensor up by its id.
var _by_id: Dictionary = {}
## The module a view files what it registers under, empty for the app's own.
var _module_id: StringName = &""


## One sensor a module brings: its key, its id, whether it sums, and the call
## that reads it. Written by its constructor alone.
##
## `reading.call(info, sensor)` answers the sensor's reading of the
## `SaStrokeInfo` *info* before any curve, 0 to 1 for a plain sensor and -1 to 1
## for an additive one, as `SaSensor.value` answers a built-in. *sensor* is the
## `SaSensor` asking, so a reading can use its `length` or its name.
class Sensor:
    extends RefCounted
    ## What a preset ticks it by, `"fixture_pressure_squared"` for the suite's.
    var key: String
    ## The id `SaSensor.id` holds for it, [method SaSensorRegistry.id_for] of the key.
    var id: int
    ## Whether it sums with the option's other sensors rather than multiplying,
    ## and so answers -1 to 1 and is moved onto the curve's square and back.
    var additive: bool
    ## Which module registered it.
    var module: StringName
    var _reading: Callable

    func _init(named: String, reading: Callable, sums: bool, owner_module: StringName) -> void:
        key = named
        id = SaSensorRegistry.id_for(named)
        additive = sums
        module = owner_module
        _reading = reading

    ## The reading of *info* for *sensor*, before any curve.
    func read(info: SaStrokeInfo, sensor: SaSensor) -> float:
        return SaTyped.real(_reading.call(info, sensor))


## *held* is the table of another view, so a module's view and the app's hold
## one table. A new registry starts its own.
func _init(module_id: StringName = &"", held: Variant = null) -> void:
    _module_id = module_id
    _by_id = held if held is Dictionary else {}


## The registry the app installed, or one of this class's own.
static func shared() -> SaSensorRegistry:
    if _installed != null:
        var held: SaSensorRegistry = _installed.get_ref()
        if held != null:
            return held
    if _own == null:
        _own = SaSensorRegistry.new()
    return _own


## Makes *registry* the one [method shared] answers while something holds it.
static func install(registry: SaSensorRegistry) -> void:
    _installed = weakref(registry) if registry != null else null


## The id a module's sensor called *key* is given, the same on every run.
static func id_for(key: String) -> int:
    return FIRST_ID + (hash(key) & (ID_SPAN - 1))


## A view of this registry that files what it registers under *module_id*,
## which `SaContext.for_module` hands a module.
func for_module(module_id: StringName) -> SaSensorRegistry:
    return SaSensorRegistry.new(module_id, _by_id)


## Registers the sensor *key*, read by *reading* as [SaSensorRegistry.Sensor]
## says it is called, summing when *additive*, filed under *module_id* or else
## the view's module. Answers the sensor's id, or -1 when refused: for no key, a
## key a built-in holds, a callable that is not valid, or a key or an id another
## module holds. The same module registering a key again replaces its entry.
func register(key: String, reading: Callable, additive: bool = false, module_id: StringName = &"") -> int:
    if module_id.is_empty():
        module_id = _module_id
    if key.is_empty():
        push_error("SaSensorRegistry: a sensor needs a key.")
        return -1
    if SaSensor.KEYS.has(key):
        push_error("SaSensorRegistry: '%s' is one of Sara's own sensors." % key)
        return -1
    if not reading.is_valid():
        push_error("SaSensorRegistry: sensor '%s' needs a reading." % key)
        return -1
    var entry := Sensor.new(key, reading, additive, module_id)
    var held: Sensor = _by_id.get(entry.id)
    if held != null and held.key == key and held.module != module_id:
        push_error("SaSensorRegistry: '%s' is %s's already." % [key, held.module])
        return -1
    if held != null and held.key != key:
        push_error("SaSensorRegistry: '%s' lands on the id of '%s', %s's. Pick another key." % [key, held.key, held.module])
        return -1
    _by_id[entry.id] = entry
    return entry.id


## Removes every sensor *module_id* registered.
func unregister_module(module_id: StringName) -> void:
    for id: int in _by_id.keys():
        var held: Sensor = _by_id[id]
        if held.module == module_id:
            _by_id.erase(id)


## The sensor of *id*, or null when no module registered one by it.
func sensor(id: int) -> Sensor:
    return _by_id.get(id)


## The id of the sensor *key*, or -1 when no module registered one by it.
func id_of(key: String) -> int:
    var id := id_for(key)
    var held: Sensor = _by_id.get(id)
    return id if held != null and held.key == key else -1


## The keys registered, sorted, so a list of them reads the same each run.
func keys() -> Array[String]:
    var listed: Array[String] = []
    for held: Sensor in _by_id.values():
        listed.append(held.key)
    listed.sort()
    return listed
