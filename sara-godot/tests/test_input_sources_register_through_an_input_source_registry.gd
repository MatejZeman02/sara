## Input sources register through an input-source registry.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## MIDI is a module, which needs somewhere to register where input comes from.
## A stub source is
## registered here through a module's scoped context, the way MIDI and any
## module register one, and each place that would name MIDI is asked the way
## the app asks it: the settings' own signal for `apply`, the state report's
## blocks for `capture_state`, and the input driver the `midi` step calls for
## `simulate`. Unloading the module silences all three. MIDI's own
## registration and the grep of the tree are in the module's suite,
## `modules/sara-base-modules/midi/tests/test_midi_becomes_a_module_of_its_own.gd`.
##
## In `tests/` rather than `core/registry`, because it walks the step's route
## through `harness`, which a core suite does not reach.
extends "res://tests/test_framework.gd"

const InputDriver := preload("res://harness/drivers/sa_input_driver.gd")
const StateReport := preload("res://harness/report/sa_state_report.gd")

## The setting the stub follows, any property `SaSettingsValues` announces.
## MIDI's Listen is the MIDI module's own preference.
const LISTEN := &"advanced_options"


## A source that counts what the registry asks of it.
class Stub:
    extends SaInputSource

    var applied: int = 0
    var released: int = 0
    var captured: int = 0
    var simulated: Array[Dictionary] = []

    func _init(source_id: StringName = &"midi") -> void:
        super(source_id, [LISTEN] as Array[StringName])

    func apply() -> void:
        applied += 1

    func release() -> void:
        released += 1

    func capture_state() -> Dictionary:
        captured += 1
        return {"stub": true, "applied": applied}

    func simulate(spec: Dictionary) -> String:
        simulated.append(spec)
        return "stub heard %s" % JSON.stringify(spec)


var _settings: SaSettingsValues = null
var _registries: SaRegistries = null


func before_each() -> void:
    _settings = SaSettingsValues.new()
    _registries = SaRegistries.new()
    # The registries' own registry follows the painter's profile, so the suite
    # hands one of its own to a context it builds over the app's others.
    _registries.input_sources = SaInputSourceRegistry.new(_settings)
    _registries.build_context(Callable(), Callable())


func after_each() -> void:
    _registries = null
    # A settings node is a Node, so it has to be freed rather than let go.
    if _settings != null:
        _settings.free()
        _settings = null


func test_a_module_registers_a_source_and_it_is_applied_at_start() -> void:
    var scoped := _registries.context.for_module(&"stub-module")
    assert_eq(scoped.input_sources, _registries.input_sources, "A module's scoped context carries the app's registry")
    var stub := Stub.new()
    assert_true(scoped.register_input_source(stub), "A module registers its source through its context")
    assert_eq(_registries.input_sources.source_of(&"midi"), stub, "and the registry answers it by its id")
    assert_eq(stub.applied, 1, "It is applied as it registers, which is the start for a module")


func test_a_setting_the_source_names_applies_it_again_and_another_does_not() -> void:
    var stub := Stub.new()
    _registries.context.for_module(&"stub-module").register_input_source(stub)
    _settings.advanced_options = not _settings.advanced_options
    assert_eq(stub.applied, 2, "The setting it names moved, so it is applied again")
    _settings.ui_scale = _settings.ui_scale + 0.25
    assert_eq(stub.applied, 2, "A setting it does not name leaves it alone")


func test_the_dump_writes_the_sources_block_under_its_id() -> void:
    var stub := Stub.new()
    _registries.context.for_module(&"stub-module").register_input_source(stub)
    var blocks := StateReport.input_source_blocks(_registries.input_sources)
    assert_eq(blocks.get("midi"), {"stub": true, "applied": 1}, "The dump's block is the source's capture_state")
    assert_eq(stub.captured, 1, "asked once for the dump")
    assert_eq(StateReport.input_source_blocks(null), {}, "and a host with no registry writes no block")


func test_the_midi_steps_route_reaches_the_sources_simulate() -> void:
    var stub := Stub.new()
    _registries.context.for_module(&"stub-module").register_input_source(stub)
    var spec := {"control": 7, "value": 64}
    var line := InputDriver.simulate_input(&"midi", spec, _registries.input_sources)
    assert_eq(stub.simulated, [spec] as Array[Dictionary], "The step's spec reaches the source whose id is midi")
    assert_eq(line, "stub heard %s" % JSON.stringify(spec), "and the line the step prints is the source's")


func test_none_of_the_three_after_the_module_unloads() -> void:
    var stub := Stub.new()
    var scoped := _registries.context.for_module(&"stub-module")
    scoped.register_input_source(stub)
    scoped.remove_all_registrations()
    assert_eq(stub.released, 1, "Unloading the module releases its source once")
    assert_null(_registries.input_sources.source_of(&"midi"), "and the registry holds it no more")
    _settings.advanced_options = not _settings.advanced_options
    assert_eq(stub.applied, 1, "A setting moved after the unload applies nothing")
    assert_eq(StateReport.input_source_blocks(_registries.input_sources), {}, "The dump writes no block for it")
    assert_eq(stub.captured, 0, "and never asks it")
    var line := InputDriver.simulate_input(&"midi", {"note": 60}, _registries.input_sources)
    assert_true(stub.simulated.is_empty(), "The step's route reaches it no more")
    assert_true(line.contains("no input source midi"), "and the line says no source took it")


func test_a_source_with_no_id_or_an_id_held_is_refused() -> void:
    var sources := SaInputSourceRegistry.new(_settings)
    assert_true(sources.register(Stub.new(), &"first"), "The first source of an id registers")
    assert_false(sources.register(Stub.new(), &"second"), "A second of the same id is refused")
    assert_false(sources.register(Stub.new(&""), &"third"), "and one with no id")
    assert_false(sources.register(null, &"fourth"), "and no source at all")
    assert_eq(sources.listed().size(), 1, "so the registry holds the one")


func test_the_drive_the_app_hands_reaches_every_module_and_a_bare_one_moves_nothing() -> void:
    var bare := SaControlDrive.new()
    assert_false(bare.can_move(&"layer/opacity"), "A bare drive moves no value")
    assert_true(is_nan(bare.read_ratio(&"layer/opacity")), "and reads none")
    assert_false(bare.choose_preset("Airbrush"), "chooses no preset")
    assert_false(bare.run_filter(&"alpha.sharpen"), "runs no filter")
    var control := Control.new()
    assert_eq(bare.target_of(control), {}, "and binds no click")
    control.free()
    var registries := SaRegistries.new()
    var drive := SaControlDrive.new()
    registries.build_context(Callable(), Callable(), drive)
    assert_eq(registries.context.for_module(&"any").drive, drive, "The drive the app hands is every module's")
