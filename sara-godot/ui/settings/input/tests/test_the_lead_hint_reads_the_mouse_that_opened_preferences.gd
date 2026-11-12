## Under Auto, the mouse that opens Preferences after a pen reads what a pen
## would get, and a pen over the same page reads that it leads.
##
## A report on Windows: a synthetic pen hovered across the canvas
## under Windows Ink, Sara's own pointer at Both and the lead Auto, and the mouse
## opened Preferences. The Cursor lead row ended "Active on this system." and still did
## after the mouse moved over the page. It looked like the engine handing
## an embedded window's motions to that window alone, so that the one feed of
## the device flag, `CursorOverlay._input` in the main window, never saw them.
##
## Half of that holds and is the first case here: a motion over an embedded
## Preferences does not reach the main window's `_input`. The other half does
## not. Every `SaDialogWindow` attaches a `CursorOverlay` of its own in `_ready`,
## and that overlay feeds `note_pointer_device` with the dialog's motions, so a
## mouse over the page counts toward the streak like a mouse over the canvas.
## The second case holds that, at exactly the streak, so a second feed added
## beside the overlay would fail it by dropping the flag at half the motions.
## What the report most likely saw is a mouse that jumped fewer times than the
## streak, which the scenario of the same name shows on the running app.
extends "res://tests/test_framework.gd"

const PEN_WOULD_LEAD := "Not active for the mouse on this system. A pen would use it."
const LEADING := "Active on this system."


## Counts the motions a window's `_input` is handed, the way the overlay's own
## `_input` is.
class MotionCount:
    extends Node

    var seen: int = 0

    func _input(event: InputEvent) -> void:
        if event is InputEventMouseMotion:
            seen += 1


var _tree: SceneTree = null
var _was_embedding: bool = true
var _host: Node = null
var _main_count: MotionCount = null
var _dialog: SaSettingsWindow = null
var _page: SaTabletPage = null
var _saved_lead: String = "auto"
var _saved_cursor: String = "auto"


## The main window's feed, a Preferences embedded over it on the page of the pen,
## and the pointer at Both and the lead at Auto, which is where a pen leads and
## a mouse does not.
func before_each() -> void:
    _saved_lead = SaSettings.cursor_lead
    _saved_cursor = SaSettings.software_cursor
    SaSettings.software_cursor = "both"
    SaSettings.cursor_lead = "auto"
    SaCursorPolicy.forget_pointer_device()
    _tree = Engine.get_main_loop() as SceneTree
    _was_embedding = _tree.root.gui_embed_subwindows
    _tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "LeadHintHost"
    EventBus.add_child(_host)
    _main_count = MotionCount.new()
    _host.add_child(_main_count)
    # The main window's feed, under the host rather than on the root, because the
    # runner calls this from its own `_ready` and the root is still busy then.
    _host.add_child(CursorOverlay.new())


func after_each() -> void:
    if is_instance_valid(_dialog):
        _dialog.hide()
    if is_instance_valid(_host):
        _host.free()
    _tree.root.gui_embed_subwindows = _was_embedding
    SaSettings.cursor_lead = _saved_lead
    SaSettings.software_cursor = _saved_cursor
    SaCursorPolicy.forget_pointer_device()
    _host = null
    _main_count = null
    _dialog = null
    _page = null


## Preferences the way Edit, Preferences opens it, on the page of the pen.
func _open_preferences() -> void:
    _dialog = SaSettingsWindow.new()
    _host.add_child(_dialog)
    _dialog.toggle("Pen and tablet")
    _page = _dialog.find_children("*", "SaTabletPage", true, false).front() as SaTabletPage


## A pen hovering on the canvas, with the tilt no mouse carries, pushed where the
## display server pushes it.
func _pen_at(at: Vector2) -> void:
    var pen := InputEventMouseMotion.new()
    pen.position = at
    pen.global_position = at
    pen.tilt = Vector2(0.3, 0.1)
    _tree.root.push_input(pen)


## *count* plain motions over the middle of the open dialog.
func _mouse_over_the_dialog(count: int) -> void:
    var middle := Vector2(_dialog.position) + Vector2(_dialog.size) * 0.5
    for i in count:
        var plain := InputEventMouseMotion.new()
        plain.position = middle + Vector2(i, 0)
        plain.global_position = plain.position
        plain.relative = Vector2(1, 0)
        _tree.root.push_input(plain)


## The sentence the Cursor lead row ends on, said again the way the page says it
## every frame it shows.
func _verdict() -> String:
    _page.refresh_lead_row()
    var row := _page.page.row(&"cursor_lead")
    for ending: String in [PEN_WOULD_LEAD, "Not active on this system.", LEADING]:
        if row.explanation.ends_with(ending):
            return ending
    return "no verdict"


## The board's reading of the cause, held by a test rather than by reading: a
## motion over an embedded Preferences goes to Preferences and not to the main
## window's `_input`. Then the half it missed: the dialog has a feed of its own.
func test_a_motion_over_an_embedded_preferences_misses_the_main_window() -> void:
    _pen_at(Vector2(600, 500))
    assert_eq(_main_count.seen, 1, "a pen on the canvas reaches the main window's input")
    assert_true(SaCursorPolicy.pointer_is_tablet, "and says a pen is the pointer")
    _open_preferences()
    assert_not_null(_page, "Preferences opens on the page of the pen")
    if _page == null:
        return
    assert_true(_dialog.is_embedded(), "and is embedded in the main window")
    _mouse_over_the_dialog(3)
    assert_eq(_main_count.seen, 1, "three motions over Preferences never reach the main window's input")
    assert_not_null(_dialog.get_node_or_null("CursorOverlay"), "the dialog carries an overlay of its own, which is its feed")


## A pen, then a mouse over Preferences, holds
## the row at what a pen would get, and a pen over the same page holds it at
## leading. The flag drops on the eleventh motion over the page and not before,
## which is the streak counted once per motion.
func test_a_mouse_over_preferences_after_a_pen_reads_what_a_pen_would_get() -> void:
    _pen_at(Vector2(600, 500))
    _open_preferences()
    if _page == null:
        assert_not_null(_page, "Preferences opens on the page of the pen")
        return
    assert_eq(_verdict(), LEADING, "straight after the pen the row says the pen leads")
    _mouse_over_the_dialog(SaCursorPolicy.MOUSE_MOTION_STREAK)
    assert_true(SaCursorPolicy.pointer_is_tablet, "ten plain motions are not yet a mouse, each counted once")
    _mouse_over_the_dialog(1)
    assert_false(SaCursorPolicy.pointer_is_tablet, "the eleventh motion over the page says a mouse")
    assert_eq(_verdict(), PEN_WOULD_LEAD, "and the row tells that mouse what a pen gets")
    _mouse_over_the_dialog(20)
    assert_eq(_verdict(), PEN_WOULD_LEAD, "and goes on saying it while the mouse moves on the page")
    assert_eq(_main_count.seen, 1, "with none of those motions reaching the main window")

    _pen_at(Vector2(Vector2(_dialog.position) + Vector2(40, 200)))
    assert_true(SaCursorPolicy.pointer_is_tablet, "a pen over the page counts as a pen, as it does over the canvas")
    assert_eq(_verdict(), LEADING, "and the row says the ring leads")
