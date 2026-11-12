extends "res://tests/test_framework.gd"

const SaColorPickerScript = preload("res://ui/dockers/color/sa_color_picker.gd")
const OkhsvConversionsScript = preload("res://utils/okhsv_conversions.gd")


func test_sa_color_picker_init_and_sync() -> void:
    var picker := SaColorPickerScript.new()
    picker.name = "SaColorPicker"
    assert_true(picker != null, "SaColorPicker should instantiate")

    # Adding to the tree invokes _ready(). Do not invoke lifecycle callbacks directly.
    var dummy := Control.new()
    dummy.add_child(picker)

    assert_true(picker.shape != null, "The picker shape should exist")
    assert_true(picker.shape.ring_rect != null, "RingRect should exist")
    assert_true(picker.shape.area_rect != null, "AreaRect should exist")
    assert_true(picker.hex_input != null, "HexInput should exist")
    assert_true(picker.foreground_swatch != null, "The foreground swatch exists")
    assert_true(picker.background_swatch != null, "and the background one")

    # Test setting color
    var test_color := Color(0.1, 0.5, 0.9, 1.0)
    picker.color = test_color
    assert_almost_eq(picker.color.r, test_color.r, 0.02, "Picker color R should match")
    assert_almost_eq(picker.color.g, test_color.g, 0.02, "Picker color G should match")
    assert_almost_eq(picker.color.b, test_color.b, 0.02, "Picker color B should match")

    dummy.free()


## The RGB box, its three sliders, the exposure box and slider and
## their two handlers were declared and never built. Nothing constructs them
## now because nothing declares them.
func test_the_dead_members_are_gone() -> void:
    var picker := SaColorPickerScript.new()
    for dead: String in ["exposure_box", "exposure_slider", "rgb_box", "r_slider", "g_slider", "b_slider"]:
        assert_false(dead in picker, "%s is gone" % dead)
    for handler: String in ["_on_exposure_changed", "_on_rgb_slider_changed"]:
        assert_false(picker.has_method(handler), "%s is gone" % handler)
    picker.free()


## The picker shows the pair and asks for the reset, and owns
## neither. Whoever wires it decides what the pair is. The swap
## button is not here, so the docker asks for two of the three.
func test_the_picker_shows_the_pair_and_asks_rather_than_acts() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    var asked: Array = []
    picker.reset_requested.connect(func() -> void: asked.append("reset"))
    picker.swatch_add_requested.connect(func(color: Color) -> void: asked.append(color))

    picker.color = Color.RED
    picker.background = Color.BLUE
    assert_eq(picker.foreground_swatch.color, Color.RED, "The left swatch is the foreground")
    assert_eq(picker.background_swatch.color, Color.BLUE, "and the right one the background")

    picker.reset_button.pressed.emit()
    picker.palette_row.add_swatch_button.pressed.emit()
    assert_eq(asked.size(), 2, "Two requests")
    assert_eq(asked[0], "reset", "reset")
    assert_true(picker.color.is_equal_approx(asked[1]), "and keep this colour, neither of them acted on here")
    assert_eq(picker.color, Color.RED, "The picker did not change the pair on its own")
    dummy.free()


## The pair has a swap. The background's tooltip promises one, so the docker
## has the button. The button asks,
## the way reset does, and the docker hands the ask to `SaColors.swap`.
func test_the_pair_carries_a_swap_button_that_asks() -> void:
    var picker := SaColorPickerScript.new()
    var asked: Array = []
    picker.swap_requested.connect(func() -> void: asked.append("swap"))
    assert_eq(picker.preview_box.get_node_or_null("SwapButton"), picker.swap_button, "The button sits in the pair's row")
    assert_true(picker.swap_button.get_index() < picker.reset_button.get_index(), "before the reset")
    assert_true("(X)" in picker.swap_button.tooltip_text, "and its tooltip names X")
    picker.swap_button.pressed.emit()
    assert_eq(asked, ["swap"], "A press asks for the swap once")
    picker.free()


func _left_press(at: Vector2 = Vector2.ZERO) -> InputEventMouseButton:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = at
    return press


## A press on the background swatch makes the wheel, the sliders and the
## hex box edit the background, the green rim moves to it, and a press on the
## foreground hands them back.
func test_a_press_on_a_swatch_picks_what_the_wheel_edits() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    picker.color = Color(0.8, 0.2, 0.1)
    picker.background = Color8(51, 153, 230)
    assert_false(picker._editing_background, "The foreground is edited at first")
    assert_true(picker.foreground_swatch.edited, "and its swatch carries the rim")

    var changed: Array = []
    var backgrounds: Array = []
    picker.color_changed.connect(func(c: Color) -> void: changed.append(c))
    picker.background_changed.connect(func(c: Color) -> void: backgrounds.append(c))

    picker.background_swatch.gui_input.emit(_left_press())
    assert_true(picker._editing_background, "A press on the background makes it the edited one")
    assert_true(picker.background_swatch.edited, "the rim moves to it")
    assert_false(picker.foreground_swatch.edited, "and off the foreground")
    assert_eq(picker.hex_input.text, "#3399e6", "The hex box shows the background")
    assert_true(changed.is_empty() and backgrounds.is_empty(), "and a press alone changes no colour")

    var centre: Vector2 = picker.shape.frame.size * 0.5
    picker.shape._on_frame_gui_input(_left_press(centre + Vector2(6, -4)))
    assert_true(changed.is_empty(), "A wheel change while the background is edited leaves the foreground alone")
    assert_eq(backgrounds.size(), 1, "and goes out as a background change")
    assert_true(picker.background.is_equal_approx(backgrounds[0]), "which the picker now shows as its background")
    assert_true(picker.color.is_equal_approx(Color(0.8, 0.2, 0.1)), "and the foreground did not move")

    picker.foreground_swatch.gui_input.emit(_left_press())
    assert_false(picker._editing_background, "A press on the foreground hands the wheel back")
    assert_true(picker.foreground_swatch.edited, "and the rim with it")
    dummy.free()


## Through the docker: a wheel change after a press on the background
## lands in `SaColors.background` and not in the foreground, and the swap
## button exchanges the two in the store.
func test_the_docker_hands_a_background_edit_and_the_swap_to_the_store() -> void:
    var was_foreground := SaColors.foreground
    var was_background := SaColors.background
    SaColors.foreground = Color(0.8, 0.2, 0.1)
    SaColors.background = Color8(51, 153, 230)

    var canvas := Control.new()
    var docker := ColorDocker.new()
    docker.name = "ColorDocker"
    canvas.add_child(docker)
    docker._ready()
    var picker: SaColorPicker = docker.color_picker

    picker.background_swatch.gui_input.emit(_left_press())
    var centre: Vector2 = picker.shape.frame.size * 0.5
    picker.shape._on_frame_gui_input(_left_press(centre + Vector2(6, -4)))
    assert_false(SaColors.background.is_equal_approx(Color8(51, 153, 230)), "The wheel moved the store's background")
    assert_true(SaColors.background.is_equal_approx(picker.background), "to what the picker shows")
    assert_true(SaColors.foreground.is_equal_approx(Color(0.8, 0.2, 0.1)), "and not the foreground")

    var front := SaColors.foreground
    var back := SaColors.background
    picker.swap_button.pressed.emit()
    assert_true(SaColors.foreground.is_equal_approx(back), "The swap puts the background in front")
    assert_true(SaColors.background.is_equal_approx(front), "and the foreground behind")
    assert_true(picker.color.is_equal_approx(back), "and the picker's swatches follow the store")
    assert_true(picker.background.is_equal_approx(front), "both of them")

    # The docker's picker shares the side every picker edits, so a press on the
    # foreground hands it back, or the next suite's picker starts on the background.
    picker.foreground_swatch.gui_input.emit(_left_press())
    canvas.free()
    SaColors.foreground = was_foreground
    SaColors.background = was_background
    SaColors.save()


## The recent list records what was chosen, not what the shape passed over:
## a gesture commits once, when it ends.
func test_a_wheel_gesture_commits_once_when_it_ends() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    var committed: Array = []
    picker.color_committed.connect(func(color: Color) -> void: committed.append(color))
    var changed: Array = []
    picker.color_changed.connect(func(color: Color) -> void: changed.append(color))

    var centre: Vector2 = picker.shape.frame.size * 0.5
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = centre
    picker.shape._on_frame_gui_input(press)
    for i in 5:
        var motion := InputEventMouseMotion.new()
        motion.position = centre + Vector2(i * 3.0, i * 2.0)
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        picker.shape._on_frame_gui_input(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    release.position = centre
    picker.shape._on_frame_gui_input(release)

    # The motions of one frame go out as one colour at its end, so a gesture with no frame in it sends the press's colour and the
    # release's, and the release's is the one under it.
    assert_eq(changed.size(), 2, "The drag changed the colour at the press and at the release")
    assert_eq(changed.back(), picker.shape.color(), "and the colour it ended on is the one under the release")
    assert_eq(committed.size(), 1, "and committed it once")
    dummy.free()


func test_swatches_and_recent_colours_are_drawn_as_chips() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    picker.set_swatches([Color.RED, Color.GREEN])
    picker.set_recent([Color.BLUE])
    # The kept chips are `SaPaletteRow`'s, which is the class that owns that
    # row, and the recent ones stayed here with the rest of the picker's rows.
    assert_eq(picker.palette_row.chips.size(), 2, "Two swatch chips")
    assert_eq(picker.recent_flow.get_child_count(), 1, "One recent chip")
    picker.set_swatches([])
    assert_eq(picker.palette_row.chips.size(), 0, "Rebuilt from the list each time")
    dummy.free()


## A painter who samples the grey background and then moves inside the
## square wants a different colour every time. The hue a grey carries is the
## wheel's own, stepped by the golden angle, so two picks of the same grey
## leave the square showing two different colours.
func test_two_picks_of_one_grey_leave_two_different_hues() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)

    var grey := Color(0.5, 0.5, 0.5, 1.0)
    picker.color = grey
    var first := picker.shape.hue
    picker.color = grey
    var second := picker.shape.hue

    assert_true(absf(first - second) > 0.05, "The second pick of the same grey moved the hue")
    var step: float = OkhsvConversionsScript.GOLDEN_ANGLE_TURNS
    assert_almost_eq(fposmod(second - first, 1.0), step, 1e-5, "by the golden angle")
    assert_true(picker.color.is_equal_approx(grey), "and the colour itself is still the grey that was picked")
    dummy.free()


## The hue only comes from the wheel when the colour has none of its own. A
## colour with chroma keeps the hue it names, however often it is set.
func test_a_coloured_pick_keeps_its_own_hue() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)

    picker.color = Color(0.1, 0.5, 0.9, 1.0)
    var first := picker.shape.hue
    picker.color = Color(0.1, 0.5, 0.9, 1.0)
    assert_eq(picker.shape.hue, first, "A colour with chroma is shown at its own hue every time")
    assert_almost_eq(
        first, OkhsvConversionsScript.srgb_to_okhsv(Color(0.1, 0.5, 0.9, 1.0)).x, 1e-9, "which is what the conversion says"
    )
    dummy.free()


## Godot's own picker is gone from the
## docker, from the member that held it and from the layout settings that
## offered a row for it.
func test_the_godot_picker_is_gone_from_the_docker_and_its_settings() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)

    assert_false("godot_picker" in picker, "The member that held it is gone")
    assert_false(picker.has_method("_on_godot_picker_color_changed"), "and its handler with it")
    assert_eq(picker.find_children("*", "ColorPicker", true, false).size(), 0, "No built-in ColorPicker is in the tree")

    var order: Array = SaSettingsLayout.DEFAULT_ORDERS["ColorPicker"]
    assert_false(order.has("Godot HSL Picker"), "and no row in the layout defaults")
    assert_false(SaSettingsLayout.DEFAULT_HIDDEN["ColorPicker"].has("Godot HSL Picker"), "nor a default that hides one")
    # The choice of shape replaced it and then left the docker itself, so
    # neither is a row in the element list any more. It is a per-docker option on
    # the same Preferences page, which `test_picker_type_option.gd` holds.
    assert_false(order.has("Picker Type"), "and the choice of shape is not a row either, it is an option")
    dummy.free()


## The ok-hsl square and the triangle are two of the
## shapes on offer, and the dropdown in the docker is where they are chosen.
## The fourth is the triangle turned a quarter turn, and the keys are
## appended rather than renumbered so a stored profile still opens on its own
## shape.
func test_the_four_shapes_are_offered_in_the_docker() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)

    assert_eq(picker.picker_report()["type_items"].size(), 7, "Seven shapes")
    assert_eq(
        SaPickerShape.KIND_KEYS,
        ["wheel", "okhsl", "triangle", "triangle_up", "hsv_square", "hsv_triangle", "hsl_square"],
        "the wheel, Sara's ok-hsl, the two triangles, and the three classic shapes"
    )
    assert_eq(picker.shape.kind_key(), "wheel", "and the wheel is what a fresh profile opens on")
    assert_eq(
        SaPickerShape.AREA_MODES.size(),
        SaPickerShape.KIND_KEYS.size(),
        "and every shape names a shader mode, since set_kind indexes one by the other"
    )
    assert_eq(SaPickerShape.KIND_LABELS.size(), SaPickerShape.KIND_KEYS.size(), "and carries a label")
    dummy.free()


## The fourth shape is the third turned a quarter turn, so the two hold the
## same pair of numbers the other way round and show the same colour. That is
## what makes it a reading of the triangle rather than a fourth model, and it is
## the number the design notes' "what the two differ by" is written from.
func test_the_transposed_triangle_is_the_triangle_with_its_axes_swapped() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    var was: String = SaSettings.color_picker_shape

    picker.set_shape_kind(SaPickerShape.Kind.TRIANGLE)
    picker.color = Color(0.1, 0.5, 0.9, 1.0)
    var chroma: float = picker.shape._across
    var lightness: float = picker.shape._up
    var shown: Color = picker.shape.color()

    picker.set_shape_kind(SaPickerShape.Kind.TRIANGLE_UP)
    assert_eq(picker.picker_report()["area_mode"], 4, "The transposed triangle is the shader's fourth mode")
    assert_almost_eq(picker.shape._across, lightness, 1e-6, "Lightness runs along X now")
    assert_almost_eq(picker.shape._up, chroma, 1e-6, "and chroma runs up Y")
    assert_true(picker.shape.color().is_equal_approx(shown), "and the colour on screen did not move")

    SaSettings.color_picker_shape = was
    dummy.free()


## And the clamp follows the swap. A press in the corner outside the gamut is a
## press on the slope, and which axis gives way is the only thing about the
## gesture that differs between the two triangles.
func test_the_transposed_triangle_clamps_the_chroma_axis() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    var was: String = SaSettings.color_picker_shape

    # The top right corner of the area is full chroma at full lightness, which
    # no hue reaches: only white sits at lightness 1.
    picker.set_shape_kind(SaPickerShape.Kind.TRIANGLE_UP)
    # Asked of the shape rather than written into it (f15): `_reach_at` answers for
    # axes handed in, and `_triangle_reach` asks it about the ones the cursor is on,
    # so the gesture and this cannot come apart.
    var lightness := 0.95
    var asked := 1.0
    var reach: float = picker.shape._reach_at(0.733478, lightness, asked)
    var given := minf(asked, reach)

    assert_true(reach < 0.1, "Blue holds almost no chroma at lightness 0.95, %f of its cusp" % reach)
    assert_almost_eq(lightness, 0.95, 1e-6, "so the lightness the press asked for stands")
    assert_true(given <= reach + 1e-6, "and the chroma is the one that gave way")

    SaSettings.color_picker_shape = was
    dummy.free()


## The stretch and the counter-move on the transposed shape, which nothing
## held before. Both were built for the upright triangle and this shape
## came after it, so the one test above covers a hue turn on `triangle` and none
## covered `triangle_up`, whose axes are swapped. The next unit in this file
## moves `cusp_chroma` itself, and a counter-move nothing asserts is one nobody
## notices going.
func test_the_transposed_triangle_stretches_and_counters_like_the_upright_one() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    var was: String = SaSettings.color_picker_shape

    picker.set_shape_kind(SaPickerShape.Kind.TRIANGLE_UP)
    picker.shape.set_from_color(Color(0.18, 0.44, 0.84, 1.0))
    var before := picker.shape.report()

    # A cyan, whose cusp is the narrowest of any hue, and then a magenta, whose
    # cusp is the widest. The two differ by more than twice over, which is what
    # makes a drift in the counter-move visible rather than arguable.
    picker.shape._drag_ring(Vector2.from_angle(TAU * SaPickerShape.ring_angle(0.594, false)) * 100.0)
    var cyan := picker.shape.report()
    picker.shape._drag_ring(Vector2.from_angle(TAU * SaPickerShape.ring_angle(0.911, false)) * 100.0)
    var magenta := picker.shape.report()

    for turned: Dictionary in [cyan, magenta]:
        assert_almost_eq(float(turned["across"]), float(before["across"]), 1e-6, "The cursor stayed where it was across")
        assert_almost_eq(float(turned["up"]), float(before["up"]), 1e-6, "and up")
    assert_true(
        float(magenta["cusp_chroma"]) > float(cyan["cusp_chroma"]) * 2.0,
        (
            "while the width the chroma axis stands for more than doubled, %f to %f"
            % [float(cyan["cusp_chroma"]), float(magenta["cusp_chroma"])]
        )
    )
    assert_true(String(cyan["color"]) != String(magenta["color"]), "so the colour under the cursor is the new hue's")

    SaSettings.color_picker_shape = was
    dummy.free()


## Choosing a shape goes through the setting, so it survives a restart, and
## the area's shader mode follows it. The modes are the shader's own: 1 is the
## OKHSV square, 2 the ok-hsl disc and 3 the triangle.
func test_choosing_a_shape_writes_the_setting_and_switches_the_area() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    var was: String = SaSettings.color_picker_shape

    picker.set_shape_kind(SaPickerShape.Kind.TRIANGLE)
    assert_eq(SaSettings.color_picker_shape, "triangle", "The setting carries the choice")
    assert_eq(picker.shape.kind, SaPickerShape.Kind.TRIANGLE, "and the shape followed it")
    assert_eq(picker.picker_report()["area_mode"], 3, "with the triangle's shader mode up")

    picker.set_shape_kind(SaPickerShape.Kind.OKHSL)
    assert_eq(picker.picker_report()["area_mode"], 2, "and the ok-hsl disc's when that is chosen")

    SaSettings.color_picker_shape = was
    dummy.free()


## Switching shape mid-painting must not change the colour under the brush.
## Each shape reads the same colour into its own two axes rather than keeping
## the numbers and calling them something else.
func test_a_shape_switch_keeps_the_colour() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    var was: String = SaSettings.color_picker_shape

    picker.color = Color(0.1, 0.5, 0.9, 1.0)
    for key: String in ["okhsl", "triangle", "wheel"]:
        SaSettings.color_picker_shape = key
        picker.apply_shape_setting()
        var shown: Color = picker.shape.color()
        assert_almost_eq(shown.r, 0.1, 0.01, "R still, in the %s shape" % key)
        assert_almost_eq(shown.g, 0.5, 0.01, "G still, in the %s shape" % key)
        assert_almost_eq(shown.b, 0.9, 0.01, "B still, in the %s shape" % key)

    SaSettings.color_picker_shape = was
    dummy.free()


## An unknown key is a profile written by a newer build, and reads as the
## wheel rather than as a crash or an empty picker.
func test_an_unknown_shape_key_reads_as_the_wheel() -> void:
    assert_eq(SaPickerShape.kind_of("hexagon"), SaPickerShape.Kind.WHEEL, "Unknown reads as the wheel")
    assert_eq(SaPickerShape.kind_of("triangle"), SaPickerShape.Kind.TRIANGLE, "and a known key as itself")


## A gesture in the triangle cannot leave it: a press in the empty corner
## beside the gamut lands on the slope, which is where the cursor is drawn.
func test_a_press_outside_the_triangle_lands_on_its_edge() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    var was: String = SaSettings.color_picker_shape
    SaSettings.color_picker_shape = "triangle"
    picker.apply_shape_setting()
    # A picker under a parent that is not itself in the tree never runs
    # `_ready`, so the ring and the area have no size until this is asked for.
    picker.shape._on_center_resized()

    var area: Control = picker.shape.area_rect
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    # The top right corner, which is high lightness at full chroma and is
    # outside every hue's triangle.
    press.position = area.position + Vector2(area.size.x - 1.0, 1.0)
    picker.shape._on_frame_gui_input(press)

    var report := picker.shape.report()
    assert_true(float(report["across"]) < 1.0, "The chroma was pulled back inside the gamut")
    assert_true(float(report["up"]) > 0.9, "at the lightness the press asked for")

    SaSettings.color_picker_shape = was
    dummy.free()


## OKHSL is a disc with a lightness slider beside it, not a
## square. The ring goes with it, because the disc's own rim is a hue ring and
## two of them for one hue is a second control for nothing.
func test_the_ok_hsl_shape_is_a_disc_with_a_lightness_slider() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    var was: String = SaSettings.color_picker_shape

    SaSettings.color_picker_shape = "okhsl"
    picker.apply_shape_setting()
    picker.shape._on_center_resized()
    var report := picker.shape.report()
    assert_false(bool(report["ring_visible"]), "The disc carries the hue itself, so the ring is down")
    assert_true(bool(report["lightness_slider_visible"]), "and the third axis is the slider beside it")
    assert_eq(SaPickerShape.KIND_LABELS[SaPickerShape.Kind.OKHSL], "OKHSL, disc", "the dropdown says so too")

    # The disc fills the frame, where the square sat inside the ring at a
    # fraction of it.
    var frame: Control = picker.shape.frame
    var area: Control = picker.shape.area_rect
    assert_almost_eq(area.size.x, frame.size.x, 1.0, "and it is the whole frame rather than the square's inset")

    for key: String in ["wheel", "triangle"]:
        SaSettings.color_picker_shape = key
        picker.apply_shape_setting()
        var other := picker.shape.report()
        assert_true(bool(other["ring_visible"]), "The %s keeps its ring" % key)
        assert_false(bool(other["lightness_slider_visible"]), "and has no slider, its area holding both axes")

    SaSettings.color_picker_shape = was
    dummy.free()


## A press in the disc reads a hue and a saturation from one gesture: the angle
## round the middle and the distance out from it. Dead centre is a grey, which
## has no angle, so the hue stays where the painter last left it.
func test_a_press_in_the_disc_reads_hue_and_saturation_together() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    var was: String = SaSettings.color_picker_shape
    SaSettings.color_picker_shape = "okhsl"
    picker.apply_shape_setting()
    picker.shape._on_center_resized()

    var area: Control = picker.shape.area_rect
    var middle := area.position + area.size * 0.5
    var radius := minf(area.size.x, area.size.y) * 0.5

    # Straight up from the middle, three quarters of the way out.
    _press_at(picker.shape, middle + Vector2(0.0, -radius * 0.75))
    var report := picker.shape.report()
    assert_almost_eq(float(report["across"]), 0.75, 0.02, "Three quarters out is three quarters of the saturation")
    var up_hue := SaPickerShape.ring_hue(0.75, false)
    assert_almost_eq(float(report["hue"]), up_hue, 0.01, "and straight up is half a turn from yellow")

    var held := float(report["hue"])
    _press_at(picker.shape, middle)
    var centred := picker.shape.report()
    assert_almost_eq(float(centred["across"]), 0.0, 0.01, "The middle is a grey")
    assert_almost_eq(float(centred["hue"]), held, 1e-6, "and a grey leaves the hue where it was")

    SaSettings.color_picker_shape = was
    dummy.free()


## The triangle is drawn against the hue's own cusp rather
## than one constant for every hue, so each one fills its frame. What must not
## change with it is where the cursor sits: turning the ring moves the colour,
## not the two axes under it.
func test_the_triangle_fills_its_frame_and_the_cursor_does_not_drift() -> void:
    var picker := SaColorPickerScript.new()
    var dummy := Control.new()
    dummy.add_child(picker)
    var was: String = SaSettings.color_picker_shape
    SaSettings.color_picker_shape = "triangle"
    picker.apply_shape_setting()
    picker.shape._on_center_resized()

    # Every hue's widest chroma is its own cusp, so the fraction the right edge
    # stands for is 1.0 at the cusp's lightness whatever the hue.
    for hue: float in [0.0, 0.1, 0.3, 0.5, 0.72, 0.9]:
        var cusp := OkhsvConversions.find_cusp(cos(TAU * hue), sin(TAU * hue))
        assert_almost_eq(picker.shape._reach_at(hue, 0.0, cusp.x), 1.0, 0.01, "Hue %.2f reaches the right edge at its cusp" % hue)

    picker.shape.set_from_color(Color(0.18, 0.44, 0.84, 1.0))
    var before := picker.shape.report()
    var narrow := float(before["cusp_chroma"])

    # Turning the ring, which is the gesture under test.
    picker.shape._drag_ring(Vector2.from_angle(TAU * SaPickerShape.ring_angle(0.297, false)) * 100.0)
    var after := picker.shape.report()

    assert_almost_eq(float(after["across"]), float(before["across"]), 1e-6, "The cursor stayed where it was across")
    assert_almost_eq(float(after["up"]), float(before["up"]), 1e-6, "and up")
    assert_true(
        absf(float(after["cusp_chroma"]) - narrow) > 0.01,
        "while the width the axis stands for moved, %f to %f" % [narrow, float(after["cusp_chroma"])]
    )
    assert_true(String(after["color"]) != String(before["color"]), "so the colour under it is the new hue's")

    SaSettings.color_picker_shape = was
    dummy.free()


## A press on the shape's frame, the way a hand makes one.
func _press_at(shape: SaPickerShape, at: Vector2) -> void:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = at
    shape._on_frame_gui_input(press)
    press = InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = false
    press.position = at
    shape._on_frame_gui_input(press)


# --- The wheel's side ----------------------------------------


## The docker's own column, a scroll holding a margin holding the picker, at
## *width* by *height* in a viewport in the tree, with the shape and the pair
## shown and nothing else, which is what the Default layout ships.
##
## In the tree because the rule reads the height the rows below the wheel take,
## and a flow's height is only known once it has been sorted.
func _column(width: int, height: int) -> SaColorPicker:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(width, height)
    EventBus.add_child(viewport)
    var scroll := SaMake.scroll(viewport, "Scroll")
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size = Vector2(width, height)
    var margin := SaMake.margin(scroll, "MarginContainer", SaUI.BASE_MARGIN)
    margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
    var picker := SaColorPickerScript.new()
    margin.add_child(picker)
    for child in picker.get_children():
        var row := child as Control
        if row != null:
            row.visible = row == picker.shape or row == picker.preview_box
    _lay_out(viewport)
    return picker


## Sorts every container under *node*, outside in, twice, so the wheel's fit
## before a sort and the flows' heights after one have both landed. A test
## cannot await a frame.
func _lay_out(node: Node) -> void:
    for _pass in 2:
        _sort_under(node)


func _sort_under(node: Node) -> void:
    for child: Node in node.get_children():
        var box := child as Container
        if box != null:
            box.notification(Container.NOTIFICATION_PRE_SORT_CHILDREN)
            box.notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_under(child)


## The viewport `_column` put the picker in, freed with everything in it.
func _free_column(picker: SaColorPicker) -> void:
    var node: Node = picker
    while node != null and not node is SubViewport:
        node = node.get_parent()
    if node != null:
        node.free()


## A docker tall enough for it draws the wheel square at its inner width. The
## width is the docker's own, less the margin on either side, and the frame the
## shape draws in is that side both ways.
func test_the_wheel_is_square_at_the_dockers_inner_width() -> void:
    var width := ColorDocker.DEFAULT_SIZE.x
    var picker := _column(width, 900)
    var inner := float(width - 2 * SaUI.px(SaUI.BASE_MARGIN))
    var wheel := picker.wheel_report()
    assert_almost_eq(float(wheel["width"]), inner, 0.5, "The column is the docker's inner width")
    assert_almost_eq(float(wheel["side"]), inner, 1.0, "and the wheel's side is that width: %s" % wheel)
    assert_almost_eq(picker.shape.frame.size.x, picker.shape.frame.size.y, 0.5, "The frame is square")
    assert_almost_eq(picker.shape.frame.size.x, inner, 1.0, "at the width")
    assert_almost_eq(picker.shape.size.y, float(wheel["side"]), 0.5, "and the shape is no taller than its wheel")
    assert_true(
        picker.preview_box.position.y < picker.shape.size.y + 20.0,
        "so the pair sits under the wheel, not at the docker's foot: %f" % picker.preview_box.position.y
    )
    _free_column(picker)


## A shorter docker caps the wheel at the height the rows under it leave, so
## nothing is pushed past the bottom edge while there is room for a wheel.
func test_a_shorter_docker_caps_the_wheel_at_the_height_left() -> void:
    var width := ColorDocker.DEFAULT_SIZE.x
    var picker := _column(width, 220)
    var inner := float(width - 2 * SaUI.px(SaUI.BASE_MARGIN))
    var wheel := picker.wheel_report()
    assert_true(float(wheel["left"]) < inner, "The height left is under the width: %s" % wheel)
    assert_almost_eq(float(wheel["side"]), roundf(float(wheel["left"])), 0.5, "and the wheel takes the height left")
    assert_almost_eq(picker.shape.frame.size.x, picker.shape.frame.size.y, 0.5, "still square")
    assert_true(picker.rows_fit()["fits"], "and every row fits in the docker: %s" % picker.rows_fit())
    _free_column(picker)


## A docker too short for a usable wheel still gets one of WHEEL_MIN, and the
## rows scroll rather than squeeze it to a dot.
func test_the_wheel_is_never_under_its_minimum() -> void:
    var picker := _column(ColorDocker.DEFAULT_SIZE.x, 90)
    var floor_side := float(SaUI.px(SaColorPicker.WHEEL_MIN))
    assert_almost_eq(float(picker.wheel_report()["side"]), floor_side, 0.5, "The side is WHEEL_MIN")
    assert_almost_eq(picker.shape.frame.size.x, floor_side, 0.5, "and so is the frame drawn in it")
    _free_column(picker)


## The rule on its own, where the numbers are chosen: the width in a tall
## room, the height left in a short one, and the floor under both. The disc
## carries its lightness bar beside it, and the side gives the bar its width.
func test_the_side_is_the_width_capped_by_the_height_left() -> void:
    var picker := SaColorPickerScript.new()
    for child in picker.get_children():
        var row := child as Control
        if row != null:
            row.visible = row == picker.shape
    var floor_side := float(SaUI.px(SaColorPicker.WHEEL_MIN))
    assert_eq(picker.wheel_side(280.0, 1000.0), 280.0, "A tall room gives the width")
    assert_eq(picker.wheel_side(280.0, 200.0), 200.0, "a short one the height")
    assert_eq(picker.wheel_side(280.0, 40.0), floor_side, "and never under WHEEL_MIN")
    picker.shape.lightness_bar.visible = true
    var bar := float(SaUI.px(SaPickerShape.SLIDER_W) + SaUI.px(SaPickerShape.SLIDER_GAP))
    assert_eq(picker.wheel_side(280.0, 1000.0), 280.0 - bar, "The disc's bar is paid for out of the width")
    picker.free()
