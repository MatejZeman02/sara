## A filter reaches a group's layers or the whole picture with Affect all.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The maintainers' ruling of 2026-10-06: a filter "should change the active layer
## or a group. Or all if it is the global one. Maybe we need 'affect all'
## checkbox for the filters." Bake on a group writes every paint layer under it
## the brush may write, as one undo step, and names in the corner the layers it
## passed over. Affect all, the check beside the way toggle, takes Attach to
## the document, Layer to a layer carrying Affect all and Bake to every paint layer.
##
## The picture: Layer 1 outside, and a group holding Lower, Upper and an
## adjustment layer of Brightness/Contrast above them. The dialog is the
## fixture a painter presses, and Brightness/Contrast at +30 is the filter.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(256, 256)
const AT := Vector2i(40, 40)
const OUTSIDE := Color(0.2, 0.3, 0.4, 1.0)
const LOWER := Color(0.25, 0.125, 0.5, 1.0)
const UPPER := Color(0.5, 0.25, 0.125, 1.0)
const BRIGHTER := {"widget": "brightness", "value": 30.0}

var _easel: SaEasel = null
var _doc: SaDocument = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _key: StringName = &""
var _outside: SaLayer = null
var _lower: SaLayer = null
var _upper: SaLayer = null
var _adjustment: SaLayer = null
var _group: SaLayer = null
var _was_embedding: bool = false


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "E2TestHost"
    EventBus.add_child(_host)

    _easel = Bench.easel(SIZE)
    _doc = _easel.document
    _registry = _easel.compositor.filter_chain.registry
    var filter := SaBrightnessContrastFilter.new()
    _key = SaFilterRegistry.key_for(&"sara-base-modules", filter)
    _registry.register(filter, &"sara-base-modules")
    var types := Fixtures.make_registries().layer_types
    _picture(types)

    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.layer_types = types
    _window.watch(_registry)
    _host.add_child(_window)

    SaProblems.pending_refusals = PackedStringArray()
    # The corner lines below are provoked on purpose, so the transcript shows
    # the assertions and not the lines they check.
    SaProblems.announce = false


func after_each() -> void:
    # Both are remembered for the next filter, and no suite leaves them for another.
    SaSettings.filter_way = "bake"
    SaSettings.filter_affect_all = false
    SaProblems.announce = true
    _window.free()
    _window = null
    _canvas.free()
    _canvas = null
    _easel.free()
    _easel = null
    _doc = null
    _registry = null
    _outside = null
    _lower = null
    _upper = null
    _adjustment = null
    _group = null
    _host.free()
    _host = null
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding


## Layer 1 outside, and the group of the header over it, the group active.
func _picture(types: SaLayerTypeRegistry) -> void:
    _outside = _doc.get_node("Layer 1") as SaLayer
    _outside.get_or_create_chunk(Vector2i.ZERO).clear(OUTSIDE)
    var ops := SaLayerOps.new(_doc)
    _lower = ops.add()
    _lower.name = "Lower"
    _lower.get_or_create_chunk(Vector2i.ZERO).clear(LOWER)
    _upper = ops.add()
    _upper.name = "Upper"
    _upper.get_or_create_chunk(Vector2i.ZERO).clear(UPPER)
    _group = ops.group_layers([_lower, _upper])
    _doc.set_active_layer(_upper)
    var values := _registry.get_filter(_key).parameters()
    _adjustment = SaFilterConversion.new(_doc).add_holding(_key, values, types, "Adjustment")
    _doc.set_active_layer(_group)
    _doc.history.reset()
    _doc.undo_redo.clear_history()


func _texel(layer: SaLayer) -> Color:
    return Bench.texel(layer.get_field(Vector2i.ZERO), AT)


## Every paint layer of the picture and the texel each holds now.
func _paint() -> Dictionary[SaLayer, Color]:
    var found: Dictionary[SaLayer, Color] = {}
    for layer in SaFilterOps.new(_doc).targets_of(null):
        if layer.chunks.has(Vector2i.ZERO):
            found[layer] = _texel(layer)
    return found


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


## Opens Brightness/Contrast on the active layer through the registry's door,
## moves it to +30, and answers what the dialog says it is.
func _open() -> Dictionary:
    assert_true(_registry.invoke(_key), "The Filter menu's door opens Brightness/Contrast")
    var tree := Engine.get_main_loop() as SceneTree
    var moved := SaFilterDialogWindow.capture(tree, BRIGHTER)
    assert_true(moved.contains("brightness"), "Brightness moves: %s" % moved)
    _window.dialog.flush_rerun()
    return _window.describe()


func _capture(spec: Dictionary) -> String:
    return SaFilterDialogWindow.capture(Engine.get_main_loop() as SceneTree, spec)


func _refused() -> PackedStringArray:
    return SaProblems.pending_refusals


func _brighter(now: Color, was: Color, what: String) -> void:
    assert_true(now.r > was.r + 1.0e-3 and now.g > was.g + 1.0e-3, "%s is brighter: %s from %s" % [what, now, was])


func _same(now: Color, was: Color, what: String) -> void:
    assert_true(now.is_equal_approx(was), "%s is as it was: %s against %s" % [what, now, was])


## The first requirement: Bake on a group of two paint layers and an
## adjustment layer writes both paint layers, leaves the adjustment, and one
## undo restores both.
func test_bake_on_a_group_writes_its_paint_layers_in_one_step() -> void:
    var said := _open()
    assert_true(said["can_bake"], "Bake is not dimmed on a group")
    assert_eq(said["way"], &"bake", "and the toggle stands on it")
    var record: SaAttachedFilter = _adjustment.filters[0]
    var held := record.parameters.duplicate(true)
    var steps := _steps()
    _window.apply_filter()
    assert_eq(_steps(), steps + 1, "Apply is one step")
    _brighter(_texel(_lower), LOWER, "Lower")
    _brighter(_texel(_upper), UPPER, "Upper")
    _same(_texel(_outside), OUTSIDE, "Layer 1, outside the group,")
    assert_true(_adjustment.chunks.is_empty(), "The adjustment layer is given no paint")
    assert_eq(_adjustment.filters.size(), 1, "and keeps its one record")
    assert_eq(record.parameters, held, "with the values it had")
    assert_true(_group.chunks.is_empty() and _group.filters.is_empty(), "The group itself gains neither paint nor a record")
    var said_lines := _refused()
    assert_eq(said_lines.size(), 1, "One line is said in the corner: %s" % [said_lines])
    assert_true(
        said_lines.size() == 1 and said_lines[0].contains("'%s' stores no paint." % _adjustment.name),
        "naming the adjustment layer and why: %s" % [said_lines]
    )
    _doc.undo_redo.undo()
    _same(_texel(_lower), LOWER, "One undo, and Lower")
    _same(_texel(_upper), UPPER, "and Upper")
    _doc.undo_redo.redo()
    _brighter(_texel(_lower), LOWER, "Redo, and Lower")
    _brighter(_texel(_upper), UPPER, "and Upper")


## A layer the brush may not write is passed over and named with why, and the
## others are written.
func test_a_locked_layer_in_the_group_is_passed_over_and_named() -> void:
    _lower.is_locked = true
    _open()
    _window.apply_filter()
    _same(_texel(_lower), LOWER, "The locked Lower")
    _brighter(_texel(_upper), UPPER, "Upper")
    var said_lines := _refused()
    assert_eq(said_lines.size(), 1, "One corner line: %s" % [said_lines])
    assert_true(said_lines.size() == 1 and said_lines[0].contains("'Lower' is locked."), "names Lower and why: %s" % [said_lines])


## Bake dims on a group only where it would write nothing.
func test_a_group_with_no_layer_to_write_dims_bake() -> void:
    _lower.is_locked = true
    _upper.is_locked = true
    var why := SaFilterApply.way_refusal(_group, &"bake")
    assert_eq(why, "'%s' holds no layer the filter can write, so there is nothing to bake." % _group.name, "The helper says why")
    var said := _open()
    assert_false(said["can_bake"], "Bake is dimmed")
    assert_eq(said["dimmed"].get(&"bake", ""), why, "with that sentence")
    assert_eq(said["way"], &"attach", "and the toggle opens on Attach")
    assert_eq(SaFilterApply.way_refusal(_group, &"bake", true), "", "Affect all would still find Layer 1")
    _capture({"affect_all": true})
    assert_true(_window.describe()["can_bake"], "so a tick opens Bake")
    _capture({"affect_all": false})
    assert_false(_window.describe()["can_bake"], "and an untick dims it again")


## The check is in the dialog beside the toggle, off on a fresh profile, and a
## tick is remembered for the next filter as the way is.
func test_affect_all_starts_off_and_is_remembered() -> void:
    var fresh := SaSettingsValues.new()
    assert_false(fresh.filter_affect_all, "A fresh profile reads Affect all off")
    fresh.free()
    assert_eq(SaSettingsKeys.place_of(&"filter_affect_all").size(), 2, "and the preference has a place in the file")
    var said := _open()
    var check := _window.find_child("AffectAll", true, false) as CheckBox
    assert_not_null(check, "The dialog shows the Affect all check")
    assert_eq(check, _window.affect_all, "the one the window reads")
    assert_eq(check.get_parent(), _window.way_toggle.get_parent(), "in one row with the way toggle")
    assert_false(said["affect_all"], "It opens off")
    var ticked := _capture({"affect_all": true})
    assert_true(ticked.contains("Affect all ticked"), "The door's step ticks it: %s" % ticked)
    assert_true(SaSettings.filter_affect_all, "and the tick is written")
    _window.cancel_filter()
    assert_true(_open()["affect_all"], "so the next filter opens with it ticked")
    _capture({"affect_all": false})
    assert_false(SaSettings.filter_affect_all, "and an untick is written as well")


## Affect all with Attach: the record hangs on the document.
func test_affect_all_attaches_the_record_to_the_document() -> void:
    _doc.set_active_layer(_upper)
    _open()
    _capture({"affect_all": true})
    _capture({"way": "attach"})
    var steps := _steps()
    _window.apply_filter()
    assert_eq(_steps(), steps + 1, "Apply is one step")
    assert_eq(_doc.root_filters.size(), 1, "which hangs the record on the document")
    assert_eq(String(_doc.root_filters[0].key), String(_key), "the filter's own")
    assert_true(_upper.filters.is_empty(), "and none on the active layer")
    _same(_texel(_upper), UPPER, "No pixel of it is written,")


## Affect all with Layer: the filter layer goes above the active layer in its
## group, carrying Affect all, which reaches the whole picture from there.
func test_affect_all_puts_the_filter_layer_above_the_active_one_with_the_property() -> void:
    _doc.set_active_layer(_lower)
    _open()
    _capture({"affect_all": true})
    _capture({"way": "layer"})
    var count := SaLayerOps.new(_doc).layers().size()
    _window.apply_filter()
    assert_eq(SaLayerOps.new(_doc).layers().size(), count + 1, "Apply adds one layer")
    var made := _doc.active_layer
    assert_true(made.is_adjustment(), "the adjustment layer holding the filter")
    assert_eq(made.get_index(), _lower.get_index() + 1, "just above the active layer")
    assert_eq(SaLayerStack.parent_of(made), _group, "in the active layer's group")
    assert_true(made.affects_all, "carrying Affect all")
    assert_eq(String(made.filters[0].key), String(_key), "holding the filter")


## Affect all with Bake: every paint layer of the picture, in one step.
func test_affect_all_bakes_every_paint_layer_in_one_step() -> void:
    var before := _paint()
    assert_true(before.size() >= 3, "The picture has its three paint layers: %s" % [before.keys()])
    _open()
    _capture({"affect_all": true})
    assert_true(_window.describe()["can_bake"], "Bake is open under Affect all")
    var steps := _steps()
    _window.apply_filter()
    assert_eq(_steps(), steps + 1, "Apply is one step")
    for layer: SaLayer in before:
        _brighter(_texel(layer), before[layer], "'%s'" % layer.name)
    assert_true(_adjustment.chunks.is_empty(), "The adjustment layer is given no paint")
    _doc.undo_redo.undo()
    for layer: SaLayer in before:
        _same(_texel(layer), before[layer], "One undo, and '%s'" % layer.name)


## "A check in every filter dialog": every filter the base module registers,
## opened on a paint layer, shows the check in the row with the way toggle. The
## registry is built the way the loader builds it, as the is, so a filter a
## later row adds is counted without this suite naming it.
func test_every_shipped_filters_dialog_shows_the_check() -> void:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    var base := BaseModule.new()
    base.register(registries.context.for_module(base.get_id()))
    var keys := registries.filters.list_keys()
    assert_true(keys.size() >= 15, "The base module's filters are registered: %d" % keys.size())
    for key: StringName in keys:
        if not _registry.has(key):
            _registry.register(registries.filters.get_filter(key), registries.filters.owner_of(key))
    _doc.set_active_layer(_upper)
    var without: Array[String] = []
    for key: StringName in keys:
        _window.open_filter(key)
        var check := _window.affect_all
        if check == null or not is_instance_valid(check) or check.get_parent() != _window.way_toggle.get_parent():
            without.append(String(key))
        _window.cancel_filter()
    assert_eq(without, [] as Array[String], "Every one of the %d dialogs shows Affect all beside the toggle" % keys.size())
