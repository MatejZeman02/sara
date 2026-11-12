## The tip preview's follow: the ear the row puts on its tool's `tip_loaded`,
## the dab it asks for again when a tip lands, and the Tip Image grid beside it
## that hears the same loads.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The preview must not rebuild the Tip Image row's list or have the page drawn
## again around a list that grew. The row is the door's grid, which lists again
## by itself, so a load leaves the page as it is and the claims about the list
## read the grid.
##
## The window is built and never added to the tree, the way
## `test_brush_editor_window.gd` builds it: a `Window` in a headless tree maps a
## real OS window and the run blocks until the watchdog fires.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## The window builds every control the Tool Options docker does, and a tip load
## uploads the image, so this suite wants the device the runner has.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_tip_preview_follow")

## A picture that is in neither tip folder, so the grid can only carry it
## because the tool loaded it.
const OUTSIDE_TIP: String = "res://ui/icon-bw.png"

## A picture that is in a tip folder, so the grid already carries it.
const LISTED_TIP: String = "res://tips/tree.png"

const TIP_ROW: StringName = &"tip_image_path"
const PREVIEW: StringName = &"tip_preview"

var _surface: SaSurface = null
var _machine: ToolMachine = null


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    # The brush's settings are the module's and outlive a test, so every test
    # starts on the procedural tip whatever the last one loaded, and so do the
    # pictures the door remembers loading from outside the tip folders.
    _brush().load_tip("")
    SaBrushTipMask.forget_loaded_elsewhere()


func after_each() -> void:
    _brush().load_tip("")
    SaBrushTipMask.forget_loaded_elsewhere()
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


func _spec(key: StringName) -> SaOptionSpec:
    for spec: SaOptionSpec in _specs():
        if spec.key == key:
            return spec
    return null


## A window bound to the brush, with the store pointed at the scratch directory.
func _window() -> SaBrushEditorWindow:
    var window := SaBrushEditorWindow.new()
    window.bind_tool(_brush(), _specs(), _store())
    return window


## Opens the page that carries *key* and answers its index, or -1. Found by
## opening each page and asking, rather than by title, so a page renamed in the
## module leaves this suite pointing at the row it is about.
func _open_page_holding(window: SaBrushEditorWindow, key: StringName) -> int:
    for index in window.page_list.row_report().size():
        window.show_page(index)
        for spec: SaOptionSpec in window.pages.open_specs():
            if spec != null and spec.key == key:
                return index
    return -1


func _preview(window: SaBrushEditorWindow) -> SaTipPreview:
    if window.pages.page_controls == null:
        return null
    return window.pages.page_controls.control(PREVIEW) as SaTipPreview


func _grid(window: SaBrushEditorWindow) -> SaTipGrid:
    if window.pages.page_controls == null:
        return null
    return window.pages.page_controls.control(TIP_ROW) as SaTipGrid


## Every path the grid lists, whichever folder it shows.
func _listed(window: SaBrushEditorWindow) -> Array[String]:
    var grid := _grid(window)
    var shown := grid.folder
    grid.choose_folder("")
    var out := grid.shown_paths()
    grid.choose_folder(shown)
    return out


## The heart of the follow. Load Tip is an action rather than an option write,
## so nothing in the editor ticks when it succeeds, and the grid a painter picks
## tips from would go on offering the folders alone.
func test_a_load_puts_the_held_tip_in_the_tip_image_grid() -> void:
    var window := _window()
    assert_true(_open_page_holding(window, TIP_ROW) >= 0, "The Tip Image row is on a page of the editor")
    assert_not_null(_preview(window), "which carries the tip preview")
    assert_not_null(_grid(window), "and draws the row as the door's grid")
    var before := _listed(window)
    assert_false(before.has(OUTSIDE_TIP), "The grid does not offer a picture from outside the tip folders yet")

    assert_true(_brush().load_tip(OUTSIDE_TIP), "A picture from anywhere on disk loads")
    var after := _listed(window)
    assert_true(after.has(OUTSIDE_TIP), "and the grid now carries it, so it can be picked back")
    assert_eq(after.size(), before.size() + 1, "one cell more than the folders alone")
    assert_eq(_grid(window).chosen, OUTSIDE_TIP, "and its cell is the one the row holds")

    window.free()


## A refusal is the other half of the claim: the tool says nothing, so the grid
## must not grow a file the brush is not holding.
func test_a_refused_load_leaves_the_grid_alone() -> void:
    var window := _window()
    _open_page_holding(window, TIP_ROW)
    assert_true(_brush().load_tip(OUTSIDE_TIP), "One load that works")
    var before := _listed(window)

    var refusals: Array[String] = []
    var ear := func(text: String) -> void: refusals.append(text)
    EventBus.paint_refused.connect(ear)
    assert_false(_brush().load_tip("res://tips/no-such-tip.png"), "A file that is not there is refused")
    EventBus.paint_refused.disconnect(ear)

    assert_eq(refusals.size(), 1, "the refusal going where refusals go")
    assert_eq(_listed(window), before, "and the grid is what the load that worked left")
    assert_eq(_grid(window).chosen, OUTSIDE_TIP, "holding what that load chose")

    window.free()


## The page is no longer built again around a load: the grid grows by itself,
## the preview on the page asks for the new dab and the rows are shown their
## values once more. A page built again lost its scroll and its open popups.
func test_a_load_keeps_the_page_and_redraws_the_dab() -> void:
    var window := _window()
    var index := _open_page_holding(window, TIP_ROW)
    var preview := _preview(window)
    var grid := _grid(window)
    var asks_before := preview.renders + preview.compressor.coalesced

    assert_true(_brush().load_tip(OUTSIDE_TIP), "A picture from outside the folders loads")
    assert_eq(window.page_list.selected, index, "leaving the same page open")
    assert_true(_preview(window) == preview, "The page was not built again")
    assert_true(_grid(window) == grid, "and its grid is the same one, grown")
    assert_true(preview.renders + preview.compressor.coalesced > asks_before, "and the preview asked for the new dab")
    assert_eq(String(preview.preview_report()["tip"]), OUTSIDE_TIP, "which it draws from that picture")

    assert_true(_brush().load_tip(LISTED_TIP), "A tip from the folders loads")
    assert_true(_preview(window) == preview, "and the page stays")
    assert_eq(grid.chosen, LISTED_TIP, "the grid holding the tree")
    assert_eq(String(preview.preview_report()["tip"]), LISTED_TIP, "and the preview drawing it")

    window.free()


## A tip can land while no page carrying the row is open, and the grid shows it
## when its page opens.
func test_a_tip_loaded_with_the_row_off_screen_is_in_the_grid_when_its_page_opens() -> void:
    var window := _window()
    var other := -1
    for index in window.page_list.row_report().size():
        window.show_page(index)
        if window.pages.widget_report().is_empty():
            other = index
            break
    assert_true(other >= 0, "A page carrying no preview and no grid is open")

    assert_true(_brush().load_tip(OUTSIDE_TIP), "A load with no grid on screen")
    assert_eq(window.page_list.selected, other, "does not move the painter off the page they are on")

    _open_page_holding(window, TIP_ROW)
    assert_true(_listed(window).has(OUTSIDE_TIP), "The tip page's grid lists the picture as it is drawn")
    assert_eq(_grid(window).chosen, OUTSIDE_TIP, "holding it")

    window.free()


## A rebind onto another tool moves the ear, so a load on the tool the row left
## asks for no dab of a tool the editor is no longer showing.
func test_binding_a_second_tool_takes_the_ear_off_the_first() -> void:
    var window := _window()
    _open_page_holding(window, TIP_ROW)
    var preview := _preview(window)
    var first := _brush()
    var second := StateBrushScript.new()
    preview.follow(second.tip_loaded)
    assert_false(first.tip_loaded.is_connected(preview._on_tip_loaded), "The first tool is off the ear")
    assert_true(second.tip_loaded.is_connected(preview._on_tip_loaded), "and the second is on it")

    var asks: Array = [preview.renders, preview.compressor.coalesced, preview.compressor.pending]
    assert_true(first.load_tip(OUTSIDE_TIP), "A load on the tool the row left")
    assert_eq([preview.renders, preview.compressor.coalesced, preview.compressor.pending], asks, "asks for no dab")

    window.free()


## A value that is not the signal is a tool whose tip never changes behind the
## editor's back, and the ear comes off rather than staying on the last tool.
func test_a_value_that_is_not_the_signal_takes_the_ear_off() -> void:
    var window := _window()
    _open_page_holding(window, TIP_ROW)
    var preview := _preview(window)
    var first := _brush()
    preview.follow(null)
    assert_false(first.tip_loaded.is_connected(preview._on_tip_loaded), "The tool that had the ear no longer has it")

    var asks: Array = [preview.renders, preview.compressor.coalesced, preview.compressor.pending]
    assert_true(first.load_tip(OUTSIDE_TIP), "so a load on it")
    assert_eq([preview.renders, preview.compressor.coalesced, preview.compressor.pending], asks, "reaches the preview not at all")

    window.free()


## The capture door is how a scenario loads a tip past the dialog, and it goes
## to the tool the row is bound to.
func test_the_capture_door_loads_through_the_tool() -> void:
    var window := _window()
    _open_page_holding(window, TIP_ROW)
    var answer := _preview(window).capture_option_edit({"load_tip": LISTED_TIP})
    assert_true(answer.contains("loaded"), "The door says the load worked: %s" % answer)
    assert_eq(String(_brush().settings.tip.image_path), LISTED_TIP, "and the brush holds the tree")
    assert_true(_preview(window).capture_option_edit({}).begins_with("SaCapture:"), "A step with no tip says so")

    window.free()


## The dump reads the preview through the pages' widget report, keyed by the
## row.
func test_the_dump_carries_the_preview_under_its_row() -> void:
    var window := _window()
    _open_page_holding(window, TIP_ROW)
    var widgets: Dictionary = window.editor_report()["widgets"]
    assert_true(widgets.has(String(PREVIEW)), "The open page reports its preview")
    assert_true(bool((widgets[String(PREVIEW)] as Dictionary)["present"]), "which has drawn a dab")
    assert_true(widgets.has(String(TIP_ROW)), "and its Tip Image grid")
    assert_true(int((widgets[String(TIP_ROW)] as Dictionary)["pictures"]) > 0, "whose cells carry pictures")

    window.free()
