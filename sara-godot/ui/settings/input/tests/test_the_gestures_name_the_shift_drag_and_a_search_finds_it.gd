## Shift and a left drag sizes the brush, and the Keyboard Shortcuts page says
## so.
##
## The drag works and the page must say so, even
## searched for "brush". `GESTURES` holds the wheel, the middle drag and the two
## Alt drags on a docker, and a search of any kind would hide the whole Gestures
## section, because only a row with an action behind it was searched and a
## section with no row left showing is hidden.
extends "res://tests/test_framework.gd"

## The row the drag reads as, the chord and then the words, as `GESTURES`
## writes it.
const ROW: Array = ["Shift + left drag on the canvas", "Size the brush, a screen pixel of radius for each pixel of drag"]


## The key the page files a fixed row under, which `row_shown` reads.
func _row_key() -> StringName:
    return StringName(SaShortcutsPage.FIXED_KEY + String(ROW[1]).to_snake_case())


func test_the_gestures_table_has_the_shift_drag() -> void:
    assert_true(SaShortcutRows.GESTURES.has(ROW), "The Gestures table names the Shift drag: %s" % str(SaShortcutRows.GESTURES))
    assert_eq(SaShortcutsPage.GESTURES, SaShortcutRows.GESTURES, "and the page reads the same table")


## The row is on the page under Gestures with nothing typed, and its chord
## column reads the drag.
func test_the_page_shows_the_row_under_gestures() -> void:
    var page := SaShortcutsPage.new()
    page.filter("")
    assert_true(page.row_shown(_row_key()), "The row is on the page")
    var section := page._section_boxes.get("Gestures", null) as Control
    assert_not_null(section, "The page has a Gestures section")
    var row := page._rows_by_action.get(_row_key(), null) as Control
    assert_true(row != null and section.is_ancestor_of(row), "and the row sits in it")
    var shown := row.find_child("FixedChord", true, false) as Label
    assert_true(shown != null and shown.text == String(ROW[0]), "Its chord column reads the drag")
    page.free()


## The ask: a search for "brush" showed the two bracket rows and hid the drag.
## Both words the row is about find it, the Gestures section shows with it, and
## a search about something else hides both.
func test_a_search_for_brush_or_size_shows_the_row() -> void:
    var page := SaShortcutsPage.new()
    var section := page._section_boxes.get("Gestures", null) as Control
    assert_not_null(section, "The page has a Gestures section")
    for needle: String in ["brush", "size", "Brush"]:
        page.filter(needle)
        assert_true(page.row_shown(_row_key()), "'%s' shows the Shift drag's row" % needle)
        assert_true(section.visible, "and the Gestures section it sits in")
        assert_true(page.row_shown(&"brush_size_increase"), "beside the larger brush row")
    page.filter("undo")
    assert_false(page.row_shown(_row_key()), "A search for something else hides the row")
    assert_false(section.visible, "and the section with no row left showing")
    page.filter("")
    assert_true(page.row_shown(_row_key()) and section.visible, "and clearing the search brings both back")
    page.free()


## The other fixed rows are searched by their words as well, since the search
## now reads every row the page declares: the middle drag's "Pan" and Tab's
## "Hide or show every docker".
func test_the_other_fixed_rows_are_found_by_their_words() -> void:
    var page := SaShortcutsPage.new()
    page.filter("pan")
    assert_true(page.row_shown(StringName(SaShortcutsPage.FIXED_KEY + "pan")), "'pan' shows the middle drag's row")
    page.filter("every docker")
    assert_true(
        page.row_shown(StringName(SaShortcutsPage.FIXED_KEY + "hide_or_show_every_docker")),
        "and 'every docker' shows Tab's row under Interface"
    )
    page.free()
