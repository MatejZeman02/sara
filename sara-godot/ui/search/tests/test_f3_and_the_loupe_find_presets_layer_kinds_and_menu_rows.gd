## F3 and the loupe find a brush preset, a kind of layer the
## Layer menu adds, a module's kind with no menu row written for it, and a
## menu's own row, and a pick of each does what the painter's own press does.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## F3 and quick search (loupe) also search the current brush presets and things
## like new layer and new canvas layer. Almost anything is findable there.
##
## The doors are the app's own: the commands `SaAppCommands.register_all`
## registers, a real `TopMenuBar` whose Layer menu is pointed at an easel's
## document, the bar's preset group in the tree in front of a stamp brush's
## settings with its store in a scratch folder, and `SaSearchWindow`, the one
## list F3 and the loupe open, read here by its rows'
## titles the way a press on F3's list reads them and by its entries the way
## Enter in the loupe's did. What a painter sees is
## `scenarios/f3-and-the-loupe-also-find-brush-presets.json`.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

const MODULE := &"moss_module"
const MOSS := &"moss"
const PRESET := "Moss Wash"

static var scratch_dir: String = SaDataRoot.path("test_search_presets")

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _host: Node = null
var _bar: TopMenuBar = null
var _box: ToolOptionsPresets = null
var _settings: Resource = null
var _window: SaSearchWindow = null
var _was_embedding := false
var _actions_before: Array[StringName] = []


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _actions_before = InputMap.get_actions()
    ScratchFolder.empty(scratch_dir)
    _host = Node.new()
    _host.name = "U112SearchHost"
    EventBus.add_child(_host)

    _registries = Fixtures.make_menu_registries()
    _easel = SaEasel.create_default(Vector2i(256, 256))
    _easel.compositor.set_registry(_registries.blend_modes)

    _bar = TopMenuBar.new()
    _host.add_child(_bar)
    _bar.bind_commands(_registries.commands)
    var layer_menu := _bar.menu("Layer") as SaLayerMenu
    layer_menu.document = _easel.document
    layer_menu.layer_types = _registries.layer_types

    _settings = StampSettingsScript.new()
    _box = ToolOptionsPresets.new()
    _box.preset_store.dir = scratch_dir
    _box.settings_source = func() -> Resource: return _settings
    var recipe := StampSettingsScript.new()
    recipe.radius = 0.037
    _box.preset_store.save_preset(PRESET, recipe)
    _host.add_child(_box)

    _window = SaSearchWindow.new(SaSearchIndex.new(_registries.context))
    _host.add_child(_window)


func after_each() -> void:
    _registries.context.for_module(MODULE).remove_all_registrations()
    _host.free()
    _host = null
    _easel.free()
    _easel = null
    _registries = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding
    ScratchFolder.empty(scratch_dir)
    for action: StringName in InputMap.get_actions():
        if not _actions_before.has(action):
            InputMap.erase_action(action)


# --- The two searches -----------------------------------------------------------


## The list open, narrowed to *text* as typing into its field does.
func _f3(text: String) -> SaChoicePopup:
    _window.open()
    _window.search.text = text
    _window.search.text_changed.emit(text)
    return _window


## The row of *list* whose title is *label*, among those drawn, or `&""`.
func _f3_row(list: SaChoicePopup, label: String) -> StringName:
    for row_id: StringName in list.row_ids():
        if list.is_row_shown(row_id) and list.label_button(row_id).text == label:
            return row_id
    return &""


## The loupe opened and *text* typed into its field.
func _loupe(text: String) -> Array[SaSearchIndex.Entry]:
    _window.open()
    _window.field.text = text
    _window.field.text_changed.emit(text)
    return _window.shown


func _loupe_row(text: String, title: String) -> SaSearchIndex.Entry:
    for entry: SaSearchIndex.Entry in _loupe(text):
        if entry.title == title:
            return entry
    return null


func _kinds_of_layer() -> Array[StringName]:
    var out: Array[StringName] = []
    for child in _easel.document.get_children():
        var layer := child as SaLayer
        if layer != null:
            out.append(layer.layer_type)
    return out


# --- A brush preset -------------------------------------------------------------


## The preset's name typed into the loupe finds it as a Brush Preset row, under
## the docker that shows it, and Enter makes it the preset in hand.
func test_the_loupe_finds_a_preset_by_name_and_a_pick_loads_it() -> void:
    var entry := _loupe_row("moss wash", PRESET)
    assert_true(entry != null, "The loupe lists the preset by its name")
    assert_eq(entry.kind, SaSearchActions.PRESET, "and says it is a brush preset")
    assert_eq(entry.place, SaSearchActions.PRESETS_PLACE, "found in Brush Presets")
    assert_eq(_window.shown[_window.marked_at], entry, "It is the row marked")
    _window.field.text_submitted.emit(_window.field.text)
    assert_eq(_box.selected_preset, PRESET, "Enter makes it the preset in hand")
    assert_almost_eq(float(_settings.get("radius")), 0.037, 0.0001, "and its brush is the one on the bar")


## The same name typed into F3 finds the same preset, and a press loads it.
func test_f3_finds_the_preset_and_a_press_loads_it() -> void:
    var list := _f3("moss wash")
    var row := _f3_row(list, PRESET)
    assert_false(row.is_empty(), "F3 lists the preset")
    assert_eq((list.row_of(row).get_node("Place") as Label).text, SaSearchActions.PRESETS_PLACE, "under Brush Presets")
    assert_eq((list.row_of(row).get_node("Kind") as Label).text, SaSearchActions.PRESET, "with its kind in its column")
    assert_true(list.press_row(row), "Its row can be pressed")
    assert_eq(_box.selected_preset, PRESET, "and the press makes it the preset in hand")


# --- A kind of layer ------------------------------------------------------------


## "new paper layer" in the loupe finds the Paper row, and the pick adds a
## Paper through the Layer menu's own row, as one history step.
func test_new_paper_layer_in_the_loupe_adds_a_paper_through_the_layer_menu() -> void:
    var entry := _loupe_row("new paper layer", "New Paper Layer")
    assert_true(entry != null, "The loupe lists New Paper Layer")
    assert_eq(entry.kind, SaSearchActions.LAYER, "and says it is a layer")
    var before := _kinds_of_layer().size()
    var steps := _easel.document.undo_redo.get_history_count()
    _window.pick(entry)
    assert_eq(_kinds_of_layer().size(), before + 1, "The pick adds one layer")
    assert_true(_kinds_of_layer().has(&"paper"), "and it is a Paper")
    assert_eq(_easel.document.undo_redo.get_history_count(), steps + 1, "as one history step, the menu's")


## The kind's own word in F3 finds the Canvas row under Layer, and a press adds
## a Canvas.
func test_f3_finds_a_kind_by_its_own_word_and_a_press_adds_it() -> void:
    var list := _f3("canvas")
    var row := _f3_row(list, "New Canvas Layer")
    assert_false(row.is_empty(), "F3 lists New Canvas Layer")
    assert_true(list.press_row(row), "Its row can be pressed")
    assert_true(_kinds_of_layer().has(&"canvas"), "and the press adds a Canvas")


## A module's kind, registered with no menu row written for it, is a row of
## both searches.
func test_a_modules_kind_is_a_row_of_both_searches() -> void:
    var schema: Array[SaFieldSpec] = [SaFieldSpec.albedo()]
    var moss := SaLayerTypeDescriptor.create(MOSS, schema)
    moss.display_name = "Moss"
    assert_true(_registries.context.for_module(MODULE).register_layer_type(moss), "The module registers its kind")
    var entry := _loupe_row("moss", "New Moss Layer")
    assert_true(entry != null, "The loupe lists the module's kind")
    var list := _f3("moss")
    var row := _f3_row(list, "New Moss Layer")
    assert_false(row.is_empty(), "and so does F3")
    entry = _window.entry_of(row)
    _window.pick(entry)
    assert_true(_kinds_of_layer().has(MOSS), "and a pick adds a layer of it")


# --- A menu's own row -----------------------------------------------------------


## A View row no command stands for is a Menu row of both searches, and a pick
## presses it as a click on it would.
func test_a_menu_row_with_no_command_is_found_and_pressed() -> void:
    var view := _bar.menu("View")
    view.populate()
    var shown := view.is_item_checked(SaViewMenu.ID_TOOL_OPTIONS)
    var entry := _loupe_row("tool options bar", "Show Tool Options Bar")
    assert_true(entry != null, "The loupe lists Show Tool Options Bar")
    assert_eq(entry.kind, SaSearchActions.MENU, "as a menu row")
    assert_eq(entry.place, "View", "of the View menu")
    var list := _f3("tool options bar")
    var row := _f3_row(list, "Show Tool Options Bar")
    assert_false(row.is_empty(), "F3 lists it too")
    _window.pick(_window.entry_of(row))
    await (Engine.get_main_loop() as SceneTree).process_frame
    assert_eq(view.is_item_checked(SaViewMenu.ID_TOOL_OPTIONS), not shown, "and the pick flips its tick")
    view.on_id_pressed(SaViewMenu.ID_TOOL_OPTIONS)
