## The engine's scroll bars get a family of their own.
##
## The scroll bar Preferences draws most was reached by no palette,
## and on Paper White the resting grabber was white at 40 percent over a
## ground of 0.95. What is held here is that the shared theme answers for
## `HScrollBar` and `VScrollBar` from the palette's new Scroll bar group, and
## that the focus rim is a border with no ground, the way every other family's
## is. The margins held are the ones that make the bar `SCROLLBAR_THICKNESS`
## wide, twice the engine's eight, which a pen missed.
extends "res://tests/test_framework.gd"

## Class -> the engine's stylebox name -> the state field its ground reads.
const GROUNDS := {
    "HScrollBar":
    {
        "scroll": "scrollbar_track",
        "grabber": "scrollbar_grabber",
        "grabber_highlight": "scrollbar_hover",
        "grabber_pressed": "scrollbar_pressed",
    },
    "VScrollBar":
    {
        "scroll": "scrollbar_track",
        "grabber": "scrollbar_grabber",
        "grabber_highlight": "scrollbar_hover",
        "grabber_pressed": "scrollbar_pressed",
    },
}

const SIDES: Array[Side] = [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]

var _saved_theme: String = "default"
var _saved_shared: Theme = null


func before_each() -> void:
    _saved_theme = SaTheme.palette_id
    _saved_shared = SaUI.shared_theme


func after_each() -> void:
    SaTheme.use_named(_saved_theme)
    SaUI.shared_theme = _saved_shared


func test_the_new_states_derive_from_their_bases_and_the_table_names_them() -> void:
    var bases := {
        "scrollbar_track": "bg_secondary",
        "scrollbar_grabber": "text_muted",
        "scrollbar_hover": "scrollbar_grabber",
        "scrollbar_pressed": "scrollbar_grabber",
    }
    var fresh := SaPalette.new()
    fresh.derive_states()
    for field: String in bases:
        assert_eq(String(SaPalette.STATE_BASES.get(field, "")), String(bases[field]), "%s is a state with the right base" % field)
        if field in SaPalette.HOVER_FROM or field in SaPalette.PRESSED_BEYOND:
            continue
        assert_eq(fresh.get(field), fresh.get(String(bases[field])), "a palette nobody set derives %s" % field)
    assert_eq(
        String((SaPalette.SCROLLBAR_BOXES["track"] as Dictionary)["bg_color"]),
        "scrollbar_track",
        "the table's track row names the field"
    )
    assert_eq(
        String((SaPalette.SCROLLBAR_BOXES["grabber"] as Dictionary)["bg_color"]), "scrollbar_grabber", "and its grabber row"
    )
    assert_eq(String((SaPalette.SCROLLBAR_BOXES["hover"] as Dictionary)["bg_color"]), "scrollbar_hover", "and its hovered row")
    assert_eq(
        String((SaPalette.SCROLLBAR_BOXES["pressed"] as Dictionary)["bg_color"]), "scrollbar_pressed", "and its pressed row"
    )


func test_every_palette_grounds_the_boxes_at_a_pens_thickness() -> void:
    var thick := float(SaThemeDefaults.SCROLLBAR_THICKNESS)
    for id: String in SaTheme.PALETTES:
        SaTheme.use_named(id)
        SaUI.init_global_theme(null)
        var theme := SaUI.shared_theme
        for cls: String in GROUNDS:
            for box_name: String in GROUNDS[cls]:
                var field := String(GROUNDS[cls][box_name])
                var label := "%s: %s.%s" % [id, cls, box_name]
                assert_true(theme.has_stylebox(box_name, cls), "%s is on the shared theme" % label)
                var flat := theme.get_stylebox(box_name, cls) as StyleBoxFlat
                assert_not_null(flat, "%s is a flat box" % label)
                if flat == null:
                    continue
                assert_eq(flat.bg_color, SaTheme.palette.get(field), "%s grounds at %s" % [label, field])
                var across := flat.get_minimum_size().y if cls == "HScrollBar" else flat.get_minimum_size().x
                assert_eq(across, thick, "%s is the bar's thickness across" % label)


func test_the_focus_rim_has_no_ground_and_keeps_the_engines_margin() -> void:
    SaTheme.use_named("default")
    SaUI.init_global_theme(null)
    var engine := ThemeDB.get_default_theme()
    var theme := SaUI.shared_theme
    for cls: String in ["HScrollBar", "VScrollBar"]:
        var flat := theme.get_stylebox("scroll_focus", cls) as StyleBoxFlat
        assert_not_null(flat, "%s's focus rim is on the shared theme" % cls)
        if flat == null:
            continue
        assert_eq(flat.bg_color.a, 0.0, "%s's focus rim has no ground to fill" % cls)
        assert_eq(flat.border_color, SaTheme.palette.border_selected, "%s's focus rim is the palette's selected border" % cls)
        var theirs := engine.get_stylebox("scroll_focus", cls)
        for side: Side in SIDES:
            assert_eq(
                flat.get_margin(side),
                theirs.get_margin(side),
                "%s's focus rim keeps the engine's margin on side %d" % [cls, side]
            )


## A switch rewrites the same boxes in place, which is the whole reason they
## are bound: a theme built under one palette follows the next one.
func test_a_switch_repaints_the_boxes() -> void:
    SaTheme.use_named("default")
    SaUI.init_global_theme(null)
    var theme := SaUI.shared_theme
    var track := theme.get_stylebox("scroll", "HScrollBar") as StyleBoxFlat
    assert_not_null(track, "the theme holds the track")
    SaTheme.use_named("paper")
    if track != null:
        assert_eq(track.bg_color, SaTheme.palette.scrollbar_track, "the same object follows the switch")
