## Registering the app's commands a second time in one process
## leaks nothing.
##
## `SaAppCommands.register_all` run more than
## once in one process left about 210 objects behind for each run after the
## first, and `run_tests.sh` failed every run that did on "resources leaked".
## Export Effects as LUT, Isolate Active Layer and Edit Smart Layer Contents
## captured the scoped `SaContext`, which holds the command registry that holds
## the command, so each was a ring. They now hold a bare context with only the
## providers, and this suite reads both halves: the count of objects comes back
## after two registrations are let go, and the commands still answer.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The easel the second half paints on needs a RenderingDevice.
const REQUIRES_GPU := true

const LUT := &"layer_export_lut"
const ISOLATE := &"view_isolate_active_layer"

var _saved_events: Dictionary = {}
var _surface: SaSurface = null


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()


func after_each() -> void:
    if _surface != null:
        SaLocalView.forget(_surface.easel.document)
        Fixtures.teardown(_surface)
        _surface = null
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        if not InputMap.has_action(action):
            continue
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)


## Fresh registries with every app command on them, let go when it returns.
## Answers a weak reference to the command registry, which a ring through a
## command's callable would keep alive. `register_builtins` files the skeleton
## module in `ModuleLoader.loaded_modules`, which holds the newest registries
## until the next takes its place, as the app's one set is held, so its entry
## is taken out. Never `ModuleLoader.unload_all()`, whose unregistering takes
## the commands out of the registry and so breaks a ring this suite is there to
## find: with it the suite passed on the base.
func _register_and_drop() -> WeakRef:
    var registries := Fixtures.make_registries()
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    ModuleLoader.loaded_modules.erase(registries.skeleton_module.get_id())
    return weakref(registries.commands)


func _objects() -> int:
    return int(Performance.get_monitor(Performance.OBJECT_COUNT))


## One registration first, because it fills caches the built-ins keep for the
## process, 129 objects when measured. Each registration also starts the
## search's warm-up timer, a `SceneTreeTimer` the tree holds for three seconds
## and frees when it fires, which a test cannot await, so the count allows one
## object for each of the two registrations measured. Before the fix each was
## about 250.
func test_two_registrations_let_go_leave_the_object_count_where_it_started() -> void:
    _register_and_drop()
    var before := _objects()
    var first := _register_and_drop()
    var second := _register_and_drop()
    assert_null(first.get_ref(), "the first registration's command registry is freed once let go")
    assert_null(second.get_ref(), "and so is the second's")
    first = null
    second = null
    var after := _objects()
    var warm_up_timers := 2
    assert_eq(after - before - warm_up_timers, 0, "two registrations of the app's commands, both let go, leave no object behind")


func test_the_lut_and_isolate_commands_still_run_and_answer_after_a_third() -> void:
    _register_and_drop()
    _register_and_drop()
    _surface = Fixtures.make_surface()
    var registries := Fixtures.make_registries(_surface)
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var commands := registries.commands
    var document := _surface.easel.document
    var lut := commands.get_descriptor(LUT)
    var isolate := commands.get_descriptor(ISOLATE)
    assert_not_null(lut, "Export the effects as a LUT is registered")
    assert_not_null(isolate, "Isolate the active layer is registered")
    if lut == null or isolate == null:
        return

    assert_false(bool(lut.enabled.call()), "a plain active layer has no effects to export, so the row is greyed")
    var group := SaLayerOps.new(document).group_active()
    document.set_active_layer(group)
    assert_true(bool(lut.enabled.call()), "a group active on the main canvas has effects to export")
    var tree := Engine.get_main_loop() as SceneTree
    var scene := tree.current_scene if tree != null else null
    var opened := commands.execute(LUT)
    var dialog := scene.get_node_or_null(SaEffectsLut.DIALOG_NAME) if scene != null else null
    assert_true(lut.handler.is_valid(), "the LUT command's handler is alive after it ran")
    assert_eq(opened, dialog != null, "the LUT command answers whether it opened its window, and it opens where a scene is")
    if dialog != null:
        dialog.free()

    assert_false(bool(isolate.checked.call()), "isolation starts off")
    assert_true(commands.execute(ISOLATE), "Isolate the active layer runs on the main canvas")
    assert_true(bool(isolate.checked.call()), "and its row reads checked")
    assert_true(commands.execute(ISOLATE), "a second press runs too")
    assert_false(bool(isolate.checked.call()), "and puts every layer back, the row unchecked")
