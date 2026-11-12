## The tool options bar built from each tool's SaOptionSpec list,
## and the one stored-layout migration that renamed every control to its
## option key. The right-click menu over the same list is
## `test_tool_context_menu.gd`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A machine holding the built-in tools needs a surface, which needs a device.
const REQUIRES_GPU := true

static var scratch_profile: String = SaDataRoot.path("test_option_specs.cfg")

var _saved_path: String = ""
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _bar: ToolOptionsBar = null


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _registries = Fixtures.make_registries(_surface)
    _bar = ToolOptionsBar.new()
    _bar.target_tool_machine = _machine
    _bar._ready()
    _bar.bind_registries(_registries.blend_modes)


func after_each() -> void:
    _bar.free()
    Fixtures.teardown(_surface, _machine)
    _registries = null
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


func _brush() -> ToolState:
    return _machine.get_tool("brush")


## The menus a fresh bar holds before the sentinel and *named* lacks, in a
## fresh bar's order, which is the order `get_layout_order` seats them in.
func _menus_seated_into(named: Array) -> Array:
    var shipped: Array = SaSettings.DEFAULT_ORDERS["TopMenuBar"]
    var menus := shipped.slice(0, shipped.find(SaSettings.ROW_SENTINEL))
    return menus.filter(func(menu: Variant) -> bool: return not named.has(menu))


## *order* with every element of *dropped* taken out, the rest as it stood.
func _without(order: Array, dropped: Array) -> Array:
    return order.filter(func(element: Variant) -> bool: return not dropped.has(element))


## Every option the brush declares gets a control of the kind its spec names,
## under the key the stored layout knows it by, in the order it was declared.
func test_the_bar_builds_one_control_per_declared_key() -> void:
    var descriptor := _machine.get_descriptor(&"brush")
    assert_true(descriptor.options.size() >= 11, "The brush declares its options: %d" % descriptor.options.size())
    var elements := _bar.layout_elements()
    var built: Array[StringName] = []
    for spec: SaOptionSpec in descriptor.options:
        var control := _bar.control_for(spec.key)
        if not spec.bar:
            # The option is a Tool Options docker row and not a bar one.
            assert_null(control, "No bar control for '%s'" % spec.key)
            continue
        assert_not_null(control, "A control for '%s'" % spec.key)
        if control == null:
            continue
        built.append(spec.key)
        assert_eq(elements.get(String(spec.key)), control, "listed for the layout pass under its key")
        match spec.kind:
            SaOptionSpec.Kind.FLOAT:
                assert_true(control is FactorSlider, "'%s' is a slider" % spec.key)
            SaOptionSpec.Kind.BOOL:
                assert_true(control is Button and (control as Button).toggle_mode, "'%s' is a toggle" % spec.key)
            SaOptionSpec.Kind.ENUM:
                # A button opening the app's own row list,
                # where it was an `OptionButton`.
                assert_true(control is SaChoiceButton, "'%s' is a dropdown" % spec.key)
            SaOptionSpec.Kind.BLEND_MODE:
                assert_true(control is BlendModeButton, "'%s' is a blend menu" % spec.key)
            _:
                pass
    assert_eq(_bar.options.keys().slice(0, built.size()), built, "in the order the descriptor declared them")
    assert_null(_bar.control_for(&"spacing"), "and nothing for a setting no tool declared")


## A spec's property may reach into a nested resource: the brush's hardness
## and flow are GammaFloats, and the slider moves their `value`.
func test_a_nested_property_is_written_and_read_through_the_path() -> void:
    var settings: Resource = _brush().settings
    var hardness := _bar.control_for(&"hardness") as FactorSlider
    hardness.value_changed.emit(0.7)
    assert_almost_eq(settings.hardness.value, 0.7, 0.0001, "The slider wrote hardness:value")
    var flow := _bar.control_for(&"flow") as FactorSlider
    flow.value_changed.emit(0.3)
    assert_almost_eq(settings.flow.value, 0.3, 0.0001, "and flow:value")

    settings.hardness.value = 0.2
    _bar._sync_ui_from_settings()
    assert_almost_eq(hardness.value, 0.2, 0.0001, "and reads it back on a sync")
    assert_almost_eq(float(_bar.read_option(&"hardness")), 0.2, 0.0001, "which is what read_option answers too")


## The brush and the eraser both declare `radius`, so there is one Size
## control that shows and writes whichever of the two is the permanent tool.
func test_a_shared_key_follows_the_shown_tool() -> void:
    var brush := _brush()
    var eraser := _machine.get_tool("eraser")
    brush.settings.radius = 0.05
    eraser.settings.radius = 0.1
    _machine.set_active_tool(&"brush")
    _bar._sync_ui_from_settings()
    var size := _bar.control_for(&"radius") as FactorSlider
    assert_almost_eq(size.value, 0.05, 0.0001, "On the brush the slider shows the brush's radius")
    assert_true(_bar.shows_for_active_tool(size), "and has a place on the bar")

    _machine.set_active_tool(&"eraser")
    assert_eq(_bar.control_for(&"radius"), size, "The eraser shares the control rather than getting a second")
    assert_almost_eq(size.value, 0.1, 0.0001, "which now shows the eraser's radius")
    size.value_changed.emit(0.15)
    assert_almost_eq(eraser.settings.radius, 0.15, 0.0001, "and writes the eraser")
    assert_almost_eq(brush.settings.radius, 0.05, 0.0001, "leaving the brush alone")


## Holding a quick tool's key must not rearrange the bar under the hand, so
## the bar follows the permanent tool rather than the held one.
func test_a_held_quick_tool_leaves_the_bar_alone() -> void:
    _machine.set_active_tool(&"brush")
    var space := InputEventKey.new()
    space.physical_keycode = KEY_SPACE
    space.pressed = true
    _machine._update_held_keys(space)
    _machine._evaluate_tool()
    assert_eq(_machine.active_tool_name, &"pan", "Space holds the pan tool")
    assert_eq(_bar.shown_tool_id(), &"brush", "while the bar stays on the brush")
    assert_true(_bar.shows_for_active_tool(_bar.control_for(&"radius")), "with its controls in place")
    space.pressed = false
    _machine._update_held_keys(space)
    _machine._evaluate_tool()

    _machine.set_active_tool(&"pan")
    assert_eq(_bar.shown_tool_id(), &"pan", "Pan chosen for good is shown")
    # The line that stood here asserted the brush's controls went. The note is "when brush mode is not selected, all these brush
    # settings dissapear. It is an unwanted behaviour", and a painter's answer is
    # that the group stays for every tool and stays live, nothing
    # dimmed. Pan still declares nothing of its own, which is the other half.
    assert_true(_bar.shows_for_active_tool(_bar.control_for(&"radius")), "and the brush's stay, as Krita's do")
    assert_eq(_bar.owner_of(&"radius"), &"brush", "reading and writing the brush rather than the pan")
    assert_true(_bar.shows_for_active_tool(_bar.preset_box), "while the skeleton's own stay too")


## The erase toggle lives on the tool, not its settings, and announces itself
## from its setter so the key and the bar agree whichever moved it.
func test_the_erase_toggle_writes_the_brush_and_follows_the_key() -> void:
    var brush := _brush()
    var toggle := _bar.control_for(&"eraser_toggled") as Button
    toggle.toggled.emit(true)
    assert_true(brush.eraser_toggled, "The toggle wrote the brush")
    brush.toggle_eraser()
    assert_false(brush.eraser_toggled, "The key flipped it back")
    assert_false(toggle.button_pressed, "and the toggle followed through the event")


## The radius is a fraction of the canvas, shown as pixels of the document
## under the bar.
func test_the_size_slider_shows_pixels_of_the_document() -> void:
    var size := _bar.control_for(&"radius") as FactorSlider
    assert_almost_eq(size.display_value_multiplier, 256.0, 0.01, "A 256 canvas shows the fraction times 256")
    assert_true(size.normalized_display == false, "and not as a percentage")
    var opacity := _bar.control_for(&"opacity") as FactorSlider
    assert_true(opacity.normalized_display, "while opacity is a percentage")


## A painter's question: does storing the size as a fraction
## of the canvas make it resolution independent? One setting, two document
## sizes: the row's pixels and the ring's pixels both double, and the preset
## that carries the fraction never changes.
func test_one_size_is_twice_the_pixels_on_a_document_twice_as_large() -> void:
    var brush := _brush()
    brush.settings.radius = 0.1
    _machine.set_active_tool(&"brush")
    _bar._sync_ui_from_settings()
    var size := _bar.control_for(&"radius") as FactorSlider
    assert_almost_eq(size.display_value_multiplier * size.value, 25.6, 0.01, "0.1 of a 256 canvas is 25.6 px on the row")
    assert_almost_eq(brush.get_cursor_radius(), 25.6, 0.01, "and the ring is the same 25.6 px")

    var document: SaDocument = _surface.get_document()
    document.canvas_size = Vector2i(512, 512)
    EventBus.document_resized.emit(document, document.canvas_size)
    assert_almost_eq(size.display_value_multiplier * size.value, 51.2, 0.01, "Twice the document, twice the pixels on the row")
    assert_almost_eq(brush.get_cursor_radius(), 51.2, 0.01, "and on the ring")
    assert_almost_eq(brush.settings.radius, 0.1, 0.0001, "while the stored fraction is what it was")


## The Size row's two ceilings: the drag stops at half the
## smaller dimension, a typed value at the whole of it, both the machine's
## constants so the shift-drag and the brackets agree with the row.
func test_the_size_row_drags_to_the_soft_ceiling_and_types_to_the_hard_one() -> void:
    var size := _bar.control_for(&"radius") as FactorSlider
    assert_almost_eq(size.soft_max_value, ToolMachine.BRUSH_RADIUS_SOFT_MAX, 0.0001, "The drag's ceiling")
    assert_almost_eq(size.max_value, ToolMachine.BRUSH_RADIUS_MAX, 0.0001, "and the typed one")
    assert_true(size.max_value * 1080.0 >= 500.0, "so 500 px fits on the default document")
    assert_true(size.drag_max() * 1080.0 >= 500.0, "by dragging, not only by typing")


## The Size row is geometric and reaches under a pixel, which is the note's
## two clauses on the control itself: "Size smaller than 1 should be allowed.
## Also make it logarithmic scale (the slider)." The mapping is the slider's own
## and is proved in `test_factor_slider.gd`. What this pins is that the brush's
## declaration asks for it, and that the floor it asks for is a size that paints.
func test_the_size_row_is_geometric_and_reaches_under_a_pixel() -> void:
    var size := _bar.control_for(&"radius") as FactorSlider
    assert_true(size.logarithmic, "The brush's Size row asks for the geometric drag")
    assert_almost_eq(size.min_value, ToolMachine.BRUSH_RADIUS_MIN, 1e-9, "and its floor is the machine's")
    # The row's own document, which this fixture builds at 256 rather than the
    # app's 1080, so the pixels are the multiplier's rather than a literal.
    var pixels_per_unit: float = size.display_value_multiplier
    assert_true(
        size.min_value * pixels_per_unit < 1.0,
        "which is under a pixel on this row's document: %.4f px" % (size.min_value * pixels_per_unit)
    )
    # Two decimals are what let that show: at one, every size under a pixel
    # would draw as "0 px" or "1 px" and the note's own 0.5 would be invisible.
    assert_eq(size.decimal_places, 2, "and the row carries the second decimal a sub-pixel size needs")
    # A geometric row is not quantized, or the absolute step would round a
    # typed half pixel back up to a whole one.
    size._line_edit.visible = true
    size._line_edit.text = "0.5"
    size._stop_editing()
    assert_almost_eq(size.value * pixels_per_unit, 0.5, 0.01, "A typed half pixel survives the step")
    assert_eq(size._label.text, "Radius: 0.50 px", "and reads as half a pixel")
    # And a whole size reads its two decimals too, so the
    # text keeps one width while the row is dragged.
    size._line_edit.visible = true
    size._line_edit.text = "25"
    size._stop_editing()
    assert_eq(size._label.text, "Radius: 25.00 px", "as a whole size does, with the noughts the row always shows")


## Preferences shows a key under its label and the tools that declare it.
func test_preferences_calls_a_key_by_its_label_and_tools() -> void:
    assert_eq(SaSettings.element_title("TopMenuBar", "radius"), "Radius (Brush, Eraser)", "A shared key names both tools")
    assert_eq(
        SaSettings.element_title("TopMenuBar", "blend_mode"),
        "Blend Mode (Brush, Eraser)",
        "and so does the mode the brush and the eraser share"
    )
    # This asserted the raw key, because the option carried `bar = false`,
    # no control was built and `element_title` had nothing to ask. That was the
    # defect rather than the design: the page drew the row anyway and called it
    # `sample_merged`. Every tool that declares the key is named now, the way
    # the two above are, and now that the eyedropper has a Sample
    # row of its own in place of Merged that is the wand alone.
    assert_eq(
        SaSettings.element_title("TopMenuBar", "sample_merged"),
        "Sample merged (Magic Wand)",
        "and a key one tool declares names that tool, whichever surface shows it"
    )
    assert_eq(SaSettings.element_title("TopMenuBar", "sample_from"), "Sample (Eyedropper)", "as the eyedropper's Sample row does")
    assert_eq(SaSettings.element_title("TopMenuBar", "Brush Presets"), "Brush Presets", "A skeleton element is its own title")


## A profile from before the bar built itself names every control by an
## English label. The migration renames each to its key in place, keeps the
## visibility, keeps the sentinel where it was, and puts the exposure
## slider where it used to draw, at the end of the first row.
##
## The profile names two menus, and the read seats the nine it lacks
## after Edit, among its own. Those are taken out before the order is read for
## the renames, and read where the read seats them.
func test_a_version_4_profile_is_renamed_and_keeps_its_sentinel() -> void:
    var config := ConfigFile.new()
    config.set_value("meta", "version", 4)
    config.set_value(
        "profile_order",
        "TopMenuBar",
        [
            "File",
            "Edit",
            "Brush Presets",
            "Blend Mode",
            "Flow Slider",
            "Second Row",
            "Size Slider",
            "Opacity Slider",
            "Stabilizer"
        ]
    )
    config.set_value("profile_visibility", "TopMenuBar_Size Slider", false)
    config.set_value("profile_visibility", "TopMenuBar_Stabilizer", false)
    config.save(ProjectSettings.globalize_path(scratch_profile))

    SaSettings.load_settings()
    var order := SaSettings.get_layout_order("TopMenuBar")
    var seated := _menus_seated_into(["File", "Edit"])
    assert_eq(
        _without(order, seated).slice(0, 10),
        ["File", "Edit", "Brush Presets", "blend_mode", "flow", "exposure", "Second Row", "radius", "opacity", "stabilizer_mode"],
        "Each name became its key in place, with exposure beside Flow where it drew"
    )
    assert_eq(order.slice(2, 2 + seated.size()), seated, "while the menus it lacked are seated after Edit, among its own")
    assert_false(order.has("Size Slider"), "and the old name is gone")
    assert_false(SaSettings.get_element_visible("TopMenuBar", "radius"), "A hidden slider stays hidden under its key")
    assert_false(SaSettings.get_element_visible("TopMenuBar", "stabilizer_mode"), "and so does a hidden dropdown")
    assert_true(SaSettings.get_element_visible("TopMenuBar", "opacity"), "while a shown one stays shown")
    assert_true(order.has("flow"), "and every default the profile lacked is appended")
    assert_eq(int(SaSettings.config.get_value("meta", "version", 0)), SaSettings.SETTINGS_VERSION, "at the current version")


## A stored order without Flow puts exposure in front of the sentinel, and a
## fresh profile reads the defaults with exposure beside Flow.
func test_exposure_lands_before_the_sentinel_when_flow_is_not_listed() -> void:
    var config := ConfigFile.new()
    config.set_value("meta", "version", 4)
    config.set_value("profile_order", "TopMenuBar", ["File", "Size Slider", "Second Row", "Stabilizer"])
    config.save(ProjectSettings.globalize_path(scratch_profile))
    SaSettings.load_settings()
    var order := SaSettings.get_layout_order("TopMenuBar")
    var seated := _menus_seated_into(["File"])
    var first_row := ["File", "radius", "exposure", "Second Row"]
    assert_eq(_without(order, seated).slice(0, 4), first_row, "In front of the sentinel, on the first row")
    assert_eq(order.slice(1, 1 + seated.size()), seated, "after the menus the profile lacked, which are seated after File")

    SaSettings.set_layout_order("TopMenuBar", [])
    _remove_profile()
    SaSettings.load_settings()
    order = SaSettings.get_layout_order("TopMenuBar")
    var sentinel := order.find(SaSettings.ROW_SENTINEL)
    assert_eq(order.find("exposure"), order.find("flow") + 1, "A fresh profile has exposure beside Flow")
    assert_true(order.find("exposure") > sentinel, "on the second row with the brush's other controls since")
    assert_true(order.find("stabilizer_mode") > order.find("exposure"), "and the stabilizer after it")


## `SaOptionSpec.advanced` had existed since the module API was written and
## nothing read it, so a module author who set the flag saw no effect and every
## tool option was shown to every painter. One function reads it now, so
## both surfaces can ask the same question.
func test_an_advanced_option_is_shown_only_while_the_setting_is_on() -> void:
    var previous: bool = SaSettings.advanced_options
    var plain := SaOptionSpec.make(&"plain", "Plain", SaOptionSpec.Kind.BOOL)
    var hidden := SaOptionSpec.make(&"hidden", "Hidden", SaOptionSpec.Kind.BOOL)
    hidden.advanced = true

    SaSettings.advanced_options = false
    assert_true(ToolOptionControls.shows_advanced(plain), "An ordinary option is always shown")
    assert_false(ToolOptionControls.shows_advanced(hidden), "and a flagged one is not, by default")
    assert_true(ToolOptionControls.shows_advanced(null), "A spec that is not there is not a reason to hide a row")

    SaSettings.advanced_options = true
    assert_true(ToolOptionControls.shows_advanced(hidden), "The check brings it back")
    assert_true(ToolOptionControls.shows_advanced(plain), "and leaves the rest alone")

    SaSettings.advanced_options = previous


## Off by default, and additive, so a profile written before the setting reads false and
## behaves exactly as it did. That is why `SETTINGS_VERSION` did not move for it.
##
## **It used to say so by pinning the version at 11**, which is a proxy rather
## than the claim: the number moves the first time something else needs a
## migration, and the rename of the `raw` view mode is that something. The claim
## is that an older profile still reads off and that no migration writes the key,
## and this drives `SaSettingsMigrations` over a version-10 profile to say it.
func test_the_advanced_setting_is_off_by_default_and_costs_no_version() -> void:
    var previous: bool = SaSettings.advanced_options
    var config := ConfigFile.new()
    assert_false(config.get_value("ui", "advanced_options", false), "A profile with no key reads off")

    SaSettingsMigrations.apply(config, 10)
    assert_false(config.has_section_key("ui", "advanced_options"), "and no migration puts one there")
    assert_false(config.get_value("ui", "advanced_options", false), "so it still reads off afterwards")
    SaSettings.advanced_options = previous


## What the brush puts behind the advanced check, so the check has something to
## do and so a row that quietly acquires the flag is noticed.
##
## Exposure is the option that only means anything in an HDR document. The tip
## rows behind it are the Tip rows, and the line that decides which is
## everything past Shape and Ratio, because the top bar had 45 pixels
## spare at 1920 once the preset button went on it. So Tip, Shape, Ratio and
## Spacing are in front of the check and the rest are behind it.
##
## Spacing is in front of it on the same reading: it is a first-order control a
## painter reaches for, it has been on the settings resource since before the
## bar existed with no way to reach it, and a row now reaches it.
##
## The two sharpness rows are behind it by their own rule. Sharpness at anything above zero is a different kind of brush
## rather than a stronger one, which is the same judgement Exposure carries.
##
## Tip Image and Load Tip are behind the check because an image tip is a
## second kind of brush and neither row does anything to a procedural one.
##
## The three airbrush rows are behind the check because an airbrush is a
## second kind of brush rather than a setting on this one, and because two of
## the three do nothing until the first is on.
##
## The two tip mirrors are behind the check because there is
## already a Mirror H and a Mirror V on the top bar that do something else. A
## painter who has not met the difference is better served by not being shown
## two more of them, and one who has knows where they went.
##
## **The curve options are behind it too and come first**. The Tool
## Options docker draws a `CURVE_OPTION` as a button that opens the editor, and
## all of them are declared ahead of every row here because the editor's page
## order is the declaration order, with the Masking Brush page's switch among
## them, between Texture and Airbrush Rate, which is where that page goes.
## Unflagged they would sit above Size and Opacity in the docker, which is the
## same 45 pixels of judgement the Tip rows are behind the check for. A painter who
## has met the idea of a modulated parameter turns Advanced on and finds a door
## per option. The pages are never behind the check: the editor reads every spec.
func test_the_brush_marks_exposure_and_the_deep_tip_rows_advanced() -> void:
    var descriptor := _machine.get_descriptor(&"brush")
    assert_not_null(descriptor, "The brush is registered")
    var flagged: Array[String] = []
    for spec: SaOptionSpec in descriptor.options:
        if spec.advanced:
            flagged.append(String(spec.key))
    assert_eq(
        flagged,
        (
            [
                "size_option",
                "opacity_option",
                "flow_option",
                "spacing_option",
                "softness_option",
                "hardness_option",
                "rotation_option",
                "mirror_option",
                "ratio_option",
                "hue_option",
                "saturation_option",
                "value_option",
                "darken_option",
                "mix_option",
                "scatter_option",
                "texture_option",
                "masking_enabled",
                "rate_option",
                "sharpness_option",
                "smudge_pickup_option",
                "smudge_color_rate_option",
                "smudge_length_option",
                "masking_size_option",
                "masking_strength_option",
                "exposure",
                "tip_image_path",
                "tip_load",
                "tip_mode",
                "tip_lightness",
                "airbrush_enabled",
                "airbrush_rate",
                "airbrush_ignore_spacing",
                "sharpness",
                "sharpness_softness",
                "tip_mirror_horizontal",
                "tip_mirror_vertical",
                "tip_softness",
                "tip_falloff",
                "tip_spikes",
                "tip_density",
                "tip_randomness",
                "tip_antialias",
                "tip_auto_spacing",
                "tip_auto_spacing_coeff",
                "pattern_name",
                "texture_scale",
                "texture_offset_x",
                "texture_offset_y",
                "texture_random_per_stroke",
                "texture_random_offset_x",
                "texture_random_offset_y",
                "texture_invert",
                "texture_mode",
                "texture_brightness",
                "texture_contrast",
                "texture_neutral_from_pattern",
                "texture_neutral",
                "texture_cutoff_left",
                "texture_cutoff_right",
                "texture_cutoff_policy",
                "smudge_mode",
                "smudge_radius",
                # The smudge page's Move Height switch.
                "smudge_move_height",
                # The pickup's source, declared on the page the
                # row above names and behind Advanced with the rest of them.
                "smudge_sample_merged",
                "masking_size",
                "masking_spacing",
                "masking_tip_generator",
                "masking_tip_shape",
                "masking_tip_ratio",
                "masking_tip_angle",
                "masking_tip_image_path",
                "masking_tip_mirror_horizontal",
                "masking_tip_mirror_vertical",
                "masking_tip_softness",
                "masking_tip_falloff",
                "masking_tip_spikes",
                "masking_tip_density",
                "masking_tip_randomness",
                "masking_tip_antialias",
                "masking_tip_auto_spacing",
                "masking_tip_auto_spacing_coeff",
                "color_source",
                "gradient",
            ]
            as Array[String]
        ),
        (
            "The curve options with the mask's switch among them, Exposure, the image tip rows with its mode "
            + "and the lightness, the three airbrush rows, the two sharpness rows, the two tip mirrors, the "
            + "eight tip rows, the five Texture "
            + "rows, the three randomiser rows, the mode row, the three tone rows, the three cutoff rows, "
            + "the other sixteen Masking Brush rows, the colour source and the gradient last, in declaration order"
        )
    )
