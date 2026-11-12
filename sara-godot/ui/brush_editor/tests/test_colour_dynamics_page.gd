## One editor page carrying several curve options, which is what the Colour
## Dynamics page is.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `SaBrushEditorPages.pages_from` makes one page per title, because a second
## curve option beside the first would otherwise be two things claiming one
## checkbox in the list on the left. The checkbox is on the page, one per
## option, and a page carrying several is not checkable in the list. What is here is that rule from both ends: the shape
## `pages_from` answers, and the controls a shown page actually builds.
##
## **Two halves, and only the second needs a window.** `pages_from` is static and
## takes a list of specs, so the grouping is asked of it directly with specs this
## file writes. The building is asked of a bound window, detached the way
## `test_ticks_follow_a_loaded_preset.gd` builds one: a `Window` added to the
## tree in a headless run hangs.
##
## The module's own half, that the five colour options name this page and the
## source row sits above them, is
## `modules/sara-base-modules/stamp-brush/tests/test_darken_and_mix.gd`. The
## picture is `scenarios/darken-and-mix-and-the-colour-page.json`.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The window builds curve controls and a scratchpad with a canvas in it.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_d2_colour_page")

## The title the stamp brush's five colour options share, as a string, because
## this file is the skeleton's and the skeleton names no module class.
const COLOUR_PAGE: String = "Colour Dynamics"

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


func _window() -> SaBrushEditorWindow:
    var window := SaBrushEditorWindow.new()
    var specs: Array[SaOptionSpec] = []
    specs.assign(_machine.get_descriptor(&"brush").options)
    window.bind_tool(_machine.get_tool("brush"), specs, _store())
    return window


## A curve option spec naming *page*, with a real property behind it so a bound
## window can resolve it. Written here rather than taken off the brush, because
## the grouping is a rule about specs and not about this module's list.
func _curve(key: StringName, label: String, page: String) -> SaOptionSpec:
    var spec := SaOptionSpec.make(key, label, SaOptionSpec.Kind.CURVE_OPTION)
    spec.property = NodePath(String(key))
    spec.page = page
    return spec


func _page_named(pages: Array[Dictionary], title: String) -> Dictionary:
    for page: Dictionary in pages:
        if String(page["title"]) == title:
            return page
    return {}


# --- What `pages_from` answers ------------------------------------------------


## Three curve options naming one page are one page, and the page carries all
## three. They are not three pages with one title, which would show
## the title three times in the list on the left.
func test_curve_options_naming_one_page_are_one_page() -> void:
    var specs: Array[SaOptionSpec] = [
        _curve(&"a_option", "A", "Shared"),
        _curve(&"b_option", "B", "Shared"),
        _curve(&"c_option", "C", "Shared"),
    ]
    var pages := SaBrushEditorPages.pages_from(specs)

    assert_eq(pages.size(), 1, "One page for the three")
    var page := pages[0]
    assert_eq(String(page["title"]), "Shared", "under the title they named")
    assert_eq((page["curves"] as Array).size(), 3, "carrying all three curve options")
    assert_eq((page["curve"] as SaOptionSpec).key, &"a_option", "and the first of them is the page's own")


## A curve option that names no page is still a page of its own, which is every
## other curve option in the app.
func test_a_curve_option_naming_no_page_is_still_its_own_page() -> void:
    var lone := SaOptionSpec.make(&"lone_option", "Lone", SaOptionSpec.Kind.CURVE_OPTION)
    lone.property = NodePath("lone_option")
    var pages := SaBrushEditorPages.pages_from([lone] as Array)

    assert_eq(pages.size(), 1, "One page")
    assert_eq(String(pages[0]["title"]), "Lone", "titled by its label")
    assert_eq((pages[0]["curves"] as Array).size(), 1, "carrying the one option")


## A plain row naming the shared page joins it, the way the Texture rows join
## theirs, and it joins the one page rather than the first of several.
func test_a_plain_row_joins_the_shared_page_once() -> void:
    var row := SaOptionSpec.make(&"a_source", "Source", SaOptionSpec.Kind.ENUM)
    row.page = "Shared"
    var specs: Array[SaOptionSpec] = [_curve(&"a_option", "A", "Shared"), _curve(&"b_option", "B", "Shared"), row]
    var pages := SaBrushEditorPages.pages_from(specs)

    assert_eq(pages.size(), 1, "Still one page")
    assert_eq((pages[0]["specs"] as Array).size(), 3, "with the two options and the row on it")


## The brush's own list, read through the same door: the five colour options are
## one page and every page title appears once.
func test_the_brush_declares_the_colour_page_once() -> void:
    var specs: Array[SaOptionSpec] = []
    specs.assign(_machine.get_descriptor(&"brush").options)
    var pages := SaBrushEditorPages.pages_from(specs)
    var titles: Array[String] = []
    for page: Dictionary in pages:
        titles.append(String(page["title"]))

    assert_eq(titles.count(COLOUR_PAGE), 1, "The colour page is declared once")
    for title: String in titles:
        assert_eq(titles.count(title), 1, "and no title is declared twice, including %s" % title)
    var colour := _page_named(pages, COLOUR_PAGE)
    assert_eq((colour["curves"] as Array).size(), 5, "and the colour page carries five curve options")


# --- What a shown page builds -------------------------------------------------


## The page is in the list, is not checkable, and builds a control per option
## when it is shown.
func test_the_colour_page_builds_a_control_for_every_option() -> void:
    var window := _window()
    var at := window.pages.index_of(COLOUR_PAGE)
    assert_true(at >= 0, "The brush declares a colour page")
    assert_false(window.pages.has_switch(at), "which has no switch of its own")
    assert_false(bool((window.page_list.row_report()[at] as Dictionary)["switch"]), "and says so in the row it reports")
    assert_eq(String((window.page_list.row_report()[at] as Dictionary)["group"]), "Dynamics", "though it is a dynamic")

    window.show_page(at)
    assert_eq(window.pages.curve_controls.size(), 5, "Five graphs on the page")
    assert_eq(window.pages.curve_control, window.pages.curve_controls[0], "and the page's own is the first of them")
    window.free()


## Every other curve page still draws exactly one control and keeps its one
## switch, now at the top of the page, which is the half of the old rule that
## did not change.
func test_a_page_of_one_option_is_unchanged() -> void:
    var window := _window()
    var at := window.pages.index_of("Size")
    assert_true(at >= 0, "The brush declares a Size page")
    assert_true(window.pages.has_switch(at), "with a switch of its own")

    window.show_page(at)
    assert_eq(window.pages.curve_controls.size(), 1, "and one graph on it")
    window.free()


## A switch on the shared page writes its own option's `enabled` and no other,
## which is what a page carrying five needs and what one checkbox could not do.
func test_a_switch_on_the_shared_page_writes_its_own_option() -> void:
    var window := _window()
    var at := window.pages.index_of(COLOUR_PAGE)
    window.show_page(at)
    var keys: Array[StringName] = []
    for spec: SaOptionSpec in window.pages.open_specs():
        if spec.kind == SaOptionSpec.Kind.CURVE_OPTION:
            keys.append(spec.key)
    assert_eq(keys.size(), 5, "Five options on the open page")

    var settings: Resource = window.settings
    var before: Array[bool] = []
    for key: StringName in keys:
        before.append(bool(settings.get(key).enabled))

    window.pages.set_option_enabled(keys[3], not before[3])
    for i in keys.size():
        var want := (not before[3]) if i == 3 else before[i]
        assert_eq(bool(settings.get(keys[i]).enabled), want, "%s is where it should be" % keys[i])

    window.pages.set_option_enabled(keys[3], before[3])
    window.free()


## The dump reports the page's rows, which is what a scenario reads: the five
## options, the source and the preset's gradient, in the order the module
## declared them.
func test_the_open_page_reports_its_five_options_and_the_source() -> void:
    var window := _window()
    window.show_page(window.pages.index_of(COLOUR_PAGE))
    var labels: Array[String] = []
    for row: Dictionary in window.pages.row_report():
        labels.append(String(row["label"]))

    assert_eq(
        labels,
        ["Hue", "Saturation", "Value", "Darken", "Mix", "Colour source", "Gradient"] as Array[String],
        "The five options, the row that says where the colour comes from, then the gradient"
    )
    window.free()
