## Sara's own pointer row says who draws the pointer for the pick on screen,
## not for the one the run began with.
##
## A run that began at Never and
## picked Both read "The system is drawing it here.", and one that began at
## Both and picked Never read "Sara is drawing it here." after Preferences was
## closed and opened again, while the Cursor lead row below followed the pick.
## The sentence was written once, when the page was declared, and the rebuild
## meant to say it again never ran.
##
## What is held here is the page built once, each choice picked in turn through
## the row's own control the way a hand presses it, and the sentence read off
## the row and off the line on screen after the frame the page asks in. The
## sentence wanted is written out below rather than asked of the function the
## page calls.
extends "res://tests/test_framework.gd"

const SARA := "Sara is drawing it here."
const SYSTEM := "The system is drawing it here."

var _host: Node = null
var _page: SaTabletPage = null
var _saved_cursor: String = "auto"
var _saved_advanced: bool = false


func before_each() -> void:
    _saved_cursor = SaSettings.software_cursor
    _saved_advanced = SaSettings.advanced_options
    # Both is offered only under Advanced options, and the page reads the switch
    # when it is declared.
    SaSettings.advanced_options = true
    SaSettings.software_cursor = "never"
    _host = Node.new()
    _host.name = "PointerHost"
    EventBus.add_child(_host)
    _page = SaTabletPage.new()
    _host.add_child(_page)


func after_each() -> void:
    SaSettings.software_cursor = _saved_cursor
    SaSettings.advanced_options = _saved_advanced
    if is_instance_valid(_host):
        _host.free()
    _host = null
    _page = null


func _row() -> SaPageRow:
    for row: SaPageRow in _page.page.rows():
        if row.label == "Sara's own pointer":
            return row
    return null


func _button() -> SaChoiceButton:
    return _page.find_child("SoftwarePointerMode", true, false) as SaChoiceButton


func _hint_on_screen() -> String:
    var hint := _row().line.get_node_or_null(^"Labels/Hint") as Label
    return hint.text if hint != null else ""


## Who draws the pointer under *mode*, written out: Never leaves it to the
## system, Always and Both draw Sara's, and Auto draws Sara's under Wayland only.
func _wanted(mode: String) -> String:
    match mode:
        "never":
            return SYSTEM
        "always", "both":
            return SARA
    return SARA if DisplayServer.get_name() == "Wayland" else SYSTEM


func _index_of(mode: String) -> int:
    return _button().choice_values().find(mode)


func _pick(mode: String) -> void:
    assert_true(_button().pick_row(_index_of(mode)), "the row offers %s" % mode)
    _page.refresh_pointer_row()


func test_the_row_starts_on_the_pick_it_was_built_at() -> void:
    assert_not_null(_row(), "the page declares the pointer row")
    assert_true(_row().explanation.ends_with(SYSTEM), "Never, '%s'" % _row().explanation)


## Never, Always, Both and Auto in turn, the order the ask names, and Never
## again, which is the run going the other way.
func test_every_pick_is_said_on_the_row_and_on_screen() -> void:
    for mode: String in ["never", "always", "both", "auto", "never", "both"]:
        _pick(mode)
        assert_eq(SaSettings.software_cursor, mode, "the pick reached the setting")
        assert_true(_row().explanation.ends_with(_wanted(mode)), "%s, the row's field, '%s'" % [mode, _row().explanation])
        assert_true(_hint_on_screen().ends_with(_wanted(mode)), "%s, the line, '%s'" % [mode, _hint_on_screen()])


## The frame asks while the page is on screen, so the sentence follows without
## anything called by hand.
func test_a_frame_on_screen_says_it_again() -> void:
    _button().pick_row(_index_of("always"))
    _page._process(0.0)
    assert_true(_row().explanation.ends_with(SARA), "'%s'" % _row().explanation)


## Preferences closed and opened again hides and shows the page, and a setting
## moved while it was hidden is said when it shows.
func test_the_page_shown_again_reads_the_pick_again() -> void:
    _page.hide()
    SaSettings.software_cursor = "always"
    _page.show()
    assert_true(_row().explanation.ends_with(SARA), "'%s'" % _row().explanation)
    assert_true(_hint_on_screen().ends_with(SARA), "and on screen, '%s'" % _hint_on_screen())
