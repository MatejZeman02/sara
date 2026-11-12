## Wrap Offset's sliders have nought at the middle of their
## track.
##
## The note, from the `filters` sweep's F8: "The track runs from about -15360
## to +1920 and 0 sits at about 88 percent along it." The filter declares a soft
## range of minus 2048 to 2048 and a hard one of 16384 either side, and
## `FactorSlider` knew a soft ceiling only, so its drag ran from the hard floor
## to the soft ceiling. It has a soft floor now, `SaSlider.make` passes the
## declared one through, and the track is minus 2048 to 2048 while a typed
## number still goes to the hard end.
##
## The drag is driven through `_gui_input`, called by hand, because an injected
## motion never reaches it.
extends "res://tests/test_framework.gd"

const WIDTH := 200.0
const SOFT := float(SaWrapOffsetFilter.SOFT_REACH)
const HARD := float(SaWrapOffsetFilter.HARD_REACH)

## Held here, because a `Callable` does not keep its object alive and the
## dialog declares its rows through the filter's own `build`.
var _filter: SaWrapOffsetFilter = null
var _dialog: SaDialog = null
var _host: VBoxContainer = null


func before_each() -> void:
    _host = VBoxContainer.new()
    _host.name = "S27WrapOffsetHost"
    # A `LineEdit` refuses `grab_focus` outside a tree and `_start_editing`
    # grabs, so the dialog is in one.
    EventBus.add_child(_host)
    _filter = SaWrapOffsetFilter.new()
    _dialog = SaDialog.new(_filter.build)
    _dialog.declare_rows()
    _dialog.realize(_host)


func after_each() -> void:
    _host.free()
    _host = null
    _dialog = null
    _filter = null


## The slider a row of the dialog draws, sized so a drag has a box to run over.
func _slider(key: StringName) -> FactorSlider:
    var slider := _dialog.row(key).control as FactorSlider
    slider.size = Vector2(WIDTH, 18.0)
    return slider


## A press at *from* and a drag to *to*, through the handler a pointer reaches.
func _drag(slider: FactorSlider, from: float, to: float) -> void:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = Vector2(from, 9.0)
    slider._gui_input(press)
    var motion := InputEventMouseMotion.new()
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    motion.position = Vector2(to, 9.0)
    slider._gui_input(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.position = motion.position
    slider._gui_input(release)


## A number typed into the slider's box and committed with Enter.
func _type(slider: FactorSlider, text: String) -> void:
    slider.start_editing()
    slider._line_edit.text = text
    slider._stop_editing()


## "The painter expects a range centred on 0." Each row says its soft range is
## the declared one either side of nought, its hard range the typed reach, and
## its slider puts nought at half the box.
func test_both_rows_say_a_soft_range_centred_on_zero() -> void:
    for key: StringName in [&"offset_x", &"offset_y"]:
        var described := (_dialog.row(key) as SaSlider).describe()
        assert_eq(described["hard"], [-HARD, HARD], "%s types out to 16384 either side" % key)
        assert_almost_eq(float(described["soft_min"]), -SOFT, 0.001, "%s's drag starts at minus 2048" % key)
        assert_almost_eq(float(described["soft_max"]), SOFT, 0.001, "and stops at 2048")
        var slider := _slider(key)
        assert_almost_eq(slider.drag_min(), -SOFT, 0.001, "The slider's floor is the soft one")
        assert_almost_eq(slider.drag_max(), SOFT, 0.001, "and its ceiling the soft one")
        assert_almost_eq(slider.ratio_of_value(0.0, slider.drag_max()), 0.5, 0.0001, "so nought is the middle of the box")


## "One way is almost unusable." A drag to the left end is minus 2048, to the
## right end 2048, and back to the middle nought, and each reaches the row.
func test_a_drag_reaches_both_soft_ends_and_the_middle() -> void:
    var row := _dialog.row(&"offset_x") as SaSlider
    var slider := _slider(&"offset_x")
    _drag(slider, WIDTH * 0.5, 0.0)
    assert_almost_eq(slider.value, -SOFT, 0.5, "The left end is minus 2048, not the hard minus 16384")
    assert_almost_eq(float(row.value), -SOFT, 0.5, "and the row holds it")
    _drag(slider, WIDTH * 0.5, WIDTH)
    assert_almost_eq(slider.value, SOFT, 0.5, "The right end is 2048")
    _drag(slider, WIDTH * 0.25, WIDTH * 0.5)
    assert_almost_eq(slider.value, 0.0, 0.5, "and the middle is nought")
    _drag(slider, WIDTH * 0.5, -WIDTH)
    assert_almost_eq(slider.value, -SOFT, 0.5, "A drag past the left end stops at the soft floor")


## "Typing 5000 still works." A typed number goes past the soft ends to the hard
## ones, draws as a full or an empty track, and stops at the hard reach.
func test_a_typed_number_goes_past_the_soft_ends() -> void:
    var slider := _slider(&"offset_y")
    _type(slider, "5000")
    assert_almost_eq(slider.value, 5000.0, 0.001, "5000 is typed past the soft ceiling")
    assert_almost_eq(slider.ratio_of_value(slider.value, slider.drag_max()), 1.0, 0.0001, "and draws as full")
    _type(slider, "-5000")
    assert_almost_eq(slider.value, -5000.0, 0.001, "minus 5000 past the soft floor")
    assert_almost_eq(slider.ratio_of_value(slider.value, slider.drag_max()), 0.0, 0.0001, "and draws as empty")
    _type(slider, "-20000")
    assert_almost_eq(slider.value, -HARD, 0.001, "and the hard floor still holds")


## "A painter dragging Brightness or any slider with no soft floor sees no
## change." A floor the call wrote as the hard one gives no soft floor, the
## drag starts at the hard minimum, and Brightness's left end is minus a hundred.
func test_a_slider_with_no_soft_floor_drags_from_its_hard_floor() -> void:
    var radius := SaSlider.make("Radius", 1, 20, 3, {"hard_max": 200})
    assert_almost_eq(radius.soft_min, 0.0, 0.0001, "A floor the hard one equals is no soft floor")
    var brightness := SaSlider.make("Brightness", -100, 100, 0, {})
    assert_almost_eq(brightness.soft_min, 0.0, 0.0001, "nor is Brightness's")
    var slider := brightness.custom_control as FactorSlider
    _host.add_child(slider)
    slider.size = Vector2(WIDTH, 18.0)
    assert_almost_eq(slider.drag_min(), -100.0, 0.0001, "Its drag starts at the hard floor")
    _drag(slider, WIDTH * 0.5, 0.0)
    assert_almost_eq(slider.value, -100.0, 0.5, "and its left end is minus a hundred")
    radius.custom_control.free()


## Zero is the unset soft floor, as zero is the unset soft ceiling, and a floor
## at or under the hard one, or over the ceiling, is no floor either.
func test_an_unset_or_impossible_soft_floor_is_the_hard_floor() -> void:
    var slider := FactorSlider.new()
    slider.min_value = -100.0
    slider.max_value = 100.0
    assert_almost_eq(slider.drag_min(), -100.0, 0.0001, "An unset soft floor leaves the hard one")
    slider.soft_min_value = -150.0
    assert_almost_eq(slider.drag_min(), -100.0, 0.0001, "a soft floor under the hard one is the hard one")
    slider.soft_max_value = 40.0
    slider.soft_min_value = 60.0
    assert_almost_eq(slider.drag_min(), -100.0, 0.0001, "and one over the soft ceiling is the hard one")
    slider.soft_min_value = -40.0
    assert_almost_eq(slider.drag_min(), -40.0, 0.0001, "while minus forty under a ceiling of forty is a floor")
    slider.free()
