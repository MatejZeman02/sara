## The brush editor window: the pages it builds, the switch rule on its list,
## Save and Save As, Reset, and the dirty indicator.
##
## The window is never added to the tree here. A `Window` in the tree maps a real
## OS window and the run blocks until the watchdog fires, which is the same
## reason `test_new_document_white_point.gd` builds its dialog detached.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The window builds a `SaCurveOptionControl`, which builds an `SaCurveEditor`,
## and the plain pages build the same controls the Tool Options docker does.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_brush_editor")

var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    ScratchFolder.clear(scratch_dir)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


func _brush() -> ToolState:
    return _machine.get_tool("brush")


func _specs() -> Array[SaOptionSpec]:
    var out: Array[SaOptionSpec] = []
    out.assign(_machine.get_descriptor(&"brush").options)
    return out


## A window bound to the brush, with the store pointed at the scratch directory.
func _window(loaded: String = "") -> SaBrushEditorWindow:
    var window := SaBrushEditorWindow.new()
    window.bind_tool(_brush(), _specs(), _store(), loaded)
    return window


# --- The geometry the spec names ----------------------------------------------


func test_the_window_is_the_size_the_spec_draws() -> void:
    var window := SaBrushEditorWindow.new()
    # 1100 by 700, so the Brush Tip page shows its curve.
    assert_eq(window.logical_size, Vector2i(1100, 700), "1100 by 700 logical")
    assert_eq(window.logical_min_size, Vector2i(640, 420), "and no smaller than 640 by 420")
    # Not exclusive, which is the whole reason an editor is worth having open:
    # an exclusive window blocks the canvas it is meant to be watched against.
    assert_false(window.exclusive, "and it does not block the window under it")
    assert_false(window.visible, "A window built and not opened is not on screen")
    window.free()


# --- The pages, and the rule on their rows ------------------------------------


## Every option the brush declares reaches a page, in the order the brush sets:
## the tip first, the dashboard next, then the numbers in
## the order a painter reaches for them, and after those the pages
## not sorted, in the order the brush declared them.
##
## The brush declares its pages in this order and the editor takes a page where
## its first row is, so the list below is the brush's declaration read back
## and no module's titles are held in the skeleton.
func test_the_brush_declares_its_pages_in_the_decided_order() -> void:
    var window := _window()
    var titles: Array = []
    for i in window.page_list.page_count():
        titles.append(window.page_list.title_at(i))
    assert_eq(
        titles,
        [
            "Brush Tip",
            "General",
            "Size",
            "Opacity",
            "Flow",
            "Spacing Dynamics",
            "Softness",
            "Hardness",
            "Rotation",
            "Mirror",
            "Ratio",
            "Colour Dynamics",
            "Scatter",
            "Texture",
            "Masking Brush",
            "Airbrush Rate",
            "Sharpness",
            "Smudge Pickup",
            "Colour Rate",
            "Smear Length",
            "Mask Size",
            "Mask Opacity",
        ],
        "The sixteen pages in the sorted order, then the six left unsorted"
    )
    var rows: Array = window.page_list.row_report()
    assert_eq(rows.size(), window.page_list.page_count(), "The report has a row per page")
    assert_false(bool(rows[0]["switch"]), "Brush Tip is plain, so it has no switch")
    assert_false(bool(rows[1]["switch"]), "and General is plain too")
    assert_true(bool(rows[2]["switch"]), "while Size is a curve option page and has one")
    window.free()


## The fallback the editor keeps for a tool that names no page, which is what
## the brush relied on and what any third-party tool relies on.
func test_a_spec_naming_no_page_lands_on_the_default() -> void:
    var plain := SaOptionSpec.make_float(&"radius", "Size", 0.001, 0.2, 0.001)
    var pages: Array = SaBrushEditorPages.pages_from([plain])
    assert_eq(pages.size(), 1, "One spec, one page")
    assert_eq(String(pages[0]["title"]), SaBrushEditorPages.DEFAULT_PAGE, "and it is General")
    assert_null(pages[0]["curve"], "with no curve behind it")


## The rule the list exists for, on specs built here.
func test_a_curve_option_page_gets_a_switch_and_a_plain_page_does_not() -> void:
    var settings: Resource = _brush().settings
    var option := SaCurveOption.create_default()
    option.enabled = false
    settings.set_meta("test_curve", option)

    var curve_spec := SaOptionSpec.make(&"test_curve", "Size", SaOptionSpec.Kind.CURVE_OPTION)
    curve_spec.property = ^"metadata/test_curve"
    curve_spec.page = "Size"
    var plain := SaOptionSpec.make_float(&"radius", "Size", 0.001, 0.2, 0.001)
    plain.page = "Brush Tip"

    var window := SaBrushEditorWindow.new()
    var specs: Array[SaOptionSpec] = [curve_spec, plain]
    window.bind_tool(_brush(), specs, _store())
    var rows: Array = window.page_list.row_report()
    # By title rather than by index. This suite's subject is the switch, and
    # where each page lands is the order test's above.
    var by_title: Dictionary = {}
    for row: Dictionary in rows:
        by_title[String(row["title"])] = row
    assert_eq(rows.size(), 2, "Two specs, two pages")
    assert_true(by_title.has("Size") and by_title.has("Brush Tip"), "one page per declared title")
    assert_true(bool(by_title["Size"]["switch"]), "The curve option page has a switch")
    assert_false(bool(by_title["Size"]["on"]), "reading what the option holds")
    assert_false(bool(by_title["Brush Tip"]["switch"]), "and the plain page has none")
    window.free()


## A page lands where its first row is declared, whichever kind that row is
## A plain row naming a page ahead of the curve option the page
## is named after puts the page there, and the option joins it as its switch,
## which is the case a pass over curve pages first would order the other way
## round.
func test_a_page_lands_where_its_first_row_is_declared() -> void:
    var early := SaOptionSpec.make_float(&"radius", "Size", 0.001, 0.2, 0.001)
    early.page = "Zeta"
    var curve := SaOptionSpec.make(&"test_curve", "Alpha", SaOptionSpec.Kind.CURVE_OPTION)
    var joins := SaOptionSpec.make_float(&"opacity", "Opacity", 0.0, 1.0, 0.01)
    joins.page = "Alpha"
    var plain := SaOptionSpec.make_float(&"flow", "Flow", 0.0, 1.0, 0.01)
    var pages := SaBrushEditorPages.pages_from([early, joins, curve, plain])
    var titles: Array = []
    for page: Dictionary in pages:
        titles.append(String(page["title"]))
    assert_eq(titles, ["Zeta", "Alpha", SaBrushEditorPages.DEFAULT_PAGE], "In the order each page's first row came")
    assert_eq(pages[1]["curve"], curve, "and the option is the page's switch though a row came first")
    assert_eq(pages[1]["specs"], [joins, curve], "with the page's rows in declaration order")


## Both kinds of row are the same height and keep the same slot at their end,
## so a title ends where it ends whether or not its page has a dot to show.
func test_the_two_kinds_of_row_are_the_same_height() -> void:
    var list := SaBrushEditorPageList.new()
    list.build([{"title": "Size", "dynamic": true, "switch": true, "on": true}, {"title": "General"}])
    # Through `_rows` rather than `get_child(0)`, because the Brush
    # Presets fold sits above the rows and the list's first two children are its
    # header and its box. Reading another object's private is what the privates
    # rule allows, and the array is the list's own order.
    var first := list._rows[0]["row"] as Control
    var second := list._rows[1]["row"] as Control
    assert_eq(first.custom_minimum_size.y, second.custom_minimum_size.y, "The rows are the same height")
    assert_not_null(first.get_node_or_null("DotSlot/OnDot"), "The curve option row has a dot")
    assert_null(second.get_node_or_null("DotSlot/OnDot"), "and the plain row has none rather than a hidden one")
    assert_not_null(second.get_node_or_null("DotSlot"), "It keeps the dot's slot as empty space instead")
    assert_null(first.get_node_or_null("Check"), "and no row carries a checkbox a press could tick")
    list.free()


## The page's switch writes the option's own `enabled`.
func test_the_switch_writes_the_option_s_enabled() -> void:
    var settings: Resource = _brush().settings
    var option := SaCurveOption.create_default()
    option.enabled = false
    settings.set_meta("test_curve", option)
    var spec := SaOptionSpec.make(&"test_curve", "Size", SaOptionSpec.Kind.CURVE_OPTION)
    spec.property = ^"metadata/test_curve"
    spec.page = "Size"

    var window := SaBrushEditorWindow.new()
    var specs: Array[SaOptionSpec] = [spec]
    window.bind_tool(_brush(), specs, _store())
    window.set_page_enabled(0, true)
    assert_true(option.enabled, "Switching the page on switches the option on")
    window.set_page_enabled(0, false)
    assert_false(option.enabled, "and switching it off switches it off")
    window.free()


## Clicking a row opens that page, and the list says which is open.
func test_a_click_switches_the_page() -> void:
    var plain_a := SaOptionSpec.make_float(&"radius", "Size", 0.001, 0.2, 0.001)
    plain_a.page = "Brush Tip"
    var plain_b := SaOptionSpec.make_float(&"opacity", "Opacity", 0.0, 1.0, 0.01)
    plain_b.page = "General"
    var window := SaBrushEditorWindow.new()
    var specs: Array[SaOptionSpec] = [plain_a, plain_b]
    window.bind_tool(_brush(), specs, _store())
    assert_eq(window.page_list.selected, 0, "The first page opens with the window")
    window.show_page(1)
    assert_eq(window.page_list.selected, 1, "and a click moves it")
    assert_eq(String(window.editor_report()["page"]), "General", "which the dump reports by title")
    window.free()


# --- Save, Save As, Reset and the dirty indicator ------------------------------


## Save writes under the loaded name and Save As asks for one, both through
## `SaPresetStore` with no second copy of that logic.
func test_save_writes_under_the_loaded_name() -> void:
    var store := _store()
    var window := SaBrushEditorWindow.new()
    window.bind_tool(_brush(), _specs(), store, "")
    assert_eq(window.preset_bar.save(), "", "With no preset loaded, Save asks for a name rather than inventing one")
    assert_true(window.preset_bar.preset_name_edit.visible, "and the name field is what it asks with")

    window.preset_bar.write_named("Inker")
    assert_eq(window.preset_bar.session.preset_name, "Inker", "Submitting a name writes the preset")
    assert_true(store.has_preset("Inker"), "and the store holds it")

    _brush().settings.radius = 0.09
    assert_eq(window.preset_bar.save(), "Inker", "Save then writes over the same name")
    var stored := store.load_preset("Inker")
    assert_almost_eq(float(stored.get("radius")), 0.09, 0.0001, "with the settings as they are now")
    window.free()


## A rename is a write under the new name and a delete of the old, in that order,
## so a failed write leaves the painter with the preset they had.
func test_a_rename_writes_the_new_name_and_removes_the_old() -> void:
    var store := _store()
    var window := SaBrushEditorWindow.new()
    window.bind_tool(_brush(), _specs(), store, "")
    window.preset_bar.write_named("Inker")
    window.preset_bar.begin_rename()
    assert_eq(window.preset_bar.preset_name_edit.text, "Inker", "Rename prefills the loaded name")
    window.preset_bar.write_named("Liner")
    assert_true(store.has_preset("Liner"), "The new name is written")
    assert_false(store.has_preset("Inker"), "and the old one is gone")
    assert_eq(window.preset_bar.session.preset_name, "Liner", "and the window is on the new one")
    window.free()


## Whoever else lists presets is told after the rename's delete, not between the
## write and it.
##
## Emitting `preset_written` from inside the write would let the delete run after
## the listeners had already re-read the store, so the tool options bar's
## dropdown would draw a row for a file that is gone by the time a painter
## reaches for it. `scenarios/presets-and-pen-settings.json` is where it
## shows: the chooser filtered to "Probe" listed both "Probe Editor" and "Probe Round"
## after the editor had renamed the second into the first. The session performs
## the whole rename and the window signals once it is done, so the list a
## listener reads is the list on disk.
func test_a_rename_tells_its_listeners_once_the_old_preset_is_gone() -> void:
    var store := _store()
    var window := SaBrushEditorWindow.new()
    window.bind_tool(_brush(), _specs(), store, "")
    window.preset_bar.write_named("Inker")

    # A dictionary rather than a local the lambda writes: GDScript captures by
    # value, so an assignment inside the handler would never reach this scope.
    var seen := {}
    window.preset_written.connect(func(_stored: String) -> void: seen["names"] = store.list_names())
    window.preset_bar.begin_rename()
    window.preset_bar.write_named("Liner")
    var listed: PackedStringArray = seen.get("names", PackedStringArray())
    assert_true("Liner" in listed, "The new name is listed when the signal arrives")
    assert_false("Inker" in listed, "and the renamed-away one is already gone")
    window.free()


## The indicator is a comparison against the file rather than a flag, so a
## setting changed from the bar while the editor is open reads dirty too.
func test_the_dirty_indicator_follows_the_stored_preset() -> void:
    var store := _store()
    var window := SaBrushEditorWindow.new()
    window.bind_tool(_brush(), _specs(), store, "")
    assert_true(window.preset_bar.is_dirty(), "With nothing saved, there is nothing to be clean against")

    window.preset_bar.write_named("Inker")
    assert_false(window.preset_bar.is_dirty(), "A save leaves it clean")
    assert_eq(window.preset_bar.dirty_label.text, SaBrushEditorSession.CLEAN_TEXT, "and the label says so")

    # From outside the window, which is what makes the comparison worth its cost.
    _brush().settings.radius = 0.123
    window.preset_bar.sync_dirty()
    assert_true(window.preset_bar.is_dirty(), "A setting moved anywhere reads dirty")
    assert_eq(window.preset_bar.dirty_label.text, SaBrushEditorSession.DIRTY_TEXT, "and the label says that")

    window.preset_bar.save()
    assert_false(window.preset_bar.is_dirty(), "and saving over it is clean again")
    window.free()


## The third state, an editor opened with no preset loaded.
##
## An editor opened on a tool with no preset loaded has nothing on the left of
## the comparison, so "Unsaved changes" is a sentence about work the painter has
## not done. The boolean is left alone on purpose: the save path reads it and a
## brush with no preset behind it does have something worth writing.
func test_an_editor_with_no_preset_says_so_rather_than_unsaved() -> void:
    var store := _store()
    var window := SaBrushEditorWindow.new()
    window.bind_tool(_brush(), _specs(), store, "")

    assert_eq(window.preset_bar.session.preset_name, "", "The window is on no preset")
    assert_eq(window.preset_bar.dirty_text(), SaBrushEditorSession.NO_PRESET_TEXT, "so it says so")
    assert_eq(window.preset_bar.dirty_label.text, SaBrushEditorSession.NO_PRESET_TEXT, "and the label a painter reads agrees")
    assert_true(window.preset_bar.is_dirty(), "while the boolean the save path reads is untouched")

    window.preset_bar.write_named("Inker")
    assert_eq(window.preset_bar.dirty_text(), SaBrushEditorSession.CLEAN_TEXT, "A save puts it on the two-state pair")

    _brush().settings.radius = 0.123
    window.preset_bar.sync_dirty()
    assert_eq(window.preset_bar.dirty_text(), SaBrushEditorSession.DIRTY_TEXT, "and an edit reads the other one")
    window.free()


## The three strings are three, which is the point of this test: a build
## that made the new one equal to either of the others would pass every
## assertion above and say nothing new on screen.
func test_the_three_indicator_states_are_three_different_sentences() -> void:
    var seen := {
        SaBrushEditorSession.CLEAN_TEXT: true,
        SaBrushEditorSession.DIRTY_TEXT: true,
        SaBrushEditorSession.NO_PRESET_TEXT: true,
    }
    assert_eq(seen.size(), 3, "Saved, Unsaved changes and No preset are three sentences")


## Reset puts the settings back to the stored preset and leaves the preset alone.
func test_reset_puts_the_settings_back() -> void:
    var store := _store()
    var window := SaBrushEditorWindow.new()
    window.bind_tool(_brush(), _specs(), store, "")
    _brush().settings.radius = 0.05
    window.preset_bar.write_named("Inker")

    _brush().settings.radius = 0.19
    window.preset_bar.reset()
    assert_almost_eq(float(_brush().settings.radius), 0.05, 0.0001, "The settings come back")
    assert_true(store.has_preset("Inker"), "and the preset is still there")
    assert_false(window.preset_bar.is_dirty(), "so the window is clean")
    window.free()


## The comparison walks the same properties `copy_settings` does, or a field the
## save does not carry would leave the window dirty for ever.
func test_a_field_the_save_excludes_cannot_make_it_dirty() -> void:
    var store := _store()
    var window := SaBrushEditorWindow.new()
    window.bind_tool(_brush(), _specs(), store, "")
    window.preset_bar.write_named("Inker")
    assert_true(SaPresetStore.EXCLUDED_KEYS.has("color"), "The colour is what a preset does not carry")
    _brush().settings.color = Color(0.1, 0.2, 0.3)
    assert_false(window.preset_bar.is_dirty(), "so changing it is not a change to the preset")
    window.free()


# --- The command and the seam --------------------------------------------------


## The window has a door that the bar's button runs.
func test_an_edit_brush_command_is_registered() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    SaAppCommands.register_all(registries, func(_id: StringName) -> void: pass)
    var command := registries.commands.get_descriptor(&"edit_brush")
    assert_not_null(command, "There is an edit_brush command")
    if command != null:
        assert_eq(command.title, "Edit brush", "named as the Keyboard Shortcuts page lists it")
        assert_eq(command.menu_label(), "Edit Brush...", "with the label the menu would draw")
        assert_false(command.default_events.is_empty(), "and a chord of its own")
    registries = null
    Fixtures.teardown(surface)


## `ToolOptionControls.open_curve_editor` is a seam for this window to bind, and its
## docstring says the button falls back to the bare host until it is bound.
func test_the_curve_editor_seam_exists_for_this_window_to_bind() -> void:
    var probe := SaBrushEditorWindow.new()
    assert_true(probe.has_method("show_curve_option"), "The window can be pointed at one page")
    probe.free()
    assert_true("open_curve_editor" in ToolOptionControls, "and the seam is still there to bind")


## Rename and Reset with no preset loaded do nothing, the
## session's reset answering false and a rename having no name to move. Both are
## dimmed while there is no preset and lit once one is written.
func test_rename_and_reset_are_dimmed_with_no_preset_loaded() -> void:
    var store := _store()
    var window := SaBrushEditorWindow.new()
    window.bind_tool(_brush(), _specs(), store, "")
    assert_true(window.preset_bar.rename_button.disabled, "No preset loaded offers no Rename")
    assert_true(window.preset_bar.reset_button.disabled, "and no Reset")

    window.preset_bar.write_named("Inker")
    assert_false(window.preset_bar.rename_button.disabled, "A written preset lights Rename")
    assert_false(window.preset_bar.reset_button.disabled, "and Reset")
    window.free()
