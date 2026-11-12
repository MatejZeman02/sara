## Preferences > Display, driven the way a painter drives it.
##
## A control that looks live and is not is the bug here,
## so these press the page's own nodes rather than the settings behind them: a
## slider whose callback is right and whose value never reaches the canvas is
## the bug, not the fix.
extends "res://tests/test_framework.gd"

var _saved_enabled: bool
var _saved_stops: float
var _saved_rolloff: bool
var _saved_method: String
var _saved_levels: bool


func before_each() -> void:
    _saved_enabled = SaSettings.display_exposure_enabled
    _saved_stops = SaSettings.display_exposure_stops
    _saved_rolloff = SaSettings.tonemap_highlights
    _saved_method = SaSettings.shape_check_method
    _saved_levels = SaSettings.shape_check_levels
    SaSettings.display_exposure_enabled = false
    SaSettings.display_exposure_stops = 0.0


## Restores what this suite found rather than the defaults, so a run does not
## quietly reset a preference the person has set.
func after_each() -> void:
    SaSettings.display_exposure_stops = _saved_stops
    SaSettings.display_exposure_enabled = _saved_enabled
    SaSettings.tonemap_highlights = _saved_rolloff
    SaSettings.shape_check_method = _saved_method
    SaSettings.shape_check_levels = _saved_levels


func test_the_stops_slider_switches_the_exposure_on() -> void:
    var page := SaDisplayPage.new()
    var stops := _stops_slider(page)
    assert_true(stops != null, "The page has a Stops slider")

    _drag(stops, 2.0)
    assert_almost_eq(SaSettings.display_exposure_stops, 2.0, 1e-6, "A drag writes the stops")
    assert_true(SaSettings.display_exposure_enabled, "and switches the exposure on, or the drag shows nothing")
    assert_true(page._exposure_check.button_pressed, "with the switch above it following")

    _drag(stops, 0.0)
    assert_false(SaSettings.display_exposure_enabled, "Back at zero the exposure is off again")
    assert_false(page._exposure_check.button_pressed, "and so is the switch")
    page.free()


## The switch itself still stands on its own, so a person who wants the stops
## they set last time back has one click rather than a drag away and back.
func test_the_switch_still_works_by_itself() -> void:
    SaSettings.display_exposure_stops = 1.5
    SaSettings.display_exposure_enabled = false
    var page := SaDisplayPage.new()
    page._exposure_check.button_pressed = true
    assert_true(SaSettings.display_exposure_enabled, "The switch writes the setting")
    assert_almost_eq(SaSettings.display_exposure_stops, 1.5, 1e-6, "and leaves the stops where they were")
    page.free()


## A drag of *slider* to *value*.
##
## The signal rather than the property, because a Range outside a running frame
## takes a written value without emitting anything, so `slider.value = 2.0`
## proves only that Godot stores numbers. `value_changed` is what a real drag
## emits and what the page is connected to.
static func _drag(slider: HSlider, value: float) -> void:
    slider.set_value_no_signal(value)
    slider.value_changed.emit(value)


## The View transform row. A settings page is handed no registries, so a
## page built in a test carries the one row that needs none, and the modes are
## proved against the registry in test_view_transforms.gd and against the
## canvas in scenarios/display-page.json.
##
## The list is the ordinary view and the modes, and the roll-off is not one
## of its rows. It sat first, beside Normal View, so the page set one setting in
## two places.
func test_the_view_transform_list_carries_no_roll_off() -> void:
    var page := SaDisplayPage.new()
    var labels := page._view_option.choice_labels()
    assert_eq(labels[0], SaViewTransformRegistry.NORMAL_NAME, "The list opens on the ordinary view")
    assert_false(labels.has(String(SaDisplayPage.ROLLOFF_ID)), "and has no roll-off row")
    assert_false(labels.has("Tonemap Highlights"), "under either name")
    assert_eq(page._view_items, [SaDisplayPage.NO_MODE] as Array[StringName], "Its one plain row is no mode at all")
    assert_eq(page._view_option.selected_value(), 0, "and it opens on it")
    page.free()


## And picking a row of the list leaves the roll-off where it was, either way
## round, because the switch is the one control that writes it.
func test_picking_a_view_leaves_the_roll_off_alone() -> void:
    for before: bool in [false, true]:
        SaSettings.tonemap_highlights = before
        var page := SaDisplayPage.new()
        page._view_option.pick_row(0)
        assert_eq(SaSettings.tonemap_highlights, before, "Normal View leaves the roll-off %s" % ("on" if before else "off"))
        assert_eq(page._rolloff_check.button_pressed, before, "and the switch says so")
        page.free()


## The switch alone writes the setting, and the list does not move for it.
func test_the_switch_alone_writes_the_roll_off() -> void:
    SaSettings.tonemap_highlights = false
    var page := SaDisplayPage.new()
    assert_false(page._rolloff_check.button_pressed, "The switch opens off, with the setting")
    page._rolloff_check.button_pressed = true
    assert_true(SaSettings.tonemap_highlights, "Pressing it writes the setting")
    assert_eq(page._view_option.selected_value(), 0, "and the list stays on Normal View")
    page._rolloff_check.button_pressed = false
    assert_false(SaSettings.tonemap_highlights, "and pressing it again writes it back")
    page.free()


## The switch is a door onto the setting rather than a copy of it, so the View
## menu's toggle moving the setting moves the switch.
func test_the_switch_follows_the_view_menu() -> void:
    SaSettings.tonemap_highlights = false
    var page := SaDisplayPage.new()
    SaSettings.tonemap_highlights = true
    assert_true(page._rolloff_check.button_pressed, "The switch reads the roll-off back out of the setting")
    page.free()


## The second half. The Shape check rows set how the Shape Check view runs,
## and nothing drives them under another view, so the rows dim and give the
## keyboard up there, and the Method row's hint says which view it belongs to.
func test_shape_check_dims_under_normal_view() -> void:
    var page := SaDisplayPage.new()
    var method := page._shape_rows._method_row
    assert_eq(page._view_row.value, SaDisplayPage.NO_MODE, "The page is on Normal View")
    assert_false(page._shape_rows.live(), "and Shape check is dimmed there")
    assert_almost_eq(method.line.modulate.a, SaPage.DIMMED_ALPHA, 1e-3, "drawn faint")
    assert_true((method.control as BaseButton).disabled, "and not answering a painter")
    assert_true(method.explanation.contains("Shape Check view"), "Its hint names the view it shows under")
    assert_false(bool(page.view_transform_report()["shape_check_live"]), "and the dump reads it dimmed")

    # The registry is the application's, and a page built here has none, so
    # the mode is handed over the way `_sync_view_transform` hands it.
    page._view_row.value = SaShapeCheckRows.VIEW_ID
    page.page.apply_rules()
    assert_true(page._shape_rows.live(), "Under Shape Check the rows are live")
    page._view_row.value = SaDisplayPage.NO_MODE
    page.page.apply_rules()
    assert_false(page._shape_rows.live(), "and dimmed again once the view goes back")
    page.free()


## The section below the switch is un-dimmed. The rows under the
## switch fade while the operator they describe is not running, and the switch's
## own row does not, because it is what changes the state.
func test_the_rows_under_the_switch_say_whether_the_roll_off_is_running() -> void:
    SaSettings.tonemap_highlights = false
    var page := SaDisplayPage.new()
    var faded: Array = page._rolloff_rows_alpha()
    assert_false(faded.is_empty(), "The section has rows under its switch")
    for alpha: float in faded:
        assert_almost_eq(alpha, SaPage.DIMMED_ALPHA, 1e-3, "and each is dimmed while the roll-off is off")
    assert_almost_eq(
        (page._rolloff_rows.get_child(0) as Control).modulate.a, 1.0, 1e-6, "The switch's own row stays at full strength"
    )

    # **Disabled as well as dimmed.** A dimmed row that stayed editable would
    # leave "toggled on and possible to edit" saying nothing the first two
    # states did not, so rows are not editable before the switch is on.
    for live: bool in page._rolloff_rows_editable():
        assert_false(live, "and none of them answers a painter while it is off")
    assert_false(page._rolloff_check.disabled, "The switch itself stays live, being what turns it on")

    page._rolloff_check.button_pressed = true
    for alpha: float in page._rolloff_rows_alpha():
        assert_almost_eq(alpha, 1.0, 1e-6, "and every one is full strength once it is on")
    var live_rows: Array = page._rolloff_rows_editable()
    assert_false(live_rows.is_empty(), "The section still has rows under its switch")
    for live: bool in live_rows:
        assert_true(live, "and every one of them answers a painter once it is on")
    for node in page._rolloff_rows.find_children("*", "HSlider", true, false):
        assert_true((node as HSlider).editable, "which the sliders say for themselves")
    assert_false(page._rolloff_check.disabled, "and the switch is live in this state too")
    page.free()


## The Stops slider, found by its range, which is the exposure's own and no
## other row's on the page.
func _stops_slider(page: Control) -> HSlider:
    for node in page.find_children("*", "HSlider", true, false):
        var slider := node as HSlider
        if slider != null and is_equal_approx(slider.min_value, -SaSettings.MAX_EXPOSURE_STOPS):
            return slider
    return null


## Some explanation that grayscale is normal and coloured maps are
## HDR is helpful, with False Colour picked, and the sentence
## that says exactly that, once sat in a tooltip nobody had hovered. It is
## under the list now, and it is the registry's own sentence rather than a
## second wording of it, so the page and the View menu cannot drift.
func test_the_picked_row_says_what_it_does_under_the_list() -> void:
    var page := SaDisplayPage.new()

    var sentence := page._view_sentence
    assert_not_null(sentence, "The list has a sentence under it")
    assert_eq(sentence.text, page._view_option.tooltip_text, "and it is the one the collapsed control carries")

    var report := page.view_transform_report()
    assert_eq(String(report["view_sentence"]), sentence.text, "which the dump reads back")

    # Every row, because any of them can carry the bug.
    # What is asserted is that the label follows the
    # pick, not what it says: a page built in a test is handed no registries, so
    # the sentences themselves are empty here and
    # `scenarios/h2-false-colour-sentence.json` is where they are read.
    var labels := page._view_option.choice_labels()
    for i in labels.size():
        page._view_option.pick_row(i)
        page._sync_view_transform()
        assert_eq(page._view_sentence.text, page._sentence_for_row(i), "'%s' puts its own sentence under the list" % labels[i])
    page.free()


## The second note, "we need a second similar image right next to it that
## transform doesn't affect, for comparison". Two copies of one picture,
## the operator on one of them and none on the other, which is not something a
## screenshot of two coloured strips can be read for: the operator is the
## material and a shot has no material in it.
func test_the_gamut_picture_has_an_untouched_twin() -> void:
    var knee := SaSettings.tonemap_knee
    var desaturation := SaSettings.tonemap_desaturation
    var page := SaDisplayPage.new()
    # The picture is taken on entering the tree, so a page the search builds
    # off it to read its rows never bakes it.
    assert_null(page._gamut.texture, "Off the tree the page bakes no picture")
    # Under an autoload rather than the root, which a filtered run finds busy
    # setting up its children and refuses, leaving the page off the tree.
    EventBus.add_child(page)

    assert_not_null(page._gamut, "The operated picture is there")
    assert_not_null(page._gamut_plain, "and so is the plain one")
    assert_not_null(page._gamut.texture, "In the tree it draws the picture")
    assert_true(page._gamut.texture == page._gamut_plain.texture, "Both draw the same picture, or the pair compares nothing")
    assert_not_null(page._gamut.material, "The left one carries the operator")
    # The right one carries the same shader with the roll-off off,
    # rather than no material. Cleared, it drew the stored texels raw, and the
    # picture is baked three stops above white, so the display clipped it
    # channel by channel and the reference read as a paler, flatter picture.
    assert_not_null(page._gamut_plain.material, "and the right one carries the same shader with the operator off")
    assert_true(page._gamut.get_parent() == page._gamut_plain.get_parent(), "and they sit in one row, side by side")

    var pair: Dictionary = page.view_transform_report()["gamut_pair"]
    assert_eq(int(pair["count"]), 2, "The dump counts the pair")
    assert_true(bool(pair["operated"]), "says which of them is operated on")
    assert_false(bool(pair["plain_operated"]), "and which is not")
    assert_true(bool(pair["same_texture"]), "and that the two are the same picture")
    assert_true(bool(pair["same_shader"]), "and that one shader draws both")

    # What the two differ by, which is the whole of it. The reference half is
    # the operator off and the exposure that undoes the bake, and nothing more:
    # any third difference is a second picture again.
    var operated: Dictionary = pair["operated_uniforms"]
    var plain: Dictionary = pair["plain_uniforms"]
    var differing: Array = []
    for name: String in operated.keys() + plain.keys():
        if operated.get(name) != plain.get(name) and not differing.has(name):
            differing.append(name)
    differing.sort()
    assert_eq(differing, ["display_exposure", "tonemap_enabled"] as Array, "the pair differs by %s" % [differing])
    assert_almost_eq(
        float(plain["display_exposure"]), 1.0 / SaGamutPreview.STORED_SCALE, 1e-6, "the reference half does not undo the bake"
    )

    # The sliders reach both and move only the operated one, which is what makes
    # the pair a comparison rather than two pictures.
    SaSettings.tonemap_knee = 0.37
    SaSettings.tonemap_desaturation = 0.81
    page._redraw_curve()
    var after: Dictionary = page.view_transform_report()["gamut_pair"]
    assert_almost_eq(float(after["plain_uniforms"]["knee"]), 0.37, 1e-6, "A drag leaves the reference half a knee behind")
    assert_almost_eq(float(after["plain_uniforms"]["desaturation"]), 0.81, 1e-6, "and a desaturation behind")
    assert_false(bool(after["plain_uniforms"]["tonemap_enabled"]), "and it still reads neither")
    page.free()
    SaSettings.tonemap_knee = knee
    SaSettings.tonemap_desaturation = desaturation


## The Shape check section's five rows: each dims under any
## view but the Shape Check, Reach under any method but Masses, Blocks across
## under any but Blocks, and Levels while the posterise is off.
func test_the_display_page_carries_the_options_and_dims_each_by_what_it_belongs_to() -> void:
    var page := SaDisplayPage.new()
    var keys: Array[StringName] = [
        &"shape_check_method", &"shape_check_reach", &"shape_check_across", &"shape_check_levels", &"shape_check_level_count"
    ]
    for key: StringName in keys:
        assert_not_null(page.page.row(key), "The page has the %s row" % key)
    var expected := {
        SaSettings.SHAPE_BLOCKS: [true, false, true],
        SaSettings.SHAPE_MASSES: [false, true, true],
        SaSettings.SHAPE_NONE: [false, false, true],
    }
    for method: String in expected:
        SaSettings.shape_check_method = method
        SaSettings.shape_check_levels = true
        _on_the_shape_check(page)
        var want: Array = expected[method]
        assert_eq(_live(page, &"shape_check_across"), want[0], "%s: Blocks across is %s" % [method, _word(want[0])])
        assert_eq(_live(page, &"shape_check_reach"), want[1], "%s: Reach is %s" % [method, _word(want[1])])
        assert_eq(_live(page, &"shape_check_level_count"), want[2], "%s: Levels is live with the posterise on" % method)
    SaSettings.shape_check_levels = false
    _on_the_shape_check(page)
    assert_false(_live(page, &"shape_check_level_count"), "and dimmed with it off")
    page._view_row.value = SaDisplayPage.NO_MODE
    page.page.apply_rules()
    for key: StringName in keys:
        assert_false(_live(page, key), "Under Normal View the %s row is dimmed" % key)
    page.free()


## The grey methods' rows beside the Shape check's. Reach is live under
## every method that smooths inside the masses, the posterise and its count under
## every method but Notan, and Notan's count of values under Notan alone, with
## the one threshold of two values or the dark and the light one of three.
func test_the_grey_methods_carry_their_options_and_dim_each_by_what_it_belongs_to() -> void:
    var page := SaDisplayPage.new()
    var notan: Array[StringName] = [
        &"shape_check_notan_values", &"shape_check_notan_threshold", &"shape_check_notan_dark", &"shape_check_notan_light"
    ]
    for key: StringName in notan:
        assert_not_null(page.page.row(key), "The page has the %s row" % key)
    var kept_values := SaSettings.shape_check_notan_values
    # Reach, Blocks across, the posterise, its count, Notan's values.
    var expected := {
        SaSettings.SHAPE_BLOCKS: [false, true, true, true, false],
        SaSettings.SHAPE_MASSES: [true, false, true, true, false],
        SaSettings.SHAPE_NONE: [false, false, true, true, false],
        SaSettings.SHAPE_GREY_MASSES: [true, false, true, true, false],
        SaSettings.SHAPE_NOTAN: [true, false, false, false, true],
    }
    var keys: Array[StringName] = [
        &"shape_check_reach",
        &"shape_check_across",
        &"shape_check_levels",
        &"shape_check_level_count",
        &"shape_check_notan_values"
    ]
    for method: String in expected:
        SaSettings.shape_check_method = method
        SaSettings.shape_check_levels = true
        _on_the_shape_check(page)
        var want: Array = expected[method]
        for i in keys.size():
            assert_eq(_live(page, keys[i]), want[i], "%s: %s is %s" % [method, keys[i], _word(want[i])])
    SaSettings.shape_check_method = SaSettings.SHAPE_NOTAN
    for values: int in [2, 3]:
        SaSettings.shape_check_notan_values = values
        _on_the_shape_check(page)
        assert_eq(_live(page, &"shape_check_notan_threshold"), values == 2, "%d values: the one threshold" % values)
        assert_eq(_live(page, &"shape_check_notan_dark"), values == 3, "%d values: the dark threshold" % values)
        assert_eq(_live(page, &"shape_check_notan_light"), values == 3, "%d values: the light threshold" % values)
    page._view_row.value = SaDisplayPage.NO_MODE
    page.page.apply_rules()
    for key: StringName in notan:
        assert_false(_live(page, key), "Under Normal View the %s row is dimmed" % key)
    page.free()
    SaSettings.shape_check_notan_values = kept_values


## Puts *page* on the Shape Check and applies its rules. A page built here has
## no registry, and a view setting moving syncs the page back to the ordinary
## view, so the mode is handed over after the settings move, the way
## `_sync_view_transform` hands it.
static func _on_the_shape_check(page: SaDisplayPage) -> void:
    page._view_row.value = SaShapeCheckRows.VIEW_ID
    page.page.apply_rules()


static func _live(page: SaDisplayPage, key: StringName) -> bool:
    var row := page.page.row(key)
    return is_equal_approx(row.line.modulate.a, 1.0)


static func _word(live: bool) -> String:
    return "live" if live else "dimmed"
