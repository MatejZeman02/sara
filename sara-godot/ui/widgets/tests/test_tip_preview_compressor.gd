## The tip preview draws through the stroke strip's compressor.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The hardness slider in the Brush Editor lagged. The General page carries the
## tip preview, and every
## value the slider sent drew a dab through `SaPresetThumbs.render`, a fresh
## easel painted and read back, with nothing to fold the ticks of a drag
## together. The claim is a count, so the suite counts.
##
## Nothing here is added to the tree. A `Window` in a headless tree maps a real
## OS window, and a detached compressor's Timer never runs, so its `timeout` is
## emitted here where a running tree would have closed the window.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const EditorPages = preload("res://ui/brush_editor/editor_pages.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## The window builds every control the Tool Options docker does, and a preview
## is a dab on a real document, so this suite wants the device the runner has.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_tip_preview_compressor")

## The key the stamp brush declares General's tip preview under.
const GENERAL_PREVIEW: StringName = &"tip_preview_general"

## The values one drag across the slider sends, give or take a hand.
const DRAG_TICKS: int = 50

## What a stand-in draw costs, in milliseconds. Longer than the shortest window,
## which is the case the first draft of this unit lost to.
const SLOW_DRAW_MSEC: int = 150

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _slow_draws: int = 0


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _slow_draws = 0


func after_each() -> void:
    Fixtures.teardown(_surface, _machine)
    ScratchFolder.clear(scratch_dir)


## A window bound to the brush and open on General, the page the Hardness row
## and the tip preview share.
func _window_on_general() -> SaBrushEditorWindow:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    var specs: Array[SaOptionSpec] = []
    specs.assign(_machine.get_descriptor(&"brush").options)
    var window := SaBrushEditorWindow.new()
    window.bind_tool(_machine.get_tool("brush"), specs, store)
    for index in window.page_list.page_count():
        if window.page_list.title_at(index) == EditorPages.DEFAULT_PAGE:
            window.show_page(index)
    return window


## The General page's tip preview, the stamp brush's row,
## found through the page's controls by the key the module declared it under.
func _general_preview(window: SaBrushEditorWindow) -> SaTipPreview:
    if window.pages.page_controls == null:
        return null
    return window.pages.page_controls.control(GENERAL_PREVIEW) as SaTipPreview


## The hardness the drag has reached at *tick*, from hard to soft.
func _hardness_at(tick: int) -> float:
    return 1.0 - float(tick) / float(DRAG_TICKS - 1)


func _slow_draw() -> void:
    OS.delay_msec(SLOW_DRAW_MSEC)
    _slow_draws += 1


## Fifty hardness changes inside the window are one draw at once and one more
## when it closes, and the one it closes on is the last change's dab.
func test_fifty_hardness_changes_draw_once_at_once_and_once_when_the_window_closes() -> void:
    var settings := StampSettingsScript.new()
    settings.hardness.value = 1.0
    var preview := SaTipPreview.new()
    preview.bind_source(StateBrushScript, settings)

    preview.request()
    assert_eq(preview.renders, 1, "The first change draws at once")
    var hard_ink: int = int(preview.preview_report()["ink"])
    for tick in range(1, DRAG_TICKS):
        settings.hardness.value = _hardness_at(tick)
        preview.request()
    assert_eq(preview.renders, 1, "and the other forty-nine draw nothing while the window is open")
    assert_eq(preview.compressor.coalesced, DRAG_TICKS - 1, "every one of them counted rather than dropped")
    assert_true(preview.compressor.pending, "with one draw waiting for the window to close")
    assert_eq(int(preview.preview_report()["coalesced"]), DRAG_TICKS - 1, "The dump counts what the preview folded")
    assert_eq(int(preview.preview_report()["ink"]), hard_ink, "and the picture is still the hard dab")

    preview.compressor.timeout.emit()
    assert_eq(preview.renders, 2, "The window closing draws once more")
    assert_false(preview.compressor.pending, "and leaves nothing waiting")
    var soft_ink: int = int(preview.preview_report()["ink"])
    preview.render_now()
    assert_eq(soft_ink, int(preview.preview_report()["ink"]), "The draw it closed on is the dab a hardness of nothing draws")
    assert_true(soft_ink != hard_ink, "which is a different dab from the first, or this case proves nothing")
    preview.free()


## Two compressors asked one after the other, each draw longer than the shortest
## window, which is the strip and the tip preview on every tick. With the window
## fixed at 100 ms each draw closed the other's window and nothing coalesced.
func test_a_draw_longer_than_the_window_does_not_close_its_siblings_window() -> void:
    var strip := SaPreviewCompressor.new(_slow_draw)
    var tip := SaPreviewCompressor.new(_slow_draw)
    strip.request()
    tip.request()
    assert_eq(_slow_draws, 2, "The first ask draws both at once")
    assert_true(strip.window_msec() >= SLOW_DRAW_MSEC * 2, "and a slow draw opens a window twice its own length")

    strip.request()
    tip.request()
    assert_eq(_slow_draws, 2, "The second ask draws neither, though the tip's draw outlasted the shortest window")
    assert_eq(strip.coalesced + tip.coalesced, 2, "and both asks wait for their windows")
    strip.free()
    tip.free()


## The tick as the slider sends it, through the window: the pages'
## `option_written` is what the row's `value_changed` reaches. Asked of the strip and the tip preview
## both, so a draw of one inside the loop can push the other past its window,
## and the count is bounded rather than exact.
func test_a_drag_through_the_editor_folds_the_ticks_into_a_few_dabs() -> void:
    var window := _window_on_general()
    var preview := _general_preview(window)
    assert_not_null(preview, "General carries the tip preview the Hardness row sits beside")
    var drawn_by_the_page := preview.renders

    for tick in DRAG_TICKS:
        window.settings.get("hardness").set("value", _hardness_at(tick))
        window.pages.option_written.emit(&"hardness", _hardness_at(tick))
    var drawn := preview.renders - drawn_by_the_page
    assert_eq(drawn + preview.compressor.coalesced, DRAG_TICKS, "Every tick is a dab or a folded ask")
    assert_true(drawn >= 1 and drawn <= 3, "and fifty ticks are a few dabs rather than fifty, drew %d" % drawn)
    var report: Dictionary = window.editor_report()["widgets"][String(GENERAL_PREVIEW)]
    assert_eq(int(report["coalesced"]), preview.compressor.coalesced, "The editor's dump carries the count")
    window.free()


## The strip and the tip preview answer to one class, so the rule cannot drift
## between the two the way a copy would.
func test_the_strip_and_the_tip_preview_share_one_compressor_class() -> void:
    var window := _window_on_general()
    assert_true(_general_preview(window).compressor is SaPreviewCompressor, "The tip preview's rule is the class")
    assert_true(window.preview_image.compressor is SaPreviewCompressor, "and so is the strip's")
    window.free()
