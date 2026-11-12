## A filter's Bake, Attach or Layer choice stays as it was last set.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The choice stays, for every filter, across
## sessions. It is one preference, `SaSettings.filter_way`, written by a hand's
## pick and read when a window opens. A fresh profile reads Bake, a saved profile
## brings the pick back, and a window opened where the remembered way is dimmed
## settles on the first open way and leaves the preference as it was.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _key: StringName = &""
var _was_embedding: bool = false
var _path: String = ""

static var scratch_path: String = SaDataRoot.path("test_b12_scratch.cfg")
static var other_path: String = SaDataRoot.path("test_b12_other.cfg")


func before_each() -> void:
    _path = SaSettings.settings_path
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "B12TestHost"
    EventBus.add_child(_host)

    _easel = Bench.easel(Vector2i(256, 256))
    _canvas = SaCanvas.new()
    _canvas.easel = _easel

    _registry = SaFilterRegistry.new()
    _key = SaFilterRegistry.key_for(&"sara-base-modules", SaBrightnessContrastFilter.new())
    _registry.register(SaBrightnessContrastFilter.new(), &"sara-base-modules")
    _easel.compositor.filter_chain.registry = _registry

    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.layer_types = Fixtures.make_registries().layer_types
    _window.watch(_registry)
    _host.add_child(_window)


func after_each() -> void:
    SaSettings.settings_path = _path
    SaSettings.filter_way = "bake"
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(other_path))
    Teardown.free_nodes([_window, _canvas, _easel])
    _window = null
    _canvas = null
    _easel = null
    _registry = null
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding


func test_a_fresh_profile_reads_bake_and_opens_on_it() -> void:
    var fresh := SaSettingsValues.new()
    assert_eq(fresh.filter_way, "bake", "A fresh profile reads Bake")
    fresh.free()
    assert_true(SaSettingsKeys.place_of(&"filter_way").size() == 2, "and the preference has a place in the file")
    _window.open_filter(_key)
    assert_eq(_window.way(), &"bake", "A window opened on it stands on Bake")


func test_a_pick_in_one_filter_opens_the_next_on_it() -> void:
    _window.open_filter(_key)
    _window.way_toggle.pick(&"layer")
    assert_eq(SaSettings.filter_way, "layer", "A hand's pick is written")
    _window.cancel_filter()
    _window.open_filter(_key)
    assert_eq(_window.way(), &"layer", "and the next window opens on Layer")
    assert_eq(_window.describe()["way"], &"layer", "which describe reads")


func test_a_value_written_by_code_is_not_a_pick() -> void:
    _window.open_filter(_key)
    _window.way_toggle.value = &"attach"
    assert_eq(SaSettings.filter_way, "bake", "A write by code leaves the preference as it was")


## The second clause: a profile saved with Attach opens a window on Attach.
func test_a_profile_saved_with_attach_opens_a_window_on_attach() -> void:
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_path)
    _window.open_filter(_key)
    _window.way_toggle.pick(&"attach")
    _window.cancel_filter()
    # Every setter saves, so moving off the value has to happen against another
    # file or the one under test would be overwritten.
    SaSettings.settings_path = ProjectSettings.globalize_path(other_path)
    SaSettings.filter_way = "bake"
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_path)
    SaSettings.load_settings()
    assert_eq(SaSettings.filter_way, "attach", "The profile brings Attach back")
    _window.open_filter(_key)
    assert_eq(_window.way(), &"attach", "and a window opened after reads Attach")


## The third clause: Bake dimmed on a locked layer, Bake remembered.
func test_a_locked_layer_settles_on_attach_and_keeps_bake_remembered() -> void:
    SaSettings.filter_way = "bake"
    _easel.document.active_layer.is_locked = true
    _window.open_filter(_key)
    assert_false(_window.describe()["can_bake"], "Bake is dimmed over the locked layer")
    assert_eq(_window.way(), &"attach", "The toggle settles on Attach")
    assert_eq(SaSettings.filter_way, "bake", "and the preference still reads Bake")
    _window.cancel_filter()
    _easel.document.active_layer.is_locked = false
    _window.open_filter(_key)
    assert_eq(_window.way(), &"bake", "so the next filter that can take Bake opens on it")


func test_a_remembered_way_the_first_run_frees_is_the_thumbs_place() -> void:
    SaSettings.filter_way = "layer"
    _window.open_filter(_key)
    assert_eq(_window.way(), &"layer", "Layer, dimmed until the pass is known, is the place once it runs")
    assert_eq(SaSettings.filter_way, "layer", "and was never written over")
