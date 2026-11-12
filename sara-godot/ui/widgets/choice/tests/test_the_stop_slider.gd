## A choice of a few named ways is one thumb sliding between a
## stop per option, with each option's label over its stop.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## It should feel like a single button where one slides the thumb to any of the
## options, with any number of options declared and the option label above every
## option. This holds the control itself: a label over every stop uncut at two, three and
## five options, a click between two stops taking the nearer, a drag that
## settles and says so once, and Left and Right stepping it. The Filter
## dialog's use of it is `ui/filters/tests/test_bake_attach_and_layer_are_one_sliding_choice.gd`.
extends "res://tests/test_framework.gd"

## Labels of unequal widths, so the widest decides every cell.
const WORDS: Array[String] = ["Bake", "Attach", "Layer", "An adjustment", "X"]


## A module's filter declaring the choice through the door a built-in uses
## (hard rule 6, built-ins register as modules do), its value kept in the filter's store.
class Edged:
    extends SaFilter

    func id() -> StringName:
        return &"n103_edged"

    func build(ui: SaDialog) -> void:
        ui.stops("Edge", [{"id": "soft", "label": "Soft", "tooltip": "Feathered"}, {"id": "hard", "label": "Hard"}], "soft")

    func run(_ctx: SaFilterContext) -> void:
        pass


func test_a_label_sits_over_each_stop_uncut_at_two_three_and_five_options() -> void:
    for count: int in [2, 3, 5]:
        var slider := _slider(count)
        assert_true(slider.size.x > 0.0 and slider.size.y > 0.0, "%d options: the slider asks for room" % count)
        var cell := slider.size.x / float(count)
        for index in count:
            var place := slider.label_rect(index)
            var full := slider.get_theme_font("font", "Label").get_string_size(
                WORDS[index], HORIZONTAL_ALIGNMENT_LEFT, -1, slider.get_theme_font_size("font_size", "Label")
            )
            assert_almost_eq(place.size.x, full.x, 0.01, "%d options: '%s' is drawn at its whole width" % [count, WORDS[index]])
            assert_almost_eq(place.get_center().x, slider.stop_x(index), 0.01, "and centred over its own stop")
            assert_true(
                place.position.x >= cell * index - 0.01 and place.end.x <= cell * (index + 1) + 0.01,
                "%d options: '%s' stays inside its own cell, %s in %.1f" % [count, WORDS[index], place, cell]
            )
            assert_true(place.end.y <= slider.size.y, "and above the foot of the control")
        slider.free()


func test_the_widest_label_sets_every_cell() -> void:
    var slider := _slider(4)
    var font := slider.get_theme_font("font", "Label")
    var font_size := slider.get_theme_font_size("font_size", "Label")
    var widest := font.get_string_size(WORDS[3], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    assert_true(
        slider.size.x >= (widest + SaTheme.GAP) * 4.0 - 0.01,
        "The minimum width is the widest label times the count with the theme's gap beside each"
    )
    slider.add_theme_font_size_override("font_size", 40)
    assert_true(slider.get_minimum_size().x > slider.size.x, "and a larger font asks for more")
    slider.free()


func test_a_click_between_two_stops_picks_the_nearer() -> void:
    var slider := _slider(3)
    var heard: Array = []
    slider.picked.connect(func(id: Variant) -> void: heard.append(id))
    var between := (slider.stop_x(0) + slider.stop_x(1)) / 2.0

    _click(slider, between + 3.0)
    assert_eq(slider.value, 1, "A click just right of the midpoint takes the right-hand stop")
    assert_eq(heard, [1], "and says so once")

    _click(slider, between - 3.0)
    assert_eq(slider.value, 0, "and just left of it the left-hand one")
    assert_eq(heard, [1, 0], "once more")

    _click(slider, between - 3.0)
    assert_eq(heard, [1, 0], "A click on the stop already picked says nothing")
    slider.free()


func test_a_drag_settles_on_a_stop_and_emits_once() -> void:
    var slider := _slider(5)
    var heard: Array = []
    slider.picked.connect(func(id: Variant) -> void: heard.append(id))

    _press(slider, slider.stop_x(0), true)
    for x: float in [slider.stop_x(1), slider.stop_x(2) + 5.0, slider.stop_x(3) - 4.0]:
        _move(slider, x)
        assert_eq(slider.value, 0, "The pick stays where it was while the thumb is dragged")
        assert_true(slider.describe()["dragging"], "and the control says it is being dragged")
    _press(slider, slider.stop_x(3) - 4.0, false)

    assert_eq(slider.value, 3, "Let go, the thumb settles on the nearest stop")
    assert_eq(heard, [3], "and the pick is said once, however far the drag went")
    assert_false(slider.describe()["dragging"], "and the drag is over")
    slider.free()


func test_left_and_right_step_it() -> void:
    var slider := _slider(3)
    var heard: Array = []
    slider.picked.connect(func(id: Variant) -> void: heard.append(id))

    _key(slider, KEY_RIGHT)
    assert_eq(slider.value, 1, "Right steps to the next stop")
    _key(slider, KEY_RIGHT)
    _key(slider, KEY_RIGHT)
    assert_eq(slider.value, 2, "and stops at the last")
    _key(slider, KEY_LEFT)
    assert_eq(slider.value, 1, "Left steps back")
    assert_eq(heard, [1, 2, 1], "each step said once, and the one past the end not at all")
    slider.free()


func test_a_dimmed_stop_is_passed_over_and_its_tooltip_says_why() -> void:
    var slider := _slider(3)
    slider.dim(1, "Not for this filter.")

    _click(slider, slider.stop_x(1))
    assert_eq(slider.value, 0, "A click on a dimmed stop settles on the nearest one a hand may take")
    assert_false(slider.pick(1), "a pick of it is refused")
    _key(slider, KEY_RIGHT)
    assert_eq(slider.value, 2, "and Right steps over it")
    assert_eq(slider.get_tooltip(Vector2(slider.stop_x(1), 1.0)), "Not for this filter.", "Its tooltip is the reason")
    assert_eq(slider.get_tooltip(Vector2(slider.stop_x(0), 1.0)), "Tip 0", "and every other stop keeps its own")

    slider.dim(1, "")
    assert_true(slider.pick(1), "Brought back, it takes a pick again")
    assert_eq(slider.get_tooltip(Vector2(slider.stop_x(1), 1.0)), "Tip 1", "under its own tooltip")
    slider.free()


func test_a_script_write_moves_the_thumb_and_says_nothing() -> void:
    var slider := _slider(3)
    var heard: Array = []
    slider.picked.connect(func(id: Variant) -> void: heard.append(id))
    slider.value = 2
    assert_eq(slider.describe()["value"], 2, "A write moves the pick")
    assert_eq(heard, [], "and emits nothing, so a page pushing its value back never hears itself")
    slider.free()


func test_samake_marks_it_for_the_walker() -> void:
    var slider := SaMake.stops(null, "Ways", ["One", "Two"])
    assert_eq(SaMake.kind_of(slider), SaMake.Kind.STOPS, "SaMake names the kind")
    assert_eq(String(slider.name), "Ways", "and the node")
    assert_eq(slider.value, 0, "and a bare label's id is its index, the first picked")
    slider.free()


func test_a_modules_dialog_declares_it_through_the_door() -> void:
    var filter := Edged.new()
    var dialog := SaDialog.for_filter(filter)
    var host := VBoxContainer.new()
    dialog.realize(host)
    var row := dialog.row(&"edge")
    var slider := row.control as SaStopSlider
    assert_not_null(slider, "ui.stops draws a stop slider")
    assert_eq(dialog.widget_name(row.key), "stops", "under its own name in the dump")
    assert_eq(slider.value, "soft", "on the default the declaration gave")
    assert_eq(slider.options[0]["tooltip"], "Feathered", "keeping each choice's tooltip")
    assert_eq(filter.parameters().get("edge"), "soft", "and the filter's store holds the same")

    assert_true(slider.pick("hard"), "A hand's pick moves it")
    assert_eq(filter.parameters().get("edge"), "hard", "and writes the filter's value")

    filter.set_parameters({"edge": "soft"})
    dialog.refresh()
    assert_eq(slider.value, "soft", "A value put back behind the page's back moves the thumb")
    host.free()


## A slider of *count* of `WORDS` at its minimum size, ids the indices.
func _slider(count: int) -> SaStopSlider:
    var choices: Array = []
    for index in count:
        choices.append({"id": index, "label": WORDS[index], "tooltip": "Tip %d" % index})
    var slider := SaStopSlider.new(choices)
    slider.size = slider.get_combined_minimum_size()
    return slider


func _click(slider: SaStopSlider, x: float) -> void:
    _press(slider, x, true)
    _press(slider, x, false)


func _press(slider: SaStopSlider, x: float, down: bool) -> void:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = down
    press.position = Vector2(x, slider.size.y - 2.0)
    slider._gui_input(press)


func _move(slider: SaStopSlider, x: float) -> void:
    var motion := InputEventMouseMotion.new()
    motion.position = Vector2(x, slider.size.y - 2.0)
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    slider._gui_input(motion)


func _key(slider: SaStopSlider, keycode: Key) -> void:
    var key := InputEventKey.new()
    key.keycode = keycode
    key.pressed = true
    slider._gui_input(key)
