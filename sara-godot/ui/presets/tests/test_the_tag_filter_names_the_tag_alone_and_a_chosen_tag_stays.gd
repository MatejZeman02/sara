## The tag filter's rows name the tag alone, and a chosen tag stays chosen.
##
## In the Brush Presets docker the tags submenu
## once said 'Tag: <tag>' for no reason, and after clicking one of the tagged
## brushes the filter reset to All. So two claims, each held in both of the
## chooser's hosts that carry a bar behind them, the docker and the brush
## editor's presets fold. The open list reads "All", "air" and the tags, the
## closed button keeps its "Tag: " in front of the chosen one, and a press on a
## preset, a save or a star leaves the filter and the grid where they were.
##
## The docker is built under the real bar, since the bar's own refresh is one of
## the writers of the chooser's tag, and the editor is built detached with the
## load announced by hand, which is how `test_a_stamp_preset_against_noise_settings.gd`
## stands in for the bus.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## The bar builds against a tool machine and the editor builds a scratchpad, both
## of which need a RenderingDevice.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_d9_tag_filter")

var _host: Node = null
var _surface: SaSurface = null
var _machine: ToolMachine = null

## The profile's tag filter as it stood, put back after each test, since a press
## on a tag writes it for every chooser after this one.
var _tag_filter_was: Dictionary = {}


func before_each() -> void:
    _tag_filter_was = SaSettings.preset_tag_filter.duplicate()
    SaSettings.preset_tag_filter = {}
    ScratchFolder.clear(scratch_dir)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)


func after_each() -> void:
    SaSettings.preset_tag_filter = _tag_filter_was
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
        _host = null
    Fixtures.teardown(_surface, _machine)
    ScratchFolder.clear(scratch_dir)


## Four presets, two of them tagged "wet", one "dry" and one of none, over and
## above whatever ships, whose tags are other words.
func _fill(store: SaPresetStore) -> void:
    store.dir = scratch_dir
    store.save_preset("Ink", StampSettingsScript.new(), PackedStringArray(["wet"]))
    store.save_preset("Wash", StampSettingsScript.new(), PackedStringArray(["wet"]))
    store.save_preset("Chalk", StampSettingsScript.new(), PackedStringArray(["dry"]))
    store.save_preset("Plain", StampSettingsScript.new())


## The real bar on a brush, and the docker over it, bound.
func _docker() -> BrushPresetsDocker:
    _host = Node.new()
    # In the tree, because the docker finds the bar's preset group by name from
    # the scene root.
    EventBus.add_child(_host)
    _machine.set_active_tool(&"brush")
    var bar := ToolOptionsBar.new()
    bar.name = "ToolOptionsBar"
    _host.add_child(bar)
    bar.target_tool_machine = _machine
    _fill(bar.preset_store)
    bar._ready()
    var docker := BrushPresetsDocker.new()
    _host.add_child(docker)
    docker.rebind()
    return docker


func _editor() -> SaBrushEditorWindow:
    var store := SaPresetStore.new()
    _fill(store)
    var window := SaBrushEditorWindow.new()
    var specs: Array[SaOptionSpec] = []
    specs.assign(_machine.get_descriptor(&"brush").options)
    window.bind_tool(_machine.get_tool("brush"), specs, store)
    return window


## The rows of the open list, with the two acts a chosen tag adds left out.
func _tag_rows(chooser: SaBrushPresetsChooser) -> Array[String]:
    var rows: Array[String] = []
    for label: String in chooser.tag_option.choice_labels():
        if label != tr("Rename tag...") and label != tr("Delete tag..."):
            rows.append(label)
    return rows


## What a press on the cell of *stored_name* does, which is the signal the host
## listens to.
func _press(chooser: SaBrushPresetsChooser, stored_name: String) -> void:
    chooser.cells.build(-1)
    var cell := chooser.grid.get_node("Cell_%s/Icon" % stored_name.validate_node_name()) as Button
    cell.pressed.emit()


func _wet(chooser: SaBrushPresetsChooser) -> Array[String]:
    var names: Array[String] = []
    names.assign(chooser.store.names_tagged("wet"))
    return names


func _assert_rows_name_the_tag_alone(chooser: SaBrushPresetsChooser, where: String) -> void:
    var rows := _tag_rows(chooser)
    assert_eq(rows[0], "All", "%s: the first row says All and nothing else" % where)
    assert_true(rows.has("wet") and rows.has("dry"), "%s: and the tags follow, named alone: %s" % [where, str(rows)])
    for row: String in rows:
        assert_false(row.begins_with("Tag:"), "%s: the row '%s' does not repeat the word" % [where, row])
    assert_eq(chooser.tag_option.text, "Tag: All", "%s: the closed button says what it is" % where)


func _assert_the_tag_stays(chooser: SaBrushPresetsChooser, after: String, where: String) -> void:
    assert_eq(chooser.chooser_report()["tag"], "wet", "%s: the tag is still chosen after %s" % [where, after])
    assert_eq(chooser.tag_option.text, "Tag: wet", "%s: the button still reads it after %s" % [where, after])
    assert_eq(chooser.visible_names(), _wet(chooser), "%s: and the grid lists only its presets after %s" % [where, after])


func test_the_docker_names_the_tag_alone_and_keeps_it_when_a_preset_is_pressed() -> void:
    var chooser := _docker().chooser
    _assert_rows_name_the_tag_alone(chooser, "docker")
    assert_true(chooser.tag_option.pick_row("wet"), "docker: the row named wet takes the press")
    assert_eq(chooser.tag_option.text, "Tag: wet", "docker: and the closed button reads Tag: wet")
    assert_eq(chooser.visible_names(), ["Ink", "Wash"] as Array[String], "docker: over the two presets that carry it")

    _press(chooser, "Wash")
    _assert_the_tag_stays(chooser, "a press on Wash", "docker")
    assert_eq(String(chooser.chooser_report()["marked"]), "Wash", "docker: the preset pressed is the one marked")
    _press(chooser, "Ink")
    _assert_the_tag_stays(chooser, "a press on Ink", "docker")


## A load from another door, a chord or a scenario's step, is the bar's own
## `load_preset` without the docker's cell in it, and it may load a preset the
## filter does not list.
func test_the_docker_keeps_the_tag_when_a_preset_is_loaded_from_another_door() -> void:
    var docker := _docker()
    var chooser := docker.chooser
    chooser.tag_option.pick_row("wet")
    var bar := ToolOptionsPresets.in_tree(docker)
    assert_true(bar.load_preset("Chalk"), "docker: the bar loads a preset the filter does not list")
    # The panel keeps the preset in hand in its grid where the tag hides it
    # so the grid is the tag's presets and Chalk, and the tag stays.
    var report := chooser.chooser_report()
    assert_eq(report["tag"], "wet", "docker: the tag is still chosen after a load of Chalk by the bar")
    assert_eq(chooser.tag_option.text, "Tag: wet", "docker: the button still reads it after a load of Chalk by the bar")
    assert_eq(String(report["added"]), "Chalk", "docker: and Chalk is added to the grid, being in hand")
    var with_chalk := _wet(chooser)
    with_chalk.push_front("Chalk")
    assert_eq(chooser.visible_names(), with_chalk, "docker: in its place in the order, before Ink and Wash")
    assert_true(bar.load_preset("Wash"), "docker: and one it does")
    _assert_the_tag_stays(chooser, "a load of Wash by the bar", "docker")


func test_the_docker_keeps_the_tag_when_a_preset_is_saved_or_starred() -> void:
    var docker := _docker()
    var chooser := docker.chooser
    chooser.tag_option.pick_row("wet")
    _press(chooser, "Ink")

    # A save from anywhere is the store's own signal, which rebinds the docker.
    chooser.store.save_preset("Soak", StampSettingsScript.new(), PackedStringArray(["wet"]))
    EventBus.preset_store_changed.emit("Soak", true)
    _assert_the_tag_stays(chooser, "a save", "docker")
    assert_true(chooser.visible_names().has("Soak"), "docker: and the grid lists the preset just saved")

    chooser.stars.capture_star("Ink")
    _assert_the_tag_stays(chooser, "a star", "docker")


## A pick that takes the painter to another tool, which a noise preset does from
## the stamp brush, and a switch of tool by any other door, both reach the bar's
## own refresh, which hands the chooser the bar's tag. The bar's tag is the one it
## last filtered its own list by, which is none, and it put the docker's filter
## back on All.
func test_the_docker_keeps_the_tag_across_a_switch_of_tool() -> void:
    var docker := _docker()
    var chooser := docker.chooser
    chooser.tag_option.pick_row("wet")
    _press(chooser, "Ink")
    _machine.set_active_tool(&"eraser")
    _assert_the_tag_stays(chooser, "a switch to the eraser", "docker")
    _machine.set_active_tool(&"brush")
    _assert_the_tag_stays(chooser, "a switch back to the brush", "docker")


func test_the_editor_names_the_tag_alone_and_keeps_it_when_a_preset_is_pressed() -> void:
    var window := _editor()
    var chooser := window.presets_chooser
    _assert_rows_name_the_tag_alone(chooser, "editor")
    assert_true(chooser.tag_option.pick_row("wet"), "editor: the row named wet takes the press")
    assert_eq(chooser.visible_names(), ["Ink", "Wash"] as Array[String], "editor: over the two presets that carry it")

    # The door applies the pick on the bar, which announces it, and the window
    # hears that from the bus.
    window.preset_chosen.connect(func(stored: String) -> void: window._on_preset_loaded(stored))
    _press(chooser, "Wash")
    _assert_the_tag_stays(chooser, "a press on Wash", "editor")
    window.free()


## The fold's chooser keeps the tag through a star and a save as well, and
## through the window being bound again, which is what the door does on every
## open and on every switch of the tool.
func test_the_editor_keeps_the_tag_when_a_preset_is_starred_or_saved_or_the_window_is_bound_again() -> void:
    var window := _editor()
    var chooser := window.presets_chooser
    chooser.tag_option.pick_row("wet")

    chooser.stars.capture_star("Ink")
    _assert_the_tag_stays(chooser, "a star", "editor")

    window.preset_bar.write_named("Soak")
    chooser.refresh()
    assert_true(chooser.store.has_preset("Soak"), "editor: the save wrote the preset")
    _assert_the_tag_stays(chooser, "a save", "editor")

    var specs: Array[SaOptionSpec] = []
    specs.assign(_machine.get_descriptor(&"brush").options)
    window.bind_tool(_machine.get_tool("brush"), specs, chooser.store)
    _assert_the_tag_stays(chooser, "the window being bound again", "editor")
    window.free()


func test_a_tag_deleted_or_left_with_no_preset_puts_the_filter_back_on_all() -> void:
    var chooser := _docker().chooser
    chooser.tag_option.pick_row("wet")
    chooser.store.delete_tag("wet")
    EventBus.preset_store_changed.emit("Ink", true)
    assert_eq(chooser.chooser_report()["tag"], "", "A tag nothing carries any more is no filter")
    assert_eq(chooser.tag_option.text, "Tag: All", "and the button says All")
    assert_eq(chooser.visible_names().size(), chooser.store.list_names().size(), "over every preset")


func test_a_rename_carries_the_filter_to_the_new_word_and_not_to_all() -> void:
    var chooser := _docker().chooser
    chooser.tag_option.pick_row("wet")
    chooser.store.rename_tag("wet", "damp")
    EventBus.preset_store_changed.emit("Ink", true)
    assert_eq(chooser.chooser_report()["tag"], "", "A word no longer in the library is no filter")

    chooser.tag_option.pick_row("damp")
    assert_true(chooser.tag_option.pick_row(tr("Rename tag...")), "The row of the gesture opens its field")
    chooser.tags.field.text = "soaked"
    assert_true(chooser.tags.commit(), "and Enter renames the tag")
    assert_eq(chooser.chooser_report()["tag"], "soaked", "The gesture that renamed it takes the filter along")
    assert_eq(chooser.tag_option.text, "Tag: soaked", "and the button reads the new word")
    assert_eq(chooser.visible_names(), ["Ink", "Wash"] as Array[String], "over the presets that carried the old one")
