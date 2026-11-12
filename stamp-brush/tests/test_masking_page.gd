## The Masking Brush page: the rows it declares, where they point, and the tick
## the page list draws for it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The claim worth writing down is the one about addresses.** The page is the
## Brush Tip page's rows a second time, rewritten onto the second tip, so the
## way it goes wrong is a row that still points at the painted tip: the painter
## drags Ratio on the Masking Brush page and squashes the brush. Half of this
## file is that one claim read from four sides, the property, the key, the rules
## that name another key, and the value the settings actually answer.
##
## The window is never added to the tree, for the reason
## `ui/brush_editor/tests/test_brush_editor_window.gd` gives: a `Window` in the tree maps a real
## OS window and the run blocks until the watchdog fires.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const ModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")

## The window builds the same controls the Tool Options docker does, and the
## curve pages beside this one build a curve editor.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_masking_page")

var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    ScratchFolder.clear(scratch_dir)


func _rows() -> Array[SaOptionSpec]:
    return SaMaskingPage.rows(ModuleScript.tip_options())


## Every spec the brush declares, which is what the editor and the docker are
## both built from.
func _specs() -> Array[SaOptionSpec]:
    var out: Array[SaOptionSpec] = []
    out.assign(_machine.get_descriptor(&"brush").options)
    return out


func _window() -> SaBrushEditorWindow:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    var window := SaBrushEditorWindow.new()
    window.bind_tool(_machine.get_tool("brush"), _specs(), store, "")
    return window


# --- Where the rows point -----------------------------------------------------


## The claim the page rests on: not one row reaches the tip the painter paints
## with.
func test_every_row_names_the_masking_block_and_none_the_painted_tip() -> void:
    var rows := _rows()

    assert_true(rows.size() > 3, "The page is the switch, the two numbers and the tip rows, %d of them" % rows.size())
    for spec: SaOptionSpec in rows:
        var path := String(spec.property_path())
        assert_true(path.begins_with("masking:"), "%s reaches into the masking block, and reads %s" % [spec.key, path])
        assert_false(path.begins_with("tip:"), "%s does not reach the painted tip" % spec.key)
        assert_true(String(spec.key).begins_with("masking_"), "%s has an address of its own" % spec.key)
        assert_eq(spec.page, SaMaskingPage.PAGE, "and it sits on the Masking Brush page")


## The tip rows are the Brush Tip page's own, taken rather than retyped, so the
## names and the order are the Brush Tip page's and nothing here chose them
## beyond the word that says which tip they are about.
func test_the_tip_rows_are_the_brush_tip_pages_own_in_its_order() -> void:
    var expected: Array[String] = []
    for spec: SaOptionSpec in ModuleScript.tip_options():
        # Less the rows the page drops on purpose, which is the lightness row:
        # the mask reads its own picture as a ramp whatever file it names, so a
        # row that moves something the kernel never reads is a control that
        # lies.
        if String(spec.property).begins_with("tip:") and not SaMaskingPage.NOT_THE_MASKS.has(spec.key):
            expected.append(SaMaskingPage.LABEL_PREFIX + spec.label)

    var found: Array[String] = []
    for spec: SaOptionSpec in _rows():
        if String(spec.property_path()).begins_with("masking:tip:"):
            found.append(spec.label)

    assert_true(expected.size() >= 10, "The Brush Tip page has tip rows to take, %d of them" % expected.size())
    assert_eq(found, expected, "and the mask has the same ones, in the same order, each named for the mask")


## No name the brush declares is on the Tool Options docker twice, which is
## the reason the labels are prefixed at all. Read off the specs rather than
## off the built rows, because `ui/dockers/tool_options/tests/test_painter.gd` reads the rows and
## the two together say the same thing at both ends.
func test_no_mask_row_answers_to_a_name_the_brush_already_uses() -> void:
    var taken: Array[String] = []
    for spec: SaOptionSpec in ModuleScript.brush_options():
        if String(spec.key).begins_with("masking_"):
            continue
        taken.append(spec.label)

    for spec: SaOptionSpec in _rows():
        assert_false(taken.has(spec.label), "%s is called something no other row is called" % spec.key)


## The brush's own rows are left where they are: Spacing, Cross, the airbrush
## three and the two Sharpness rows are the brush's rather than the tip's, and
## Load Tip writes to the painted tip through the tool.
func test_the_rows_that_are_the_brushs_rather_than_the_tips_are_left_alone() -> void:
    var keys: Array[String] = []
    for spec: SaOptionSpec in _rows():
        keys.append(String(spec.key))

    for taken: String in ["masking_spacing", "masking_tip_generator", "masking_tip_ratio"]:
        assert_true(keys.has(taken), "%s is on the page" % taken)
    for left: String in ["masking_painting_mode", "masking_airbrush_enabled", "masking_sharpness", "masking_tip_load"]:
        assert_false(keys.has(left), "%s is not, because it is not a question about a tip" % left)


## A row's rules name other rows by key, so a rule that was not rewritten is a
## Masking Brush row obeying the painted tip's generator.
func test_a_rule_naming_another_row_names_the_masks_copy_of_it() -> void:
    var rows := _rows()
    var keys: Array[StringName] = []
    for spec: SaOptionSpec in rows:
        keys.append(spec.key)

    var rules := 0
    for spec: SaOptionSpec in rows:
        if not String(spec.enabled_when).is_empty():
            rules += 1
            assert_true(keys.has(spec.enabled_when), "%s is dimmed by %s, a row on this page" % [spec.key, spec.enabled_when])
        if not String(spec.pair_with).is_empty():
            rules += 1
            assert_true(keys.has(spec.pair_with), "%s shares its row with %s, on this page" % [spec.key, spec.pair_with])
        if spec.shown_when.has("key"):
            rules += 1
            var named := StringName(spec.shown_when["key"])
            assert_true(keys.has(named), "%s is shown under %s, a row on this page" % [spec.key, named])
    assert_true(rules > 5, "There are rules to have got wrong, %d of them" % rules)


## The Brush Tip page's rules are untouched by the rewriting, which is the other
## half of the claim above: the mask's rows were copies and not the originals
## moved.
func test_taking_the_rows_leaves_the_brush_tip_pages_own_where_they_were() -> void:
    var mask := _rows()
    assert_false(mask.is_empty(), "The page took rows")

    for spec: SaOptionSpec in ModuleScript.tip_options():
        assert_false(String(spec.key).begins_with("masking_"), "%s is still the Brush Tip page's own" % spec.key)
        if String(spec.property).begins_with("tip:"):
            assert_false(String(spec.property).begins_with("masking:"), "%s still reaches the painted tip" % spec.key)


## Every row answers something on a real settings resource, which is the reading
## a property path typed wrong does not survive.
func test_every_row_reads_a_value_the_settings_hold() -> void:
    var settings := SaStampBrushSettings.new()

    for spec: SaOptionSpec in _rows():
        var value: Variant = settings.get_indexed(spec.property_path())
        assert_true(value != null, "%s reads something at %s" % [spec.key, spec.property_path()])


## Off the bar and behind Advanced, the judgement the Texture page made for the
## same reason.
func test_the_page_is_off_the_bar_and_behind_the_advanced_check() -> void:
    for spec: SaOptionSpec in _rows():
        assert_false(spec.bar, "%s is not a row on the top bar" % spec.key)
        assert_true(spec.advanced, "%s is behind the Advanced check" % spec.key)


# --- The tick -----------------------------------------------------------------


## The page has a switch, which is the reason
## `page_switch` exists. The switch is at the top of the
## page and the list draws a dot while it is on.
func test_the_page_list_draws_the_masking_pages_checkbox() -> void:
    var window := _window()
    var index := window.pages.index_of(SaMaskingPage.PAGE)

    assert_true(index >= 0, "The editor lists a Masking Brush page")
    var rows: Array = window.page_list.row_report()
    assert_true(bool(rows[index]["switch"]), "and the page has a switch")
    assert_false(bool(rows[index]["on"]), "which is off, because the mask is")
    assert_eq(String(rows[index]["group"]), "Dynamics", "under the Dynamics heading")
    window.free()


## And the switch is the mask's own, not one that reads back to nothing.
func test_the_checkbox_writes_the_masks_enabled() -> void:
    var window := _window()
    var settings := window.settings
    var index := window.pages.index_of(SaMaskingPage.PAGE)

    window.set_page_enabled(index, true)
    assert_true(bool(settings.masking.enabled), "The tick switched the mask on")
    window.sync_ticks()
    assert_true(bool(window.page_list.row_report()[index]["on"]), "and the row reads on")

    window.set_page_enabled(index, false)
    assert_false(bool(settings.masking.enabled), "and off again")
    window.sync_ticks()
    assert_false(bool(window.page_list.row_report()[index]["on"]), "with the row following it")
    window.free()


## A plain page is still plain, which is the rule `page_switch` had to be added
## without breaking: a switch on a page with nothing to switch reads as an option
## the painter is not allowed to switch off.
func test_a_page_with_nothing_to_switch_still_draws_no_checkbox() -> void:
    var window := _window()

    for title: String in ["Brush Tip", "General"]:
        var index := window.pages.index_of(title)
        assert_true(index >= 0, "%s is a page" % title)
        assert_false(bool(window.page_list.row_report()[index]["switch"]), "and it has no switch")
    window.free()


## The switch is the page's own at its top and not also a row, or the page
## would ask the same question twice.
func test_the_switch_is_not_drawn_as_a_row_under_the_heading() -> void:
    var window := _window()
    var index := window.pages.index_of(SaMaskingPage.PAGE)
    window.show_page(index)

    var drawn: Array[String] = []
    for row: Dictionary in window.pages.row_report():
        if bool(row["in_editor"]):
            drawn.append(String(row["key"]))
    assert_false(drawn.has("masking_enabled"), "The switch is the page's own and no row under its heading")
    assert_true(drawn.has("masking_size"), "while the mask's size is a row")
    assert_true(drawn.has("masking_spacing"), "and so is its spacing")
    window.free()


## Where the page order puts it, which the editor reads off the module's
## declaration: a page lands where its first row is.
func test_the_page_sits_between_texture_and_airbrush_rate() -> void:
    var window := _window()
    var index := window.pages.index_of(SaMaskingPage.PAGE)

    assert_eq(window.pages.title_at(index - 1), "Texture", "Texture is above it")
    assert_eq(window.pages.title_at(index + 1), "Airbrush Rate", "and Airbrush Rate below")
    window.free()
