## The page list's ticks follow a curve option's `enabled` after the bind.
##
## `SaBrushEditorWindow.bind_tool` read each option's `enabled` once and nothing
## read it again, so a preset loaded from the Brush Presets docker or the bar
## while the editor was open would leave every page's tick where it was, as on
## the Texture page: the list said off while the dump's option said
## `enabled` true and the strip drew the grain.
##
## **Detached, for the reason the F5 suite gives.** A `Window` added to the tree
## in a headless run hangs, so the window is built and bound and never shown,
## which is what `test_editor_size_in_pixels.gd` does too. The scenario holds
## the picture: `scenarios/the-page-list-ticks-do-not-follow-a-preset-loaded-with-the-editor-open.json`
## loads a preset through the bar with the editor open and shoots the tick.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The window builds curve controls and a scratchpad with a canvas in it.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_d11_ticks")

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


## The first page with a switch, and its option.
func _first_curve_page(window: SaBrushEditorWindow) -> int:
    for i in window.pages.count():
        if window.pages.curve_option_at(i) != null:
            return i
    return -1


func _checked(window: SaBrushEditorWindow, index: int) -> bool:
    return bool((window.page_list.row_report()[index] as Dictionary)["on"])


## What the sync is for, held here so it has a reason: the row is a copy of the
## option's `enabled` taken at the bind, and the option moving does not move it.
func test_a_write_to_the_option_leaves_the_row_until_the_sync() -> void:
    var window := _window()
    var at := _first_curve_page(window)
    assert_true(at >= 0, "The brush declares at least one curve option page")
    var option := window.pages.curve_option_at(at)
    var was := bool(option.enabled)
    assert_eq(_checked(window, at), was, "The bind read the option onto the row")
    option.set("enabled", not was)
    assert_eq(_checked(window, at), was, "The row is a copy, so the write alone leaves it")
    window.sync_ticks()
    assert_eq(_checked(window, at), not was, "and the sync brings it over")
    window.sync_ticks()
    assert_eq(_checked(window, at), not was, "A second sync with nothing moved changes nothing")
    option.set("enabled", was)
    window.free()


## Every curve page that has a tick, not only Texture: Size, Opacity and the rest
## are ticked from the same read, so the sync walks them all.
##
## **A page several curve options share is not one of them.**
## The Colour Dynamics page carries five options and draws a switch for each
## on the page itself, so its row in the list on the left has no dot, and
## `has_switch` is what says which pages this claim is about.
func test_the_sync_walks_every_curve_page() -> void:
    var window := _window()
    var flipped: Array[int] = []
    for i in window.pages.count():
        var option := window.pages.curve_option_at(i)
        if option != null and window.pages.has_switch(i):
            option.set("enabled", not bool(option.enabled))
            flipped.append(i)
    assert_true(flipped.size() >= 2, "The brush has more than one curve page to walk")
    window.sync_ticks()
    for i in flipped:
        assert_eq(_checked(window, i), bool(window.pages.curve_option_at(i).enabled), "Page %d follows its option" % i)
    var pages: Array = window.page_list.row_report()
    for i in window.pages.count():
        if not window.pages.has_switch(i):
            assert_false(bool((pages[i] as Dictionary)["on"]), "A page with no switch of its own still has no dot to sync")
    for i in flipped:
        var option := window.pages.curve_option_at(i)
        option.set("enabled", not bool(option.enabled))
    window.free()


## The two places the sync is read from. The preset signal is the case a loaded preset hits,
## and the ticker is what catches a `brush` step or a bar row writing `enabled`
## with no signal at all.
func test_the_preset_signal_and_the_ticker_both_sync() -> void:
    var window := _window()
    var at := _first_curve_page(window)
    var option := window.pages.curve_option_at(at)
    var was := bool(option.enabled)
    option.set("enabled", not was)
    window._on_preset_loaded("")
    assert_eq(_checked(window, at), not was, "A loaded preset syncs the row")
    option.set("enabled", was)
    window.preset_bar.tick()
    assert_eq(_checked(window, at), was, "and so does a tick of the dirty ticker")
    window.free()


## The dump can never disagree with the option, the way `dirty` can never
## disagree with the label: the report syncs before it reads.
func test_the_report_reads_the_option_and_not_the_stale_row() -> void:
    var window := _window()
    var at := _first_curve_page(window)
    var option := window.pages.curve_option_at(at)
    var was := bool(option.enabled)
    option.set("enabled", not was)
    var report: Dictionary = window.editor_report()
    assert_eq(bool((report["pages"][at] as Dictionary)["on"]), not was, "The report's page carries the option's value")
    option.set("enabled", was)
    window.free()
