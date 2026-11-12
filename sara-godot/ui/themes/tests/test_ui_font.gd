## The interface font ships, switches at once, and the slider text fits,
## and the dockers grow with it.
##
## Four families under ui/themes/fonts/, each with its licence beside it,
## Inter by default, a Workspace row to switch, the sliders in the Bold face
## at a size of their own and never narrower than their text, and the second
## row of the bar thinner than it was.
##
## `@tool` because the probe docker below extends `DockerWindow`, which is a
## tool script, the reason `test_scale_change_keeps_the_column_floor.gd` gives.
@tool
extends "res://tests/test_framework.gd"

## The second row's height before it was made a fresh profile's
## and thinner, its tallest control's 33 with three pixels either
## side.
const SECOND_ROW_BEFORE := 39

## The screen the probe docker sits in, a size this suite chose rather than
## whatever the run's window is.
const PROBE_HOST := Vector2i(900, 640)

## The probe at its rounds and the statics it changes, kept to be put back.
var _probe_host: SubViewport = null
var _probe: ProbeDocker = null
var _kept_font_scale: float = 1.0
var _kept_override: float = -1.0
var _kept_theme: Theme = null

## How much the font change cut before the docker grew, which the last
## `_change_font` read once the new size was laid out and before its first round.
var _cut_before_growth: int = 0


## The two rows the 130 % sweep found cut in Layers, the layer's own row and the
## footer under the stack, and a name too long for any docker.
##
## Built through `_init_docker` so the floors are the real ones, and never
## readied, so it listens to no bus and the suite drives every round itself.
## The width is the footer's at 100 % with a little to spare, so its blend mode
## reads whole there and is cut at 130 %, which is the sweep's finding.
class ProbeDocker:
    extends DockerWindow

    const WIDTH := 320
    const LAYER_NAME := "Background"
    const BLEND_NAME := "Normal (Oklab)"
    const LONG_NAME := "A layer named after every stroke that was ever painted on it, in the order the hand painted them"

    func _init() -> void:
        _init_docker("FontProbe", "Font probe", Vector2i(WIDTH, 300), Vector2i(120, 80))
        var column := VBoxContainer.new()
        column.set_anchors_preset(Control.PRESET_FULL_RECT)
        _control_node.add_child(column)
        drag_handle = PanelContainer.new()
        column.add_child(drag_handle)
        var layer := HBoxContainer.new()
        column.add_child(layer)
        layer.add_child(_cut_label(LAYER_NAME))
        var eye := Control.new()
        eye.custom_minimum_size = Vector2(28, 28)
        layer.add_child(eye)
        column.add_child(_cut_label(LONG_NAME))
        var footer := HBoxContainer.new()
        column.add_child(footer)
        footer.add_child(_plain_label("Layer"))
        # A button that cuts its name, the way `SaDropdownButton` under the
        # Layers blend mode list does.
        var blend := Button.new()
        blend.text = BLEND_NAME
        blend.clip_text = true
        blend.text_overrun_behavior = SaTheme.TEXT_CUT
        blend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        footer.add_child(blend)
        footer.add_child(_plain_label("100 %"))

    func _cut_label(text: String) -> Label:
        var label := _plain_label(text)
        label.text_overrun_behavior = SaTheme.TEXT_CUT
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        return label

    func _plain_label(text: String) -> Label:
        var label := Label.new()
        label.text = text
        return label


func test_every_shipped_family_has_both_faces_and_its_licence() -> void:
    var shipped := 0
    for id: String in SaFonts.FAMILIES:
        var family: Dictionary = SaFonts.FAMILIES[id]
        if String(family["regular"]).is_empty():
            continue
        shipped += 1
        for key: String in ["regular", "bold", "licence"]:
            assert_true(FileAccess.file_exists(family[key]), "%s ships its %s: %s" % [id, key, family[key]])
        assert_not_null(SaFonts.regular(id), "%s's Regular loads" % id)
        assert_not_null(SaFonts.bold(id), "and its Bold")
        var licence := FileAccess.get_file_as_string(family["licence"])
        assert_true(licence.contains("SIL Open Font License"), "%s's licence is the OFL" % id)
    assert_eq(shipped, 4, "Inter, IBM Plex Sans, Source Sans 3 and Atkinson Hyperlegible")
    assert_eq(SaFonts.available().size(), 5, "and the engine's Open Sans is the fifth choice")
    assert_eq(SaFonts.DEFAULT, "inter", "Inter by default")
    assert_eq(SaFonts.licence_lines().size(), 4, "The About dialog names the four")
    assert_true(SaAboutDialog.report_text().contains("Inter"), "and does")


## SaSettingsValues owns FONT_IDS, and SaFonts.FAMILIES is what a suite
## checks it against, not the other way round, because a family carries files
## a values class has no business holding.
func test_the_values_font_ids_are_exactly_the_families_table() -> void:
    var families: Array[String] = []
    for id: String in SaFonts.FAMILIES:
        families.append(id)
    assert_eq(families, SaSettingsValues.FONT_IDS, "the same ids in the same order")
    assert_eq(SaSettingsValues.DEFAULT_FONT, SaFonts.DEFAULT, "and the same default")


func test_the_engine_font_is_a_choice_with_a_bold_of_its_own() -> void:
    assert_true(SaFonts.regular("noto-sans") == ThemeDB.fallback_font, "Open Sans is the engine's fallback")
    assert_true(SaFonts.bold("noto-sans") is FontVariation, "emboldened through a variation")
    assert_eq(SaFonts.resolve("comic-sans"), SaFonts.DEFAULT, "and an id nobody has is the default")


func test_a_switch_reaches_the_shared_theme_and_the_bus() -> void:
    var was := SaFonts.current
    var heard: Array = []
    var listener := func(id: String) -> void: heard.append(id)
    EventBus.ui_font_changed.connect(listener)
    SaFonts.use("atkinson-hyperlegible")
    assert_eq(SaFonts.current, "atkinson-hyperlegible", "The switch is remembered")
    assert_eq(heard, ["atkinson-hyperlegible"], "and announced")
    var theme := SaUI.shared_theme
    if theme != null:
        assert_true(theme.default_font == SaFonts.regular("atkinson-hyperlegible"), "and the shared theme draws in it")
    EventBus.ui_font_changed.disconnect(listener)
    SaFonts.use(was)


## In the tree, because the slider writes its text on ready and a control
## outside a tree never is.
func test_a_slider_is_never_narrower_than_its_text() -> void:
    var slider := FactorSlider.new()
    slider.prefix = "Smoothing: "
    slider.suffix = "%"
    slider.decimal_places = 0
    slider.min_value = 0.0
    slider.max_value = 100.0
    slider.value = 50.0
    EventBus.add_child(slider)
    assert_eq(slider._label.text, "Smoothing: 50 %", "The prefix is not cut at ten characters any more")
    var needed := slider.text_width() + float(DockerUtils.px(FactorSlider.TEXT_PADDING))
    assert_true(slider.text_width() > 0.0, "The text measures")
    slider.custom_minimum_size.x = 10.0
    assert_true(slider.get_combined_minimum_size().x >= needed, "and the box cannot be narrowed below it")
    assert_true(slider._label.label_settings.font == SaFonts.bold(), "drawn in the Bold face")
    assert_eq(slider._label.label_settings.font_size, SaUI.get_font_size(), "at the theme font's size")
    EventBus.remove_child(slider)
    slider.free()


func test_the_keep_checkbox_says_what_it_keeps() -> void:
    var bar := ToolOptionsBar.new()
    bar._build_ui_by_code()
    assert_not_null(bar.keep_blend_chk, "The bar builds its Keep checkbox")
    assert_eq(bar.keep_blend_chk.text, "Keep Blend Mode", "and it says what it keeps")
    bar.free()


## Two slots rather than one changed, because a control outside a tree
## keeps its first minimum size: update_minimum_size() is a no-op there.
##
## The second row was taller than the first while the first held the same
## buttons. The first holds the menus alone, and the second is as
## tall as its tallest control asks for in the running app, which a scenario
## records and `test_the_bars_second_row_is_on_and_holds_every_tool_option.gd`
## holds the row to.
func test_the_second_row_is_thinner_than_it_was() -> void:
    var first := SaRowSlot.new()
    assert_almost_eq(first.get_combined_minimum_size().y, 0.0, 0.01, "An empty slot asks for nothing")
    var second := SaRowSlot.new()
    second.min_height = SaRowSlot.SECOND_ROW_HEIGHT
    assert_true(SaRowSlot.SECOND_ROW_HEIGHT < SECOND_ROW_BEFORE, "The second row's height is less than the 39 it was")
    assert_almost_eq(
        second.get_combined_minimum_size().y, float(SaUI.px(SaRowSlot.SECOND_ROW_HEIGHT)), 0.01, "and the slot asks for it"
    )
    first.free()
    second.free()


## The Font size preference is a multiplier on
## BASE_FONT_SIZE and not on the scale, which is what lets it exist beside a UI
## scale that hard rule 7 says only SaUI.apply_to_window may write. What moves
## with it is the text and the dockers that show the text, through
## `SaDockerFontGrowth` and the tests below. A margin, an icon and the scale
## every window's geometry is measured in do not.
func test_the_font_size_preference_moves_text_and_dockers_and_not_the_scale() -> void:
    var saved := SaUI.user_font_scale
    var saved_override := SaUI.os_scale_override
    SaUI.os_scale_override = 1.0

    SaUI.user_font_scale = 1.0
    assert_eq(SaUI.get_font_size(), SaUI.BASE_FONT_SIZE, "At 100% the base size is what it always was")

    SaUI.user_font_scale = 1.4
    assert_eq(SaUI.get_font_size(), 28, "140% of 20 points is 28")
    assert_almost_eq(SaUI.scale(), 1.0, 0.0001, "and the scale authority has not moved")
    assert_eq(SaUI.px(SaUI.BASE_SEPARATOR), SaUI.BASE_SEPARATOR, "nor has a margin")
    assert_eq(SaUI.to_physical(100), 100, "nor a window's geometry")

    # The clamp is the settings setter's since f16, the one writer of the cache.
    var kept := SaSettings.ui_font_scale
    SaSettings.ui_font_scale = 9.0
    assert_almost_eq(SaUI.user_font_scale, SaUI.MAX_FONT_SCALE, 0.0001, "The ceiling holds")
    SaSettings.ui_font_scale = 0.01
    assert_almost_eq(SaUI.user_font_scale, SaUI.MIN_FONT_SCALE, 0.0001, "and the floor")
    SaSettings.ui_font_scale = kept

    SaUI.user_font_scale = saved
    SaUI.os_scale_override = saved_override


## The shared theme is what every control without an override of its own reads,
## so a size that never reached it would move only half the interface.
func test_the_font_size_reaches_the_shared_theme() -> void:
    var saved := SaUI.user_font_scale
    # The gate runs res://tests/run_all.tscn rather than the app, so nothing has
    # built the theme yet. Built here and put back, because it is a static.
    var was_shared := SaUI.shared_theme
    SaUI.init_global_theme(null)
    var theme := SaUI.shared_theme
    assert_not_null(theme, "init_global_theme leaves a theme behind even with no tree to hang it on")

    SaUI.user_font_scale = 1.5
    SaUI.refresh_font_sizes()
    assert_eq(theme.default_font_size, SaUI.get_font_size(), "The default follows the preference")
    assert_eq(theme.get_font_size("font_size", "Label"), SaUI.get_font_size(), "and so does every named class")

    SaUI.user_font_scale = saved
    SaUI.refresh_font_sizes()
    assert_eq(theme.default_font_size, SaUI.get_font_size(), "and it goes back")
    SaUI.shared_theme = was_shared


# --- The dockers grow with their text ------------------------------------------


## The sweep's finding and its answer: at 130 % the footer cut its blend mode,
## and once the docker has grown no name the font cut is still cut and the
## column is no wider than the docker.
func test_at_130_no_name_the_font_cut_is_still_cut() -> void:
    var probe := _open_probe(Vector2i(100, 40))
    var cut_at_100 := _cut_texts(probe)
    assert_false(cut_at_100.has(ProbeDocker.BLEND_NAME), "At 100 %% the blend mode reads whole: %s" % [cut_at_100])
    assert_true(cut_at_100.has(ProbeDocker.LONG_NAME), "and the long name is cut already")

    var counted := _change_font(1.3)
    assert_true(counted.has(ProbeDocker.BLEND_NAME), "The blend mode was read whole at the old size")
    assert_false(counted.has(ProbeDocker.LONG_NAME), "and the long name was not")
    assert_true(_cut_before_growth > 0, "The font cut a name the docker then had to grow for")
    assert_eq(SaDockerFontGrowth.widest_cut(probe, counted), 0, "No name the font cut is cut now")
    assert_false(_cut_texts(probe).has(ProbeDocker.BLEND_NAME), "the blend mode among them")
    assert_true(probe.size.x > ProbeDocker.WIDTH, "The docker grew to show it, to %d" % probe.size.x)
    assert_true(
        DockerWindow.column_min_width(probe) <= probe.size.x,
        "and its column, %d, is no wider than it" % DockerWindow.column_min_width(probe)
    )
    assert_true(probe.min_size.x >= probe.size.x, "The width is the docker's floor, which the layout store's fit keeps")
    _close_probe()


## A docker against the right edge of its host grows into the host, not past it.
func test_a_docker_at_the_edge_grows_inward() -> void:
    var probe := _open_probe(Vector2i(PROBE_HOST.x - ProbeDocker.WIDTH, 40))
    _change_font(1.3)
    assert_true(probe.size.x > ProbeDocker.WIDTH, "The docker grew")
    assert_true(
        probe.position.x + probe.size.x <= PROBE_HOST.x,
        "and its right edge, %d, stays inside the host" % (probe.position.x + probe.size.x)
    )
    assert_true(probe.position.y + probe.size.y <= PROBE_HOST.y, "and so does its bottom")
    _close_probe()


## 100 %, 130 % and back is the same docker, where it was and as large.
func test_back_at_100_the_docker_is_the_one_it_was() -> void:
    var probe := _open_probe(Vector2i(PROBE_HOST.x - ProbeDocker.WIDTH, 40))
    var was := Rect2i(probe.position, probe.size)
    _change_font(1.3)
    assert_true(Rect2i(probe.position, probe.size) != was, "130 % moved the docker")
    _change_font(1.0)
    assert_eq(Rect2i(probe.position, probe.size), was, "and 100 % put it back")
    assert_true(probe.min_size.x <= was.size.x, "and no floor the larger size raised holds it wider")
    _close_probe()


## What else widened the docker while the change laid out is given back with
## it. The column's own floor and the layout store's fit do, and Brush Presets
## kept 9 such pixels back at 100 % once the painter's grip had made the layout
## theirs and the store stopped fitting it.
func test_what_else_widened_the_docker_in_the_change_goes_back_too() -> void:
    var probe := _open_probe(Vector2i(100, 40))
    var was := Rect2i(probe.position, probe.size)
    _change_font(1.3, 9)
    _change_font(1.0)
    assert_eq(Rect2i(probe.position, probe.size), was, "100 % puts the docker back where it was")
    _close_probe()


## A docker the painter made wider than the font needs is theirs: a larger font
## leaves it as it is and a smaller one does not take it back.
func test_a_docker_the_painter_widened_is_never_shrunk() -> void:
    var probe := _open_probe(Vector2i(100, 40))
    _change_font(1.3)
    var dragged := probe.size.x + 120
    probe.size = Vector2i(dragged, probe.size.y)
    _settle(probe)
    _change_font(1.0)
    assert_eq(probe.size.x, dragged, "100 % keeps the width the painter dragged")
    _change_font(1.3)
    assert_eq(probe.size.x, dragged, "and 130 % again has nothing to add to it")
    _close_probe()


## The Workspace page says what the slider moves now.
func test_the_font_size_hint_says_the_dockers_grow() -> void:
    var page := SaWorkspacePage.new()
    var row := page.page.row(&"font_size")
    assert_not_null(row, "The page declares the Font size row")
    assert_true(row.explanation.contains("the dockers grow with it"), "and it says so, '%s'" % row.explanation)
    assert_false(row.explanation.contains("only"), "rather than that only the text moves")
    page.free()


## The probe in a screen of its own at 100 %, laid out, at *at* in that screen.
func _open_probe(at: Vector2i) -> ProbeDocker:
    _kept_font_scale = SaUI.user_font_scale
    _kept_override = SaUI.os_scale_override
    _kept_theme = SaUI.shared_theme
    SaUI.os_scale_override = 1.0
    SaUI.user_font_scale = 1.0
    SaUI.init_global_theme(null)
    _probe_host = SubViewport.new()
    _probe_host.size = PROBE_HOST
    _probe_host.gui_embed_subwindows = true
    EventBus.add_child(_probe_host)
    _probe = ProbeDocker.new()
    _probe.theme = SaUI.shared_theme
    _probe.position = at
    _probe.visible = true
    _probe_host.add_child(_probe)
    SaUI.apply_ui_theme(_probe)
    _settle(_probe)
    return _probe


func _close_probe() -> void:
    if is_instance_valid(_probe_host):
        _probe_host.free()
    _probe_host = null
    _probe = null
    SaUI.user_font_scale = _kept_font_scale
    SaUI.refresh_font_sizes()
    SaUI.shared_theme = _kept_theme
    SaUI.os_scale_override = _kept_override


## What `SaDockerFontGrowth.follow` does over the frames after a change, with
## the frames drawn by hand: the theme pass `DockerWindow._on_ui_font_scale_changed`
## runs first, which writes every control's size at once where the shared theme
## reaches a control only on a deferred call, then `begin`, the rounds, each on
## a settled layout, and `end`. Answers the names `begin` counted.
func _change_font(font_scale: float, widen_meanwhile: int = 0) -> Dictionary:
    SaUI.user_font_scale = font_scale
    SaUI.refresh_font_sizes()
    SaUI.apply_ui_theme(_probe)
    var counted := SaDockerFontGrowth.begin(_probe)
    _settle(_probe)
    _cut_before_growth = SaDockerFontGrowth.widest_cut(_probe, counted)
    var progress: Dictionary = {}
    for _round in SaDockerFontGrowth.ROUNDS:
        if not SaDockerFontGrowth.step(_probe, counted, progress):
            break
        _settle(_probe)
    if widen_meanwhile > 0:
        _probe.size = _probe.size + Vector2i(widen_meanwhile, 0)
        _settle(_probe)
    SaDockerFontGrowth.end(_probe)
    return counted


func _cut_texts(window: Window) -> Array[String]:
    var out: Array[String] = []
    for word: Dictionary in SaDockerFontGrowth.cut_words(window):
        out.append(String(word["text"]))
    return out


## Lays *window* out the way a drawn frame would, the dialog sweep's own walk:
## every container sorted outside in, every control asked for its minimum again,
## twice, and a pixel on the window and back so an anchored control takes its
## new size.
func _settle(window: Window) -> void:
    for _pass in range(2):
        _sort_children(window)
        _ask_again(window)
    var kept := window.size
    window.size = kept + Vector2i.ONE
    window.size = kept
    _sort_children(window)


func _sort_children(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)


func _ask_again(node: Node) -> void:
    for child: Node in node.get_children():
        _ask_again(child)
        if child is Control:
            (child as Control).update_minimum_size()
