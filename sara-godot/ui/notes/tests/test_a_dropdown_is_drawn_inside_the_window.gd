## An open list has Sara's pointer over its rows, and a note taken over it
## carries it in its picture.
##
## A pointer that is not drawn over an open list leaves no way to take notes
## inside it. The list stays a window, so the list takes a `CursorOverlay` of its own while it is open, the cursor policy reads
## it as a window where the pointer is certainly drawn, and the note's picture
## has the list drawn in when it is a window of its own.
##
## Embedded, the way `test_choice_popup.gd` opens a list: a window of its own
## maps a real OS window and blocks the run, so the let-out half is the scenario
## of the same name, and the arithmetic it shares with this half is `paste`,
## which is asserted here on two images.
extends "res://tests/test_framework.gd"

const ANCHOR_AT := Vector2(300.0, 200.0)
## A point inside the first row, in the list's own space.
const ON_A_ROW := Vector2(30.0, 14.0)

var _host: Node = null
var _anchor: Control = null
var _popup: SaChoicePopup = null
var _was_embedding: bool = true
var _previous_mode: String = "auto"


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _previous_mode = SaSettings.software_cursor
    SaSettings.software_cursor = "always"
    SaCursorPolicy.forget_pointer_device()
    _host = Node.new()
    _host.name = "R2ListCursorHost"
    EventBus.add_child(_host)
    _anchor = Control.new()
    _anchor.position = ANCHOR_AT
    _anchor.size = Vector2(120.0, 24.0)
    _host.add_child(_anchor)
    _popup = SaChoicePopup.new()
    _popup.add_row(&"one", "One")
    _popup.add_row(&"two", "Two")
    _host.add_child(_popup)


func after_each() -> void:
    SaCursorPolicy.forget_pointer_device()
    SaSettings.software_cursor = _previous_mode
    if _popup != null and _popup.visible:
        _popup.hide()
    if _host != null:
        _host.free()
        _host = null
    _popup = null
    _anchor = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding


## A pen motion, known for a pen by its tilt, fed the way `CursorOverlay._input`
## feeds it, in the window it arrived in.
func _pen_at(window: Window, at: Vector2) -> void:
    var motion := InputEventMouseMotion.new()
    motion.tilt = Vector2(0.2, -0.1)
    motion.position = at
    SaCursorPolicy.note_pointer_device(motion, window)


func _overlay() -> CursorOverlay:
    return _popup.get_node_or_null("CursorOverlay") as CursorOverlay


func test_an_open_list_has_an_overlay_of_its_own_and_a_closed_one_none() -> void:
    assert_null(_overlay(), "A list that has never opened carries no overlay")
    _popup.open_under(_anchor)
    assert_true(_popup.visible, "The list opened")
    assert_not_null(_overlay(), "An open list has a CursorOverlay of its own")
    _popup.hide()
    assert_null(_overlay(), "and gives it up as it closes")
    _popup.popup(Rect2i(Vector2i(40, 40), Vector2i(160, 80)))
    assert_not_null(_overlay(), "A list opened through `popup` rather than `open_under` has one too")


func test_the_pen_over_a_row_has_saras_pointer() -> void:
    _popup.open_under(_anchor)
    _pen_at(_popup, ON_A_ROW)
    var pointer := SaCursorPolicy.pointer_in_window(_popup)
    assert_eq(pointer, ON_A_ROW, "The list reads the pen where it is over its own row")
    var ring := SaCursorPolicy.cursor_ring_radius_at(_popup, pointer)
    assert_eq(ring, -1.0, "No canvas is in a list's window, so no ring is claimed there")
    var allowed := SaCursorPolicy.wants_software_pointer(_popup, pointer)
    assert_true(allowed, "The policy reads the list as a window where the pointer is certainly drawn")
    assert_eq(CursorOverlay.resolve_cursor(ring, true, allowed), &"pointer", "so the list's overlay draws Sara's arrow")


## The root asked about the same pixel. An embedded list with an overlay stands
## over it and draws the arrow itself, and one without an overlay leaves the
## system pointer, the invariant the policy keeps: nothing hides the OS cursor
## over a window with nothing drawn in it.
func test_the_main_window_trusts_the_list_only_while_it_has_an_overlay() -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    _popup.open_under(_anchor)
    var over_a_row := Vector2(_popup.position) + ON_A_ROW
    _pen_at(root, over_a_row)
    assert_true(SaCursorPolicy.pointer_is_over_embedded_window(root, over_a_row), "The row is over the list and not the root")
    assert_true(
        SaCursorPolicy.wants_software_pointer(root, over_a_row), "With the list's overlay in place the pen's pointer is drawn"
    )
    var overlay := _overlay()
    _popup.remove_child(overlay)
    overlay.free()
    assert_false(
        SaCursorPolicy.wants_software_pointer(root, over_a_row), "and a list with no overlay would have the system pointer kept"
    )


func test_a_mouse_over_a_row_keeps_the_system_pointer() -> void:
    _popup.open_under(_anchor)
    var ring := SaCursorPolicy.cursor_ring_radius_at(_popup, ON_A_ROW)
    assert_false(SaCursorPolicy.pointer_is_tablet, "No pen was seen")
    assert_false(SaCursorPolicy.wants_software_pointer(_popup, ON_A_ROW), "A mouse is left to the driver over a list")
    assert_eq(CursorOverlay.resolve_cursor(ring, false, false), &"system", "so it keeps the system pointer, never hidden")


func test_the_overlays_report_names_the_lists_arrow() -> void:
    _popup.open_under(_anchor)
    _pen_at(_popup, ON_A_ROW)
    var found := false
    for entry: Dictionary in CursorOverlay.state_of((Engine.get_main_loop() as SceneTree).root):
        if Vector2(entry["centre"]["x"], entry["centre"]["y"]) == ON_A_ROW and entry["drawn"] == "pointer":
            found = true
    assert_true(found, "The dump a scenario reads has the list's overlay drawing the arrow at the row")


## A row of an open list is said to be in the picture, because the note draws a
## list let out of the window into it.
func test_a_note_on_a_row_is_in_the_picture() -> void:
    _popup.open_under(_anchor)
    var row := _popup.row_of(&"one")
    var info := SaNoteDescribe.describe(row, (Engine.get_main_loop() as SceneTree).root, "")
    assert_true(bool(info["in_picture"]), "A row of a list is in the note's picture")


func test_paste_draws_a_picture_at_its_place_and_scale() -> void:
    var shot := Image.create(16, 16, false, Image.FORMAT_RGBA8)
    shot.fill(Color.RED)
    var picture := Image.create(2, 2, false, Image.FORMAT_RGBA8)
    picture.fill(Color.BLUE)
    SaNoteImage.paste(shot, picture, Vector2(3.0, 4.0))
    assert_eq(shot.get_pixel(3, 4), Color.BLUE, "The picture's corner lands where it was put")
    assert_eq(shot.get_pixel(4, 5), Color.BLUE, "and it covers its own size")
    assert_eq(shot.get_pixel(5, 6), Color.RED, "and no more")
    SaNoteImage.paste(shot, picture, Vector2(8.0, 8.0), Vector2(2.0, 2.0))
    assert_eq(shot.get_pixel(11, 11), Color.BLUE, "A ratio of two draws it twice as large")
    assert_eq(shot.get_pixel(12, 12), Color.RED, "and still no larger")
    SaNoteImage.paste(shot, picture, Vector2(15.0, 15.0))
    assert_eq(shot.get_pixel(15, 15), Color.BLUE, "A picture past the edge is cut there rather than refused")


func test_an_embedded_list_leaves_the_readback_as_it_was() -> void:
    _popup.open_under(_anchor)
    var root := (Engine.get_main_loop() as SceneTree).root
    var shot := Image.create(8, 8, false, Image.FORMAT_RGBA8)
    shot.fill(Color.RED)
    var before := shot.get_data()
    assert_eq(SaNoteImage.with_windows(shot, root).get_data(), before, "An embedded list is in the root's texture already")
    assert_null(SaNoteImage.with_windows(null, root), "and a failed readback stays null")
