## The Colour Picker's seven elements placed in another docker
## edit the same colour.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A placed wheel, box or swatch
## row shows and sets the one brush colour the docker does. So each view here is
## built through the door, `SaSettings.build_element_view`, the way a composed
## docker builds one, with the Colour Picker docker built and closed and a fresh
## profile's five rows hidden at home, and nothing in the suite hands a view a
## colour. What it shows comes from `SaColors`, and what it sets goes there.
##
## A docker is a `Window` and adding one to the tree in a headless test hangs,
## so nothing here enters the tree, as in the suite beside the Layers
## docker's.
extends "res://tests/test_framework.gd"

const CATEGORY: String = SaColorPickerView.CATEGORY

## The seven, by their layout names, in the docker's shipped order.
const ELEMENTS: Array[String] = [
    "HSV Wheel",
    "Selected Colour Preview",
    "Swatches",
    "Recent Colours",
    "Hex Input",
    "RGB Sliders",
    "OK-HSV Sliders",
]

## What a fresh profile hides at home, `SaSettingsLayout.DEFAULT_HIDDEN`'s five.
const FRESH_HIDDEN: Array[String] = ["Swatches", "Recent Colours", "Hex Input", "RGB Sliders", "OK-HSV Sliders"]

## Whole steps of 255, so the hex box's two digits a channel carry it exactly.
const TYPED := Color8(51, 153, 230)
const FROM_OUTSIDE := Color8(204, 51, 26)

var _docker: ColorDocker
## Every view the door built, freed after each test.
var _views: Array[Control] = []
## The store's pair, its recent list and the home switches as they were, put
## back after each test.
var _was_foreground: Color
var _was_background: Color
var _was_recent: Array[Color] = []
var _was_shown: Dictionary[String, bool] = {}


func before_each() -> void:
    _was_foreground = SaColors.foreground
    _was_background = SaColors.background
    _was_recent = SaColors.recent.duplicate()
    for element: String in ELEMENTS:
        _was_shown[element] = SaSettings.get_element_visible(CATEGORY, element)
        SaSettings.set_element_visible(CATEGORY, element, not FRESH_HIDDEN.has(element))
    SaColors.foreground = Color.BLACK
    SaColors.background = Color.WHITE
    _docker = ColorDocker.new()
    _docker.hide()
    _home().apply_layout_settings()


func after_each() -> void:
    # The side every picker edits is shared, so a test that pressed the
    # background leaves the foreground edited again, the way a run starts.
    _press(_view("Selected Colour Preview").foreground_swatch)
    for view: Control in _views:
        if is_instance_valid(view):
            view.free()
    _views.clear()
    _docker.free()
    _docker = null
    for element: String in _was_shown:
        SaSettings.set_element_visible(CATEGORY, element, _was_shown[element])
    SaColors.foreground = _was_foreground
    SaColors.background = _was_background
    SaColors.recent.assign(_was_recent)
    SaColors.save()


## The Colour Picker docker's own picker.
func _home() -> SaColorPickerView:
    return _docker.color_picker as SaColorPickerView


## A fresh view of *element* of the Colour Picker, built through the door.
func _view(element: String) -> SaColorPickerView:
    var built := SaSettings.build_element_view(CATEGORY, element)
    if built != null:
        _views.append(built)
    return built as SaColorPickerView


## A left press on *swatch*, as the painter's click lands on it.
func _press(swatch: Control) -> void:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    swatch.gui_input.emit(press)


## The rows *picker* draws, by their layout names.
func _shown(picker: SaColorPickerView) -> Array[String]:
    var out: Array[String] = []
    var rows := picker.element_rows()
    for element: String in rows:
        if rows[element].visible:
            out.append(element)
    return out


func test_the_seven_are_placeable_under_the_titles_the_page_shows() -> void:
    for element: String in ELEMENTS:
        assert_true(SaSettings.is_placeable(CATEGORY, element), "%s has a view the Colour Picker registered" % element)
    assert_false(SaSettings.is_placeable(CATEGORY, "Drag Handle"), "while the docker's drag bar is not placeable")
    var offered: Array[String] = []
    for home: Dictionary in SaSettings.placeable_elements():
        if home["id"] == CATEGORY:
            assert_eq(home["title"], "Colour Picker", "the seven are listed under the docker's title")
            for element: Dictionary in home["elements"]:
                offered.append("%s as %s" % [element["id"], element["title"]])
    assert_eq(offered.size(), 8, "the seven and the Paint Exposure, nothing else: %s" % ", ".join(offered))
    assert_true(offered.has("Paint Exposure as Paint Exposure"), "the exposure picker under its own name")
    assert_true(offered.has("HSV Wheel as Picker Shape"), "the shape under the title its row reads")
    assert_true(offered.has("OK-HSV Sliders as OKHSV Sliders"), "and the numbers under theirs")
    assert_true(offered.has("Selected Colour Preview as Selected Colour Preview"), "and the pair under its name")


## The first case: a view of each of the seven with the docker
## closed and a fresh profile's five hidden at home, each showing its own
## element and no other.
func test_each_view_shows_its_own_element_and_no_other() -> void:
    assert_false(_docker.visible, "the Colour Picker is closed")
    var at_home: Array[String] = ["HSV Wheel", "Selected Colour Preview"]
    assert_eq(_shown(_home()), at_home, "and at home a fresh profile shows the shape and the pair alone")
    for element: String in ELEMENTS:
        var view := _view(element)
        assert_not_null(view, "the door builds a view of %s" % element)
        if view == null:
            continue
        assert_false(view == _home(), "a picker of its own, not the docker's")
        assert_eq(view.get_child_count(), _home().get_child_count(), "built once, with the docker's rows and no second set")
        assert_eq(_shown(view), [element], "the view of %s shows that row alone" % element)


## The switches are the Colour Picker's, so a row hidden at home is still
## shown by its view, and one shown at home is still not shown by another
## element's view, when the profile changes under them.
func test_a_view_ignores_the_home_switches() -> void:
    var shape := _view("HSV Wheel")
    var swatches := _view("Swatches")
    SaSettings.set_element_visible(CATEGORY, "HSV Wheel", false)
    SaSettings.set_element_visible(CATEGORY, "Swatches", true)
    for picker: SaColorPickerView in [_home(), shape, swatches]:
        picker.apply_layout_settings()
    assert_eq(_shown(_home()), ["Selected Colour Preview", "Swatches"], "home follows its switches")
    assert_eq(_shown(shape), ["HSV Wheel"], "while the shape's view still shows the shape it hides")
    assert_eq(_shown(swatches), ["Swatches"], "and the swatches' view the swatches alone")


## The second case, its first half: a colour typed into the Hex
## Input view is the brush colour, and the home picker shows it.
func test_a_hex_typed_into_its_view_is_the_brush_colour_and_the_home_pickers() -> void:
    var hex := _view("Hex Input")
    hex.hex_input.text_submitted.emit("#" + TYPED.to_html(false))
    assert_true(SaColors.foreground.is_equal_approx(TYPED), "the brush colour is the colour typed")
    assert_true(_home().color.is_equal_approx(TYPED), "and the closed docker's picker shows it")
    assert_eq(_home().hex_input.text, "#" + TYPED.to_html(false), "in its own hex box too")
    assert_true(SaColors.recent.has(TYPED), "and it joined the recent row as a colour chosen")


## Its second half: the brush colour set from outside, the way the eyedropper
## and the `colour` step set it, is what the Selected Colour Preview view shows.
func test_a_brush_colour_set_from_outside_shows_on_the_preview_view() -> void:
    var pair := _view("Selected Colour Preview")
    SaColors.foreground = FROM_OUTSIDE
    assert_true(pair.color.is_equal_approx(FROM_OUTSIDE), "the view holds the colour set from outside")
    assert_true(pair.foreground_swatch.color.is_equal_approx(FROM_OUTSIDE), "and its foreground swatch draws it")
    EventBus.color_picked.emit(TYPED)
    assert_true(pair.foreground_swatch.color.is_equal_approx(TYPED), "as it does a pick announced on the bus")
    SaColors.background = FROM_OUTSIDE
    assert_true(pair.background_swatch.color.is_equal_approx(FROM_OUTSIDE), "and the background swatch the background")


## A view built after the colour moved opens on it, so a docker placed late
## shows the store's colour rather than black.
func test_a_view_built_later_opens_on_the_stores_colour() -> void:
    SaColors.foreground = FROM_OUTSIDE
    var pair := _view("Selected Colour Preview")
    assert_true(pair.foreground_swatch.color.is_equal_approx(FROM_OUTSIDE), "the new view opens on the brush colour")


## A press on the placed pair's background swatch steers the placed shape, the
## home picker and the hex view to the background, and what the hex view sets
## then is the background and not the brush colour.
func test_the_side_a_placed_pair_picks_is_the_side_every_picker_edits() -> void:
    var pair := _view("Selected Colour Preview")
    var shape := _view("HSV Wheel")
    var hex := _view("Hex Input")
    _press(pair.background_swatch)
    for picker: SaColorPickerView in [pair, shape, hex, _home()]:
        assert_true(picker._editing_background, "%s edits the background after the press on the pair" % picker.name)
    assert_true(_view("RGB Sliders")._editing_background, "and so does a view built after it")
    hex.hex_input.text_submitted.emit("#" + TYPED.to_html(false))
    assert_true(SaColors.background.is_equal_approx(TYPED), "the hex view set the background")
    assert_true(SaColors.foreground.is_equal_approx(Color.BLACK), "and left the brush colour alone")
    assert_true(_home().background.is_equal_approx(TYPED), "which the home picker shows")
    _press(shape.foreground_swatch)
    assert_false(pair._editing_background, "a press on the foreground anywhere steers them all back")


## The numbers moved on a slider view are the brush colour too.
func test_a_slider_view_sets_the_brush_colour() -> void:
    var sliders := _view("RGB Sliders")
    sliders.rgb_sliders.color_changed.emit(FROM_OUTSIDE)
    assert_true(SaColors.foreground.is_equal_approx(FROM_OUTSIDE), "the brush colour follows the RGB view")
    assert_true(_home().color.is_equal_approx(FROM_OUTSIDE), "and the home picker shows it")


## A freed view leaves nothing listening on the bus or the store, so a docker
## a painter takes an element out of leaks no connection.
func test_a_freed_view_leaves_no_connection() -> void:
    var bus_before := EventBus.background_color_changed.get_connections().size()
    var store_before := SaColors.swatches_changed.get_connections().size()
    var view := SaSettings.build_element_view(CATEGORY, "Swatches")
    assert_eq(EventBus.background_color_changed.get_connections().size(), bus_before + 1, "a view listens on the bus")
    view.free()
    assert_eq(EventBus.background_color_changed.get_connections().size(), bus_before, "and stops when freed")
    assert_eq(SaColors.swatches_changed.get_connections().size(), store_before, "on the store as well")
