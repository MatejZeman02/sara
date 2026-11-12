## Every row of a list with icons draws its icon at `ICON_SIZE`, whatever
## its label's length, and the labels start at one x.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The toolbox's selection flyout drew Ellipse Select's and Magic Wand's icons
## at about a third of Marquee's and Lasso's, and their labels started further
## left. An expanding icon asks for no width of its own and is drawn in what the
## label leaves, and the list is as wide as its longest label, so the two
## longest rows had almost nothing left.
##
## A `Button` gives no rect for the icon it drew, so the suite reads what the
## draw follows: the icon is not expanded, the texture is at least `ICON_SIZE`
## wide so the cap is what sizes it, and the button's width with the icon
## less its width without it is the icon and the gap on every row. Rows of one
## list are one width and left aligned, so one icon width is one label x. The
## rows sit under a holder in the tree carrying Sara's theme, the way
## `test_a_greyed_row_is_as_tall_as_a_live_one.gd` builds them, because a
## button out of the tree has shaped no text. The picture is
## `scenarios/a-choice-list-draws-every-rows-icon-at-one-size.json`.
extends "res://tests/test_framework.gd"

const SHORT := "Lasso (L)"
const LONG := "Ellipse Select (J) and a label far longer than any in the flyout"

var _kept_theme: Theme = null
var _holder: VBoxContainer = null


func before_each() -> void:
    _kept_theme = SaUI.shared_theme
    SaUI.init_global_theme(null)
    _holder = VBoxContainer.new()
    _holder.theme = SaUI.shared_theme
    EventBus.add_child(_holder)


func after_each() -> void:
    _holder.free()
    _holder = null
    SaUI.shared_theme = _kept_theme


func _row(id: StringName, label: String, icon: String) -> SaChoiceRow:
    var row := SaChoiceRow.new(id, label, false, false, icon, "", false, null, "")
    _holder.add_child(row)
    return row


## What the icon adds to its row's width: the button with it less a twin
## without it.
func _icon_width(label: String, icon: String) -> float:
    var with_icon := _row(StringName("with_" + icon), label, icon).label_button()
    var without := _row(StringName("without_" + icon), label, "").label_button()
    return with_icon.get_minimum_size().x - without.get_minimum_size().x


func test_an_icon_is_capped_rather_than_fitted_into_what_its_label_leaves() -> void:
    for icon: String in ["lasso", "ellipse_select"]:
        var button := _row(StringName(icon), LONG, icon).label_button()
        assert_not_null(button.icon, "the %s row carries its icon" % icon)
        assert_false(button.expand_icon, "the %s icon is not expanded into what the label leaves" % icon)
        assert_true(
            button.icon.get_width() >= SaUI.px(SaChoicePopup.ICON_SIZE),
            "the %s texture is at least ICON_SIZE wide, so the cap sizes it" % icon
        )
        assert_eq(button.get_theme_constant("icon_max_width"), SaUI.px(SaChoicePopup.ICON_SIZE), "and the cap is ICON_SIZE")


func test_a_short_and_a_long_label_give_their_icons_one_width() -> void:
    var short_width := _icon_width(SHORT, "lasso")
    var long_width := _icon_width(LONG, "ellipse_select")
    var gap := float(_row(&"probe", SHORT, "lasso").label_button().get_theme_constant("h_separation"))
    var want := float(SaUI.px(SaChoicePopup.ICON_SIZE)) + gap
    assert_eq(short_width, want, "the short row's icon is ICON_SIZE and the gap")
    assert_eq(long_width, want, "and so is the long row's, so both labels start at one x")
