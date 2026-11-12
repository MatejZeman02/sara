## The Recorder shows where it writes and says Stop while it records.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Three faults in one docker. The one control that starts and stops never said
## Stop. The folder was a bare field cut at its end, where the folder's own name
## is. At the size the shipped layouts give it, Make Video was clipped under the
## status. So the button reads Stop while a recording runs, the folder is the
## path row Preferences draws, Settle and Cap are under a fold with the Timelapse
## page's own sentences, and the buttons share one row.
##
## The layout case embeds the docker and sorts its containers by hand, the way
## `test_the_presets_docker_reads_at_factory_settings.gd` does, since an `await`
## drops every assertion after it. The shot is
## `scenarios/the-recorder-shows-where-it-writes-and-says-stop-while-it-records.json`.
extends "res://tests/test_framework.gd"

const DockerScript = preload("res://ui/dockers/recorder/recorder_docker.gd")

const SECTION := "RecorderDocker"

## Where a recording in this suite writes, wiped after each case.
static var scratch_dir: String = SaDataRoot.path("test_n93_recorder")

var _saved_directory: String = ""
var _saved_settle: float = 2.0
var _saved_cap: int = 0
var _was_embedding: bool = false
var _host: Node = null
var _canvas: SaCanvas = null


func before_each() -> void:
    _saved_directory = SaSettings.recorder_directory
    _saved_settle = SaSettings.recorder_settle_seconds
    _saved_cap = SaSettings.recorder_cap_bytes
    SaSettings.recorder_directory = scratch_dir
    _host = Node.new()
    _host.name = "ProbeRecorderHost"
    EventBus.add_child(_host)


func after_each() -> void:
    _host.free()
    _host = null
    if _canvas != null:
        _canvas.free()
        _canvas = null
    var tree := Engine.get_main_loop() as SceneTree
    if _was_embedding != tree.root.gui_embed_subwindows:
        tree.root.gui_embed_subwindows = _was_embedding
    SaSettings.recorder_directory = _saved_directory
    SaSettings.recorder_settle_seconds = _saved_settle
    SaSettings.recorder_cap_bytes = _saved_cap
    _wipe()


func _wipe() -> void:
    if not DirAccess.dir_exists_absolute(scratch_dir):
        return
    for file_name: String in DirAccess.get_files_at(scratch_dir):
        DirAccess.remove_absolute(scratch_dir.path_join(file_name))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_dir))


## The docker under a plain Node, so `_init` runs and `_ready` does not, which is
## all a case about its controls needs.
func _detached() -> RecorderDocker:
    var docker := DockerScript.new() as RecorderDocker
    var holder := Node.new()
    _host.add_child(holder)
    holder.add_child(docker)
    return docker


## A canvas with nothing on it and off the tree, which is all `SaRecorder.start`
## asks for.
func _bind(docker: RecorderDocker) -> void:
    _canvas = SaCanvas.new()
    docker.recorder.bind_canvas(_canvas)


## The size every shipped layout opens the docker at.
func _shipped_size(path: String) -> Vector2i:
    var cfg := ConfigFile.new()
    assert_eq(cfg.load(path), OK, "%s reads" % path)
    return cfg.get_value(SECTION, "size", Vector2i())


## One layout pass from *node* down, the one the engine would run next frame.
func _sort(node: Node) -> void:
    if node is Container:
        (node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child: Node in node.get_children():
        _sort(child)


func test_the_button_says_stop_while_it_records_and_record_after() -> void:
    var docker := _detached()
    _bind(docker)
    assert_eq(docker.record_button.text, "Record", "A docker that is not recording offers Record")

    docker.record_button.button_pressed = true
    assert_true(docker.recorder.recording, "The press starts a recording")
    assert_eq(docker.record_button.text, "Stop", "and the button then says Stop")

    docker.record_button.button_pressed = false
    assert_false(docker.recorder.recording, "The second press stops it")
    assert_eq(docker.record_button.text, "Record", "and the button says Record again")


func test_a_recording_the_cap_stops_puts_record_back() -> void:
    var docker := _detached()
    _bind(docker)
    docker.record_button.button_pressed = true
    docker.recorder.stop("cap")
    assert_false(docker.record_button.button_pressed, "The cap lets the button up")
    assert_eq(docker.record_button.text, "Record", "and it says Record, not Stop")
    assert_true(docker.status.text.begins_with("Stopped, size limit reached."), "while the status says why")


func test_a_start_with_no_canvas_stays_on_record() -> void:
    var docker := _detached()
    SaProblems.announce = false
    SaProblems.attach_sink(func(_line: String, _kind: SaProblems.Kind) -> void: pass)
    docker.record_button.button_pressed = true
    SaProblems.detach_sink()
    SaProblems.announce = true
    assert_false(docker.recorder.recording, "Nothing to record is not a recording")
    assert_false(docker.record_button.button_pressed, "so the button stays up")
    assert_eq(docker.record_button.text, "Record", "and says Record")


func test_the_folder_is_a_path_row_with_the_whole_path_in_its_tooltip() -> void:
    var docker := _detached()
    var shown := docker.folder.find_child("PathLabel", true, false) as SaPathRow.PathLabel
    assert_not_null(shown, "The folder is the path row Preferences draws")
    assert_not_null(docker.folder.find_child("ChooseButton", true, false), "with a button that browses")
    var whole := ProjectSettings.globalize_path(scratch_dir)
    assert_eq(shown.full_path, whole, "It holds the folder the profile names, as the real path")
    assert_eq(shown.tooltip_text, whole, "and the tooltip carries all of it")
    assert_true(shown.mouse_filter != Control.MOUSE_FILTER_IGNORE, "which shows, because the label takes the pointer")
    assert_eq(docker.recorder.directory, scratch_dir, "which is where the recorder writes")


func test_use_default_is_the_recorders_own_folder() -> void:
    var docker := _detached()
    (docker.folder.find_child("DefaultButton", true, false) as Button).pressed.emit()
    var default_folder := SaRecorder.default_directory()
    assert_eq(SaSettings.recorder_directory, default_folder, "Use Default stores the recorder's folder, not an empty path")
    assert_eq(docker.recorder.directory, default_folder, "and the recorder writes there")
    var shown := docker.folder.find_child("PathLabel", true, false) as SaPathRow.PathLabel
    assert_eq(shown.full_path, ProjectSettings.globalize_path(default_folder), "and the row shows it")


func test_a_folder_set_in_preferences_reaches_the_docker() -> void:
    var docker := _detached()
    var elsewhere := SaDataRoot.path("test_n93_recorder_elsewhere")
    SaSettings.recorder_directory = elsewhere
    assert_eq(docker.recorder.directory, elsewhere, "A folder chosen on the Timelapse page is the one the next recording uses")
    var shown := docker.folder.find_child("PathLabel", true, false) as SaPathRow.PathLabel
    assert_eq(shown.full_path, ProjectSettings.globalize_path(elsewhere), "and the docker shows it")
    SaSettings.recorder_settle_seconds = 7.5
    assert_almost_eq(docker.settle.value, 7.5, 0.0001, "The settle time follows as well")
    assert_almost_eq(docker.recorder.settle_seconds, 7.5, 0.0001, "and reaches the recorder")


func test_settle_and_cap_are_folded_with_the_timelapse_pages_sentences() -> void:
    var docker := _detached()
    assert_false(docker.fold.visible, "Settle and Cap open folded")
    assert_true(docker.fold.is_ancestor_of(docker.settle), "Settle is under the fold")
    assert_true(docker.fold.is_ancestor_of(docker.cap), "and so is Cap")
    assert_true(docker.fold_button.text.ends_with("Timing and size limit"), "The header names what it holds")

    var page := SaRecorderPage.new()
    var hints: Array[String] = []
    for node: Node in docker.fold.find_children("*Hint", "Label", true, false):
        hints.append((node as Label).text)
    for key: StringName in [&"settle", &"cap"]:
        var explanation := page.page.row(key).explanation
        assert_false(explanation.is_empty(), "The page explains %s" % key)
        assert_true(hints.has(explanation), "and the fold shows the page's own sentence for %s" % key)
    page.free()
    # The page's titles carry no unit so the boxes do.
    assert_eq(docker.settle.suffix, "s", "Settle's box says seconds")
    assert_eq(docker.cap.suffix, "MB", "and Cap's megabytes")

    docker.fold_button.pressed.emit()
    assert_true(docker.fold.visible, "A press on the header opens the fold")
    docker.fold_button.pressed.emit()
    assert_false(docker.fold.visible, "and a second shuts it")


## The constructor's size is the one every shipped layout gives the docker, so a
## profile with no layout of its own opens it at the size the rows were fitted
## to.
func test_the_constructors_size_is_the_shipped_layouts() -> void:
    var docker := _detached()
    for path: String in [DockerLayoutStore.SHIPPED_DEFAULTS, "res://layouts/default.cfg", "res://layouts/full.cfg"]:
        assert_eq(docker.logical_size, _shipped_size(path), "The docker's own size is %s's" % path)


## At 300 by 270 the row of buttons is whole inside the docker, and Make Video's
## word fits its button.
func test_the_button_row_is_inside_the_docker_at_its_own_size() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var docker := DockerScript.new() as RecorderDocker
    _host.add_child(docker)
    docker.show()
    var shipped := _shipped_size(DockerLayoutStore.SHIPPED_DEFAULTS)
    docker.size = shipped

    var body := Theme.new()
    body.default_font = SaFonts.regular()
    body.default_font_size = SaUI.get_font_size()
    var top := docker._control_node
    top.theme = SaUI.shared_theme if SaUI.shared_theme != null else body
    var column := top.get_node("VBoxContainer") as Control
    _sort(column)
    _sort(column)

    # The scroll's rectangle is the part of the docker the rows are seen in,
    # under the drag bar and inside the window, so a button inside it is one a
    # painter sees without scrolling.
    var scroll := column.get_node("Scroll") as Control
    var seen := Rect2(scroll.global_position - top.global_position, scroll.size)
    assert_true(Rect2(Vector2.ZERO, Vector2(shipped)).encloses(seen), "The rows are seen at %s, inside the docker" % seen)
    for button: Button in [docker.record_button, docker.video_button]:
        var rect := Rect2(button.global_position - top.global_position, button.size)
        assert_true(button.size.x > 0.0 and button.size.y > 0.0, "%s is laid out, %s" % [button.name, rect])
        assert_true(seen.encloses(rect), "%s at %s is whole in the rows seen, %s" % [button.name, rect, seen])
    var needed_height := (scroll.get_child(0) as Control).get_combined_minimum_size().y
    var why := "With the fold shut the rows need %.1f of the %.1f seen, so nothing scrolls" % [needed_height, scroll.size.y]
    assert_true(needed_height <= scroll.size.y, why)
    var row := docker.record_button.get_parent() as Control
    assert_eq(row, docker.video_button.get_parent(), "Record and Make Video share one row")

    var video := docker.video_button
    var font := video.get_theme_font("font")
    var font_size := video.get_theme_font_size("font_size")
    var style := video.get_theme_stylebox("normal")
    var needed := font.get_string_size(video.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + style.get_minimum_size().x
    assert_true(needed <= video.size.x, "'%s' needs %.1f and its button is %.1f" % [video.text, needed, video.size.x])
