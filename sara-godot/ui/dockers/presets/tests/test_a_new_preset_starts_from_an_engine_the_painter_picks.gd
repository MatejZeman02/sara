## A new preset starts from an engine the painter picks.
##
## The brush engine is chosen in a dialog window, because if a user deletes all
## of the presets they could not otherwise create a new one. So the suite empties a scratch store,
## never the painter's own, opens New preset... from the menu a right press on
## the empty grid opens, and makes one preset of each engine the registry holds,
## the stamp and the noise engine, reading each back off the disk with its
## engine.
##
## The right press goes in through the docker window's GUI pass, `push_input`,
## because the claim is that a press on the grid outside every cell reaches the
## chooser at all, and a call of its handler would prove the handler only. The
## suite cannot advance a frame, so the layout is made by hand, as the tile
## suite makes its own.
extends "res://tests/test_framework.gd"

## The machine builds every tool, which needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")
const NoiseSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const LiquifySettingsScript = preload("res://modules/sara-base-modules/base/liquify/liquify_settings.gd")

## The two a painter had before deleting them, one of each engine.
const BEFORE: Array[String] = ["Seed Ink", "Seed Grain"]

static var scratch_dir: String = SaDataRoot.path("test_d7_a_new_preset_starts_from_an_engine")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _host: Node = null
var _bar: ToolOptionsBar = null
var _docker: BrushPresetsDocker = null
var _was_embedding: bool = false


func before_each() -> void:
    _clear()
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    # The stamp first, as the app loads it, so a fresh machine starts on the
    # Brush rather than on the fill.
    _modules.clear()
    for script: GDScript in [StampModuleScript, BaseModuleScript, NoiseModuleScript]:
        var module: SaModule = script.new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)
    _machine.set_active_tool(&"brush")


func after_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var left := SaMessage.live_dialog(tree)
    if left != null:
        left.queue_free()
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
        _host = null
        _bar = null
        _docker = null
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    for module: SaModule in _modules:
        module.unregister(_registries.context)
        _registries.context.for_module(module.get_id()).remove_all_registrations()
    _modules.clear()
    _registries = null
    tree.root.gui_embed_subwindows = _was_embedding
    _clear()


## The bar over the scratch store with one preset of each engine in it, the
## Brush Presets docker beside it, and the dialog on the bar's group handed the
## suite's registry, which is the one thing a suite has and the app finds on its
## main scene.
func _shelf() -> void:
    _host = Node.new()
    _host.name = "D7NewPresetHost"
    EventBus.add_child(_host)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    _bar.preset_store.save_preset(BEFORE[0], StampSettingsScript.new())
    _bar.preset_store.save_preset(BEFORE[1], NoiseSettingsScript.new())
    _bar._ready()
    _bar.preset_box.add_child(SaNewPresetDialog.new(_registries.tools))
    _docker = BrushPresetsDocker.new()
    _host.add_child(_docker)
    _docker.show()
    # Taller than the window opens by itself, so that one cell leaves grid under
    # it for the press this suite is about. A tip, which is what a fresh profile
    # draws, is square and fills a short docker on its own.
    _docker.size = Vector2i(310, 460)
    _docker.rebind()


## Every preset deleted the way the docker's Delete deletes one: loaded, then
## the bar's delete, which tells the grid.
func _delete_every_preset() -> void:
    for preset_name: String in _bar.preset_names():
        _bar.load_preset(preset_name)
        _bar.delete_loaded_preset()


## The dialog on the bar's group.
func _dialog() -> SaNewPresetDialog:
    return _bar.preset_box.get_node_or_null(SaNewPresetDialog.NODE_NAME) as SaNewPresetDialog


## A right press and its release at *at*, in the docker window's own units,
## through the window's GUI pass.
func _right_press(at: Vector2) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_RIGHT
    event.pressed = true
    event.position = at
    event.global_position = at
    _docker.push_input(event, true)
    var release := event.duplicate() as InputEventMouseButton
    release.pressed = false
    _docker.push_input(release, true)


## The layout the next frame would make, by hand.
func _lay_out() -> void:
    for _pass in 3:
        _sort(_docker)


func _sort(node: Node) -> void:
    if node is Container:
        node.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children():
        _sort(child)
    if node is Control:
        (node as Control).update_minimum_size()


## A point on the grid under every cell: the chooser's own foot, which no tile
## reaches in a library of none or one.
func _under_the_cells() -> Vector2:
    _lay_out()
    var chooser := _docker.chooser.get_global_rect()
    return Vector2(chooser.get_center().x, chooser.end.y - 4.0)


## The middle of the empty library's line, which takes the grid's place, and so
## where a painter told to right-click there does.
func _on_the_line() -> Vector2:
    _lay_out()
    return _docker.chooser.empty_line.get_global_rect().get_center()


## The engines the registry holds, in its own order, which is what the dialog has
## to offer: the stamp's Brush, Eraser and fill take one engine, and liquify
## and the noise engine are the others.
func test_the_dialog_lists_every_registered_engine_once() -> void:
    var engines := SaNewPresetDialog.registered_engines(_registries.tools)
    var ids: Array = engines.map(func(entry: Dictionary) -> StringName: return entry["engine"])
    assert_eq(ids, [&"stamp", &"liquify", &"noise"], "One row per engine, once each, in registration order")
    var labels: Array = engines.map(func(entry: Dictionary) -> String: return entry["label"])
    assert_eq(labels, ["Stamp", "Liquify", "Noise"], "Each by the name a cell's engine line uses")
    assert_eq(SaNewPresetDialog.registered_engines(null), [] as Array[Dictionary], "A host with no registry offers none")


## The whole case: a store emptied of every preset, the dialog opened from
## the empty grid's menu, one preset made of each engine, and each read back off
## the disk with the engine it was made of.
func test_an_emptied_library_makes_one_preset_of_each_engine_from_the_grids_menu() -> void:
    _shelf()
    _delete_every_preset()
    assert_eq(_bar.preset_names(), [] as Array[String], "Every preset is gone")
    assert_eq(_docker.chooser.visible_names(), [] as Array[String], "and the grid is empty")
    assert_true(_docker.chooser.empty_line.visible, "The empty library shows its line")
    assert_true(_docker.chooser.empty_line.text.contains("New Preset..."), "which names the door")

    var made: Dictionary = {}
    for entry: Dictionary in SaNewPresetDialog.registered_engines(_registries.tools):
        var engine: StringName = entry["engine"]
        # On the line while there is one, then under the first preset's cell.
        _right_press(_on_the_line() if made.is_empty() else _under_the_cells())
        var menu := _docker.chooser.tags.menu
        assert_true(menu.visible, "A right press on the grid outside every cell opens the menu")
        assert_eq(menu.row_ids()[0], SaBrushPresetTags.NEW_PRESET_ID, "with New preset... at its head")
        if made.is_empty():
            assert_eq(menu.row_ids().size(), 1, "and, with no preset under the press, nothing else")
        assert_true(menu.press_row(SaBrushPresetTags.NEW_PRESET_ID), "The row is pressed")
        var dialog := _dialog()
        assert_true(dialog.visible, "and New preset... opens")
        assert_true(dialog.capture_dialog({"pick": String(engine)}).contains('"picked":"%s"' % engine), "on %s" % engine)
        var stored := dialog.create()
        assert_false(stored.is_empty(), "Create writes a %s preset" % engine)
        assert_false(dialog.visible, "and closes the dialog")
        assert_eq(_bar.selected_preset_name(), stored, "The new preset is the one in the hand")
        assert_eq(_docker.chooser.chooser_report()["marked"], stored, "and the grid marks its cell")
        assert_false(_docker.chooser.empty_line.visible, "The empty line goes with the first preset")
        made[stored] = engine

    assert_eq(made.size(), 3, "One preset of each engine")
    var scripts := {&"stamp": StampSettingsScript, &"liquify": LiquifySettingsScript, &"noise": NoiseSettingsScript}
    var fresh := SaPresetStore.new()
    fresh.dir = scratch_dir
    for stored: String in made:
        assert_eq(fresh.engine_for(stored), made[stored], "'%s' is saved as a %s preset" % [stored, made[stored]])
        var on_disk := fresh.load_preset(stored)
        var script: Script = scripts[made[stored]]
        assert_eq(on_disk.get_script(), script, "with that engine's own settings class")
    assert_eq(_machine.active_tool_name, NoiseModuleScript.TOOL_ID, "The noise preset took the Brush onto its engine")


## A cell's menu carries New preset... at its head as well, above Convert to
## and the tags, so the door is the first row wherever the right press lands.
func test_a_cells_menu_opens_on_new_preset_too() -> void:
    _shelf()
    var tags := _docker.chooser.tags
    tags.open_menu_for(BEFORE[0], null)
    assert_eq(tags.menu.row_ids()[0], SaBrushPresetTags.NEW_PRESET_ID, "New preset... heads a cell's menu")
    assert_true(tags.menu.row_ids().has(SaBrushPresetTags.NEW_TAG_ID), "and the tag rows are still under it")
    tags.menu.hide()


## The docker's New preset... button opens the same dialog, on the engine in
## hand, and the bar's preset in hand is left where it was until Create.
func test_the_dockers_button_opens_the_same_dialog_on_the_engine_in_hand() -> void:
    _shelf()
    _bar.load_preset(BEFORE[1])
    _docker.new_button.pressed.emit()
    var dialog := _dialog()
    assert_true(dialog.visible, "The button opens New preset...")
    assert_eq(dialog.picked_engine(), &"noise", "on the engine in hand")
    assert_eq(dialog.dialog_report()["name"], "New Noise preset", "with a free name for it")
    assert_eq(_bar.selected_preset_name(), BEFORE[1], "and nothing is loaded or written until Create")
    dialog.pick(0)
    assert_eq(dialog.dialog_report()["name"], "New Stamp preset", "A pick moves the name it offered")
    dialog.hide()


## A name that is empty once made fit for a file, or one the store already
## holds, keeps the dialog open and says why. Nothing is written over.
func test_an_empty_or_a_taken_name_writes_nothing() -> void:
    _shelf()
    var dialog := SaNewPresetDialog.open_from(_docker)
    var before := _bar.preset_names()
    dialog.capture_dialog({"name": "  ..  "})
    assert_eq(dialog.create(), "", "A name of dots and spaces writes nothing")
    assert_eq(dialog.dialog_report()["said"], "A preset needs a name.", "and the line asks for one")
    dialog.capture_dialog({"pick": "stamp", "name": BEFORE[1]})
    assert_eq(dialog.create(), "", "A taken name writes nothing")
    assert_true(String(dialog.dialog_report()["said"]).begins_with("'Seed Grain' is taken"), "and the line says so")
    assert_eq(_bar.preset_store.engine_for(BEFORE[1]), &"noise", "The noise preset under that name is kept")
    assert_eq(_bar.preset_names(), before, "and the library is as it was")
    assert_true(dialog.visible, "The dialog stays open for another name")
    dialog.hide()


## The scratch store, its thumbnails and its tag file, so a run starts empty.
func _clear() -> void:
    if not DirAccess.dir_exists_absolute(scratch_dir):
        return
    var thumbs := SaPresetThumbs.thumbs_dir(scratch_dir)
    if DirAccess.dir_exists_absolute(thumbs):
        for file_name: String in DirAccess.get_files_at(thumbs):
            DirAccess.remove_absolute(thumbs.path_join(file_name))
        DirAccess.remove_absolute(thumbs)
    for file_name: String in DirAccess.get_files_at(scratch_dir):
        DirAccess.remove_absolute(scratch_dir.path_join(file_name))
    DirAccess.remove_absolute(scratch_dir)
