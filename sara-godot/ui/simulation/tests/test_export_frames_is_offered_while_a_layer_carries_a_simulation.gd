## File > Export Frames... is a row of the File menu while the
## document holds a simulation and no row at all while it does not, and its
## dialog runs the steps it is set to, a picture every so many, says where the
## run stands, and stops at Cancel once the picture under way is written.
##
## The dialog is driven by calling its `_process`, so a frame is a call. It is
## added under a host in the tree with subwindows embedded, the way the export
## dialog's own suites open theirs.
extends "res://tests/test_framework.gd"

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const FRAME := 1.0 / 60.0

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _host: Node = null
var _docker: ToolOptionsDocker = null
var _follower: SaSimulationPanel = null
var _folder: String = ""
var _kept_embedding: bool = true


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _surface = Fixtures.make_surface(Vector2i(512, 256))
    _registries = Fixtures.make_registries(_surface)
    var base := BaseModule.new()
    base.register(_registries.context.for_module(base.get_id()))
    _host = Node.new()
    _host.name = "K9ExportFramesTestHost"
    EventBus.add_child(_host)
    _docker = ToolOptionsDocker.new()
    _host.add_child(_docker)
    _follower = SaSimulationPanel.new(_registries, _docker)
    _host.add_child(_follower)
    _folder = SaDataRoot.path("k9-dialog")
    _empty_folder()
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_folder))


func after_each() -> void:
    _host.free()
    _surface.get_document().free()
    _surface.easel.free()
    _surface = null
    _registries = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding
    _empty_folder()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(_folder))
    SaProblems.pending_refusals = PackedStringArray()


func _empty_folder() -> void:
    if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_folder)):
        return
    for file: String in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(_folder.path_join(file)))


## A paint layer of its own with Spread on it, and *active* says whether it is
## the active layer or the background stays so.
func _simulated(active: bool = true) -> SaLayer:
    var document := _surface.get_document()
    var kept := document.active_layer
    var layer := SaLayerOps.new(document).add(&"")
    layer.get_or_create_chunk(Vector2i(0, 0))
    SaSimulation.put_on(layer, _registries.simulation_rules.find(&"spread"))
    document.set_active_layer(layer if active else kept)
    return layer


func _dialog() -> SaSimulationFramesDialog:
    return _follower.find_child(SaSimulationFramesDialog.NODE_NAME, true, false) as SaSimulationFramesDialog


## Moves a row's slider as a drag does, its value and then its signal.
func _slide(dialog: SaSimulationFramesDialog, slider_name: String, to: float) -> void:
    var slider := dialog.find_child(slider_name, true, false) as FactorSlider
    assert_not_null(slider, "The dialog holds %s" % slider_name)
    slider.value = to
    slider.value_changed.emit(to)


func _drive(dialog: SaSimulationFramesDialog, most: int = 200) -> int:
    var frames := 0
    while dialog.running() and frames < most:
        dialog._process(FRAME)
        frames += 1
    return frames


func test_the_file_menu_shows_export_frames_only_while_a_layer_carries_a_simulation() -> void:
    assert_true(_registries.commands.has(SaSimulationPanel.FRAMES_COMMAND), "The follower registers Export Frames...")
    var command := _registries.commands.get_descriptor(SaSimulationPanel.FRAMES_COMMAND)
    assert_eq(command.menu_label(), "Export Frames...", "under the words the row reads")
    assert_eq(command.category, &"file", "among the File commands")
    var popup := SaChoicePopup.new()
    var menu := SaFileMenu.new(popup)
    menu.bind_commands(_registries.commands)
    menu.populate()
    assert_false(command.is_enabled(), "With no simulation the command takes no press")
    assert_eq(menu.command_at(SaFileMenu.ID_EXPORT_FRAMES), &"", "and File has no row for it, not even a dim one")
    assert_false(_follower.open_frames(), "and running it opens nothing")
    assert_null(_dialog(), "so no dialog is built")
    var layer := _simulated(false)
    menu.populate()
    assert_true(command.is_enabled(), "A layer that is not active but carries a simulation is enough")
    assert_eq(menu.command_at(SaFileMenu.ID_EXPORT_FRAMES), SaSimulationPanel.FRAMES_COMMAND, "File shows the row")
    assert_eq(SaSimulation.simulated_layer(_surface.get_document()), layer, "and the run would step that layer")
    SaSimulation.take_off(layer)
    menu.populate()
    assert_eq(menu.command_at(SaFileMenu.ID_EXPORT_FRAMES), &"", "Taking the rule off takes the row away again")
    popup.free()


func test_the_dialog_runs_five_steps_as_five_pngs_and_closes_when_they_are_written() -> void:
    var layer := _simulated()
    assert_true(_registries.commands.execute(SaSimulationPanel.FRAMES_COMMAND), "The command runs")
    var dialog := _dialog()
    assert_not_null(dialog, "and opens the dialog")
    assert_true(dialog.visible, "shown")
    var opened := dialog.report()
    assert_eq(opened["format"], "png8", "PNG at eight bits first, the export dialog's own first")
    assert_eq(opened["format_label"], "PNG, 8 bits", "said on the format row")
    assert_eq(opened["steps"], SaSimulationFramesDialog.DEFAULT_STEPS, "Ten steps unless the painter says")
    assert_true(String(opened["title"]).contains("at step 0"), "The title says where the layer stands: %s" % opened["title"])
    _slide(dialog, "ExportFramesSteps", 5.0)
    var asked := dialog.report()
    assert_eq(asked["steps"], 5, "The steps row sets the run's steps")
    assert_eq(asked["result"], "5 pictures, of steps 1 to 5. PNG, 8 bits", "and the result says what will be written")
    dialog.start(_folder.path_join("spread"))
    assert_true(dialog.running(), "The run starts")
    assert_eq(dialog.report()["export_enabled"], false, "and Export... takes no second press while it runs")
    var frames := _drive(dialog)
    assert_eq(frames, 5, "a step and a picture a frame")
    var done := dialog.report()
    var names: Array = done["written"].map(func(each: Dictionary) -> String: return each["file"])
    assert_eq(
        names,
        ["spread_0001.png", "spread_0002.png", "spread_0003.png", "spread_0004.png", "spread_0005.png"],
        "A name with no extension takes the format's, and the steps are padded"
    )
    assert_eq(done["listed"], names, "The folder holds the five and nothing else of the run")
    for each: Dictionary in done["written"]:
        assert_eq(each["size"], [512, 256], "%s reads back at the canvas's size" % each["file"])
    assert_eq(done["layer_step"], 5, "The layer stands at the last step written")
    assert_false(SaSimulation.record_of(layer).playing, "paused")
    assert_false(dialog.visible, "and the dialog closes once every picture is written")


func test_stop_finishes_the_picture_under_way_and_the_dialog_says_where_the_run_stood() -> void:
    _simulated()
    _follower.open_frames()
    var dialog := _dialog()
    _slide(dialog, "ExportFramesSteps", 50.0)
    _slide(dialog, "ExportFramesEvery", 10.0)
    assert_eq(dialog.report()["result"], "5 pictures, of steps 10 to 50. PNG, 8 bits", "A picture every ten of fifty")
    dialog.start(_folder.path_join("stopped.jpeg"))
    dialog._process(FRAME)
    var cancel := dialog.find_child("ExportFramesCancel", true, false) as Button
    assert_eq(cancel.text, "Stop", "While it runs Cancel reads Stop")
    cancel.pressed.emit()
    assert_true(dialog.running(), "and the picture under way is still written")
    _drive(dialog)
    var stopped := dialog.report()
    assert_eq(
        stopped["written"].map(func(each: Dictionary) -> String: return each["file"]),
        ["stopped_0010.png"],
        "One picture, its name's other format's extension changed to the row's"
    )
    assert_true(dialog.visible, "The dialog stays open")
    assert_eq(
        stopped["progress"],
        "Stopped at step 10, 1 of 5 pictures written, the last stopped_0010.png.",
        "and says where the run stood"
    )
    assert_eq(cancel.text, "Cancel", "Cancel reads Cancel again")
    dialog.start(_folder.path_join("closed.png"))
    dialog._process(FRAME)
    dialog.hide()
    _drive(dialog)
    assert_eq(dialog.run.written.size(), 1, "Closing the dialog while it runs stops it the same way")
    assert_eq(SaSimulation.record_of(_surface.get_document().active_layer).steps, 20, "at a step it wrote")
