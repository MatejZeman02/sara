## The ants march in a painter's Sara whose Local Server is open.
##
## The ants must march in a painter's session. Modules › Local Server
## adds a capture node with no scenario, and that node held the ants of every
## selection overlay still, as a scenario's shots need, so the door's
## dump read `"ant_speed": 0.0` in a painter's session. The hold is now a
## constructor argument: a node the command line builds holds them as before,
## and the Local Server's door holds them only for the frame a shot draws.
##
## The door is opened the way the command opens it, through
## `SaCapture.connect_an_agent`, with an overlay in the tree before it opens and
## one added after. The command-line run is the node `from_command_line` builds,
## whose constructor takes the hold's default.
extends "res://tests/test_framework.gd"

static var scratch_known: String = SaDataRoot.path("door/door.json")
static var scratch_out_dir: String = SaDataRoot.path("ants")

var _parent: Node = null
var _kept_embedding: bool = true
var _hosts: Array[SaCanvas] = []


func before_each() -> void:
    if FileAccess.file_exists(scratch_known):
        DirAccess.remove_absolute(scratch_known)
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    # The dialog is a window, and one the root does not embed maps a real OS
    # window and stalls the run.
    tree.root.gui_embed_subwindows = true
    _parent = Node.new()
    _parent.name = "U581AntsHost"
    EventBus.add_child(_parent)
    _hosts = []


func after_each() -> void:
    if is_instance_valid(_parent):
        _parent.free()
    _parent = null
    for host: SaCanvas in _hosts:
        host.free()
    _hosts = []
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding


func test_a_local_server_opened_in_a_running_sara_leaves_the_ants_marching() -> void:
    var before := _overlay_in_the_tree()
    SaCapture.connect_an_agent(_parent, scratch_known)
    var door := _capture()
    assert_not_null(door, "Local Server opens a door")
    if door == null:
        return
    assert_true(door.is_inside_tree(), "and the door is in the tree, its `_ready` run")
    var after := _overlay_in_the_tree()
    assert_almost_eq(_speed(before), 16.0, 0.001, "An overlay there before the door opened walks at the default speed")
    assert_almost_eq(_speed(after), 16.0, 0.001, "and so does one added after it")
    assert_true(before.ants_march() and after.ants_march(), "both march")

    SaCapture.close_the_local_server(_parent)
    assert_true(before.ants_march() and after.ants_march(), "Closing the door leaves them marching")


## The shot of a door in a painter's Sara holds the ants for the frame it draws
## and gives them back once the picture is read.
func test_a_shot_holds_the_ants_only_while_it_draws() -> void:
    var overlay := _overlay_in_the_tree()
    var stopped := SaCapture.hold_for_a_shot(Engine.get_main_loop() as SceneTree)
    assert_true(stopped.has(overlay), "The shot stops the overlay's ants")
    assert_almost_eq(_speed(overlay), 0.0, 0.001, "which stand still while the frame is drawn")
    SaCapture.let_the_ants_march(stopped)
    assert_almost_eq(_speed(overlay), 16.0, 0.001, "and walk again once the shot is read")


func test_a_capture_run_from_the_command_line_holds_the_ants_as_before() -> void:
    var before := _overlay_in_the_tree()
    # The constructor's defaults past the door are the ones `from_command_line`
    # passes for `--capture` and for a door asked for there.
    var capture := SaCapture.new(scratch_out_dir)
    capture.set_process(false)
    _parent.add_child(capture)
    var after := _overlay_in_the_tree()
    assert_almost_eq(_speed(before), 0.0, 0.001, "A capture run holds an overlay there before it")
    assert_almost_eq(_speed(after), 0.0, 0.001, "and one added after it")

    var stopped := SaCapture.hold_for_a_shot(Engine.get_main_loop() as SceneTree)
    assert_false(stopped.has(before), "A shot leaves the run's own hold alone")
    SaCapture.let_the_ants_march(stopped)
    assert_almost_eq(_speed(before), 0.0, 0.001, "so the ants stay still after the shot")

    _parent.remove_child(capture)
    capture.free()
    assert_almost_eq(_speed(before), 16.0, 0.001, "The run gone, it gives back what it held")
    assert_almost_eq(_speed(after), 16.0, 0.001, "on every overlay")


## An overlay built by its own factory, so its material is the app's, moved
## under the suite's host as a document opened later would join the tree.
func _overlay_in_the_tree() -> SaSelectionOverlay:
    var host := SaCanvas.new()
    _hosts.append(host)
    var overlay := SaSelectionOverlay.attach_to(host)
    host.remove_child(overlay)
    _parent.add_child(overlay)
    return overlay


## The speed the state dump's `ant_speed` reads, the uniform or the shader's
## own sixteen pixels a second when nothing wrote it.
func _speed(overlay: SaSelectionOverlay) -> float:
    var value: Variant = (overlay.material as ShaderMaterial).get_shader_parameter("ant_speed")
    return float(value) if value != null else 16.0


func _capture() -> SaCapture:
    for child: Node in _parent.get_children():
        if child is SaCapture:
            return child as SaCapture
    return null
