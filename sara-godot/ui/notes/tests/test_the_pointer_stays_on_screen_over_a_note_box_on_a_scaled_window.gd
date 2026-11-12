## The pointer stays on screen over a note box on a scaled window.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The pointer must not vanish with the Brush Editor maximised, at a content
## scale of 1.25, a note box open over it and the pointer inside. A box with no
## cursor overlay would leave nothing to draw the pen's arrow in it and nothing
## to hear a mouse move over it, and a cover test that missed the box through the
## editor's scale would hide the system cursor with nothing drawn in its place.
##
## Each case is the real editor, maximised the way the chord does it, with the
## note mode's overlay in it opening the box over a control, all embedded in the
## root. The guard at the end of each case is the rule the cursor overlay's own
## header states, walked over every window open: the system cursor is hidden only
## while some overlay draws at the pointer. The running app is
## `scenarios/the-pointer-stays-on-screen-over-a-note-box-on-a-scaled-window.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The editor builds the same controls the Tool Options docker does.
const REQUIRES_GPU := true

const SCRATCH := "test_the_pointer_over_a_note_box"

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _editor: SaBrushEditorWindow = null
var _previous_mode: String = "auto"
var _kept_embedding: bool = true
var _kept_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _previous_mode = SaSettings.software_cursor
    SaSettings.software_cursor = "always"
    SaCursorPolicy.forget_pointer_device()
    _kept_mouse_mode = Input.get_mouse_mode()
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    # A window of its own would map a real OS window and block the run.
    tree.root.gui_embed_subwindows = true


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    SaPointerDevice.suite_pointer = null
    SaSettings.software_cursor = _previous_mode
    if _editor != null and is_instance_valid(_editor):
        _editor.free()
    _editor = null
    Input.set_mouse_mode(_kept_mouse_mode)
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding
    Fixtures.teardown(_surface, _machine)
    var dir := SaDataRoot.path(SCRATCH)
    if DirAccess.dir_exists_absolute(dir):
        for file_name: String in DirAccess.get_files_at(dir):
            DirAccess.remove_absolute(dir.path_join(file_name))
        DirAccess.remove_absolute(dir)


## The Brush Editor shown in the root and maximised, which is the way it comes to
## stand at 1.25.
func _maximised_editor() -> SaBrushEditorWindow:
    var store := SaPresetStore.new()
    store.dir = SaDataRoot.path(SCRATCH)
    _editor = SaBrushEditorWindow.new()
    var specs: Array[SaOptionSpec] = []
    specs.assign(_machine.get_descriptor(&"brush").options)
    _editor.bind_tool(_machine.get_tool("brush"), specs, store, "")
    EventBus.add_child(_editor)
    _editor.show()
    SaDockerMaximise.toggle(_editor)
    return _editor


## The note box opened over a control of *editor*, the way the note mode opens
## it on a press.
func _note_box(editor: Window) -> Window:
    var notes := SaNoteOverlay.attach_to(editor)
    notes.open_box(Rect2(Vector2(200.0, 200.0), Vector2(120.0, 40.0)), "Note on CurveGraph")
    return notes.box


func _pen_at(window: Window, at: Vector2) -> void:
    var motion := InputEventMouseMotion.new()
    motion.tilt = Vector2(0.2, -0.1)
    motion.position = at
    SaCursorPolicy.note_pointer_device(motion, window)


## Plain motions enough to call the pointer a mouse again, with the suite's
## system pointer put at the same place on the desktop.
func _mouse_at(window: Window, at: Vector2) -> void:
    var to_desktop: Transform2D = SaPointerDevice.desktop_transform(window)
    SaPointerDevice.suite_pointer = to_desktop * at
    for i in SaCursorPolicy.MOUSE_MOTION_STREAK + 1:
        var motion := InputEventMouseMotion.new()
        motion.position = at
        SaCursorPolicy.note_pointer_device(motion, window)


## The middle of *box*, in its own space.
func _inside(box: Window) -> Vector2:
    return box.get_visible_rect().size * 0.5


func test_the_box_stands_over_the_editor_at_its_scale() -> void:
    var editor := _maximised_editor()
    assert_true(is_equal_approx(editor.content_scale_factor, SaDockerMaximise.MAXIMISED_SCALE), "The maximised editor is at 1.25")
    var box := _note_box(editor)
    assert_true(box != null and box.visible, "The note box is open")
    assert_true(box.is_embedded(), "embedded in the root beside the editor")
    assert_true(SaCursorPolicy.has_overlay(box), "and carries a cursor overlay of its own, as a dialog does")


func test_a_pen_in_the_box_has_its_arrow_drawn_in_the_box() -> void:
    var box := _note_box(_maximised_editor())
    _pen_at(box, _inside(box))
    var at := SaCursorPolicy.pointer_in_window(box)
    assert_true(at.is_equal_approx(_inside(box)), "The box reads the pen where it is, %s" % at)
    assert_true(SaCursorPolicy.arrow_drawn_in(box, at), "The box's overlay draws the pen's arrow")
    assert_eq(SaCursorPolicy.drawn_at(box, at), &"pointer", "and the box's answer is the drawn pointer")
    SaCursorPolicy.sync_os_cursor_visibility()
    assert_eq(Input.get_mouse_mode(), Input.MOUSE_MODE_HIDDEN, "The system cursor is hidden for the arrow drawn in its place")
    _assert_a_cursor_is_shown("the pen in the box")


func test_a_mouse_in_the_box_has_the_system_cursor() -> void:
    var box := _note_box(_maximised_editor())
    _pen_at(box, _inside(box))
    _mouse_at(box, _inside(box))
    assert_false(SaCursorPolicy.pointer_is_tablet, "The box heard the mouse move, so the pen's word no longer stands")
    var at := SaCursorPolicy.pointer_in_window(box)
    assert_true(at.is_equal_approx(_inside(box)), "The box reads the mouse where it is, %s" % at)
    assert_eq(SaCursorPolicy.drawn_at(box, at), &"system", "The box shows the system cursor")
    SaCursorPolicy.sync_os_cursor_visibility()
    assert_eq(Input.get_mouse_mode(), Input.MOUSE_MODE_VISIBLE, "which is visible")
    _assert_a_cursor_is_shown("the mouse in the box")


## The editor asked about the pen in the box reads the box over it, through its
## own scale, and leaves the arrow to the box rather than claiming the point.
func test_the_editor_reads_the_box_over_the_pen_through_its_scale() -> void:
    var editor := _maximised_editor()
    var box := _note_box(editor)
    _pen_at(box, _inside(box))
    var in_editor := SaCursorPolicy.pointer_in_window(editor)
    var in_root := SaCursorPolicy.root_point_of(editor, in_editor)
    var expected := Vector2(box.position) + _inside(box)
    assert_true(
        in_root.is_equal_approx(expected), "The editor's %s is the box's %s in the root, read %s" % [in_editor, expected, in_root]
    )
    assert_true(SaCursorPolicy.pointer_is_over_embedded_window(editor, in_editor), "The editor finds the box over its own point")
    assert_false(SaCursorPolicy.arrow_drawn_in(editor, in_editor), "and leaves the arrow to the box, drawing none beneath it")
    _assert_a_cursor_is_shown("the editor asked about the pen in the box")


## The guard on its own: the pen and then the mouse put over the editor beside
## the box, inside the box, and on the box's corner, and at each the walk over
## every window open finds the cursor shown or something drawing at the pointer.
func test_no_place_hides_the_cursor_with_nothing_drawn_in_its_place() -> void:
    var editor := _maximised_editor()
    var box := _note_box(editor)
    var places: Array = [
        [editor, Vector2(900.0, 120.0), "the editor beside the box"],
        [box, _inside(box), "the middle of the box"],
        [box, Vector2(2.0, 2.0), "the corner of the box"],
    ]
    for place: Array in places:
        _pen_at(place[0], place[1])
        _assert_a_cursor_is_shown("the pen over %s" % place[2])
        _mouse_at(place[0], place[1])
        _assert_a_cursor_is_shown("the mouse over %s" % place[2])


## The overlay header's rule, walked over every window open: when the system
## cursor is hidden, some overlay draws at the pointer, and no window without an
## overlay stands over the pointer to hide what is drawn.
func _assert_a_cursor_is_shown(what: String) -> void:
    SaCursorPolicy.sync_os_cursor_visibility()
    if Input.get_mouse_mode() != Input.MOUSE_MODE_HIDDEN:
        return
    var root := (Engine.get_main_loop() as SceneTree).root
    var drawn: Array[String] = []
    var root_point := SaCursorPolicy.pointer_in_window(root)
    for window: Window in [root] + SaCursorPolicy.embedded_subwindows(root, true):
        var at := SaCursorPolicy.pointer_in_window(window)
        if window != root and not Rect2(Vector2.ZERO, window.get_visible_rect().size).has_point(at):
            continue
        # The root is beneath every other window, so only what stands over it
        # can hide what it draws.
        if window == root:
            if SaCursorPolicy.arrow_drawn_in(root, at):
                drawn.append(String(root.name))
            continue
        assert_true(
            SaCursorPolicy.has_overlay(window),
            "With %s the cursor is hidden while %s, which draws nothing, stands over %s" % [what, window.name, root_point]
        )
        if SaCursorPolicy.has_overlay(window) and SaCursorPolicy.arrow_drawn_in(window, at):
            drawn.append(String(window.name))
    assert_false(drawn.is_empty(), "With %s the cursor is hidden and some overlay draws at the pointer, %s" % [what, drawn])
