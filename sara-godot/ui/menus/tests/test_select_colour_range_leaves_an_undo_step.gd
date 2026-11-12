## Select > Colour Range leaves an undo step.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The feature must register the undo step. This drives the Select menu's own path, the
## `select_color_range` command its row and its chord run, the dialog that
## opens, its Apply and the handler behind it, over a painted layer, with Pick
## from canvas ticked and unticked. Apply is one step under the name the Undo
## History docker lists, an undo puts back the marquee that stood before the
## dialog opened, and a redo brings the range back. Opening the dialog, a pick
## from the canvas and the preview record nothing.
##
## **Enter applies too**, the route a range
## could be lost by: on the swatch the dialog opens on, after a pick from the canvas
## has handed the keyboard back, and on a box with its outline, each one step
## undone and redone the same way. In Fuzziness's typed number Enter takes the
## number and applies nothing. The key goes in through `push_input`
## on the dialog's own window, press and release, the way
## `test_enter_presses_the_button_the_outline_is_on.gd` sends it.
##
## The command opens the dialog over the main canvas, `get_tree().current_scene`,
## which a headless run cannot be given because the root is busy setting up
## children for the whole of it. So the command's dialog is reopened over this
## suite's canvas by the method the command calls, the way the app's main would
## hand it over, and that walk to the main scene is
## `scenarios/select-colour-range-leaves-an-undo-step.json` on the app.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## A red the swatch holds exactly, because the swatch takes a colour as the hex
## it shows.
const RED := Color(204.0 / 255.0, 26.0 / 255.0, 26.0 / 255.0, 1.0)
const BLUE := Color(0.1, 0.3, 0.9, 1.0)
## The red band, the left half of the canvas, which a range on the red chooses.
const RED_BAND := Rect2i(0, 0, 256, 512)
## The marquee standing when the dialog opens, inside the blue band, so the way
## back is a selection of its own rather than none.
const BEFORE := Rect2i(300, 300, 100, 100)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _doc: SaDocument = null
var _host: Node = null
var _bar: TopMenuBar = null
var _canvas: SaCanvas = null
var _table: SaShortcutCommands = null
var _kept_embedding: bool = true
var _kept_foreground: Color = Color.BLACK


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _kept_foreground = SaColors.foreground
    SaColors.foreground = Color.WHITE
    # An easel that composites, because Sample merged, on by default, reads the
    # picture rather than the layer.
    _surface = SaSurface.create(&"test", Bench.easel(Vector2i(512, 512)), Fixtures.FakeView.new())
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _registries = Fixtures.make_registries(_surface)
    _doc = _surface.get_document()
    var layer := _doc.active_layer
    _doc.selection.select_rect(RED_BAND)
    _doc.fill_layer(RED, layer)
    _doc.selection.select_rect(Rect2i(256, 0, 256, 512))
    _doc.fill_layer(BLUE, layer)
    _doc.selection.select_rect(BEFORE)
    Bench.composite(_surface.easel)
    # The canvas the dialog opens over, holding the machine the way the app's does,
    # so the dialog's hold puts the Eyedropper in that machine's hand.
    _canvas = SaCanvas.new()
    _canvas.easel = _surface.easel
    _canvas.add_child(_machine)
    _host = Node.new()
    _host.name = "U23TestHost"
    EventBus.add_child(_host)
    _table = SaShortcutCommands.new(Callable(), func() -> SaCanvas: return _canvas, Callable(), null)
    _table.register_into(_registries.commands)
    _bar = TopMenuBar.new()
    _host.add_child(_bar)
    _bar.bind_commands(_registries.commands)


func after_each() -> void:
    _bar.free()
    _bar = null
    _host.free()
    _host = null
    _table = null
    _canvas.remove_child(_machine)
    _canvas.free()
    _canvas = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _registries = null
    _doc = null
    SaColors.foreground = _kept_foreground
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding


func _steps() -> int:
    return _doc.undo_redo.get_history_count()


## The command the Select menu's row runs, and the dialog it opened, reopened
## over this suite's canvas.
func _open_by_the_command() -> SaColorRangeDialog:
    var steps := _steps()
    assert_true(_registries.commands.execute(&"select_color_range"), "The Select menu's command runs")
    var menu := _bar.menu("Select") as SaSelectMenu
    var dialog := menu._color_range_dialog if menu != null else null
    assert_not_null(dialog, "and opens the colour range dialog")
    if dialog == null:
        return null
    assert_true(dialog.visible, "on screen")
    assert_eq(menu.open_color_range_dialog(_canvas), dialog, "The same dialog reopens over the canvas")
    assert_eq(_steps(), steps, "Opening records nothing")
    return dialog


## One range over the painted layer, picked from the canvas when *pick* says so
## and typed into the swatch otherwise, then applied by its button. Answers the
## steps the history held before the dialog opened.
func _apply_a_range(pick: bool) -> int:
    var steps := _steps()
    var dialog := _open_by_the_command()
    if dialog == null:
        return steps
    if pick:
        assert_eq(_machine.active_tool_name, &"eyedropper", "Pick from canvas puts the Eyedropper in the hand")
        # What an Eyedropper click on the red band announces.
        EventBus.color_picked.emit(RED)
    else:
        dialog._pick_row.drive(false)
        assert_eq(_machine.active_tool_name, &"brush", "Unticked, the Brush stays in the hand")
        dialog._color_row.drive(RED.to_html(false))
    assert_true(dialog.picked_color().is_equal_approx(RED), "The swatch holds the red")
    dialog.refresh_preview()
    assert_eq(_steps(), steps, "Opening, the pick and the preview record nothing")
    assert_eq(_doc.selection.bounds, BEFORE, "and leave the marquee as it was")
    dialog.page.apply_button.pressed.emit()
    assert_false(dialog.visible, "Apply closes the dialog")
    return steps


func _check_the_step(steps: int, way: String) -> void:
    assert_eq(_steps(), steps + 1, "%s: Apply is one more step on the history" % way)
    var named := _doc.undo_redo.get_current_action_name()
    assert_eq(named, SaSelection.COLOR_RANGE_TITLE, "%s: named as the Undo History docker lists it" % way)
    assert_true(_doc.selection.active, "%s: the range is selected" % way)
    assert_eq(_doc.selection.bounds, RED_BAND, "%s: over the red band" % way)
    assert_true(_doc.undo(), "%s: an undo is there to take" % way)
    assert_true(_doc.selection.active, "%s: the undo leaves a selection" % way)
    assert_eq(_doc.selection.bounds, BEFORE, "%s: the marquee from before the dialog" % way)
    assert_true(_doc.redo(), "%s: a redo is there to take" % way)
    assert_eq(_doc.selection.bounds, RED_BAND, "%s: the redo brings the range back" % way)


func test_apply_with_pick_from_canvas_ticked_is_one_step_undone_and_redone() -> void:
    _check_the_step(_apply_a_range(true), "Picked from the canvas")
    assert_eq(_machine.active_tool_name, &"brush", "and the Brush is back in the hand")


func test_apply_with_pick_from_canvas_unticked_is_one_step_undone_and_redone() -> void:
    _check_the_step(_apply_a_range(false), "Typed into the swatch")


static func _enter(pressed: bool) -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_ENTER
    key.physical_keycode = KEY_ENTER
    key.pressed = pressed
    return key


## A tap: the press, then the release a focused button waits for.
static func _tap_enter(window: Window) -> void:
    window.push_input(_enter(true))
    window.push_input(_enter(false))


## The dialog opened by the command with Pick from canvas unticked and the red
## typed into the swatch, previewed, and the steps from before it opened.
func _typed_and_previewed() -> Array:
    var steps := _steps()
    var dialog := _open_by_the_command()
    if dialog == null:
        return [null, steps]
    dialog._pick_row.drive(false)
    dialog._color_row.drive(RED.to_html(false))
    dialog.refresh_preview()
    assert_eq(_steps(), steps, "The preview records nothing")
    return [dialog, steps]


func test_enter_on_the_swatch_the_dialog_opens_on_applies_rather_than_opening_its_popup() -> void:
    var opened := _typed_and_previewed()
    var dialog := opened[0] as SaColorRangeDialog
    if dialog == null:
        return
    var swatch := dialog._color_row.control as ColorPickerButton
    swatch.grab_focus()
    assert_eq(dialog.gui_get_focus_owner(), swatch, "The outline is on the swatch")
    _tap_enter(dialog)
    assert_false(dialog.visible, "Enter on the swatch applies and closes the dialog")
    assert_false(swatch.get_popup().visible, "and opens no colour popup, nor does the release")
    _check_the_step(int(opened[1]), "Enter on the swatch")


func test_enter_after_a_pick_from_the_canvas_applies_from_the_keyboard_handed_back() -> void:
    var steps := _steps()
    var dialog := _open_by_the_command()
    if dialog == null:
        return
    dialog.gui_release_focus()
    EventBus.color_picked.emit(RED)
    dialog.refresh_preview()
    assert_eq(_steps(), steps, "The pick and the preview record nothing")
    assert_eq(dialog.gui_get_focus_owner(), null, "The pick alone moves no focus while the pointer is down")
    # The frame after the pointer comes up, which a suite has no frames to wait for.
    dialog._process(0.0)
    assert_eq(dialog.gui_get_focus_owner(), dialog._color_row.control, "The keyboard goes back to the swatch the pick filled")
    assert_false((dialog._color_row.control as Control).has_focus(true), "with no outline drawn on it")
    _tap_enter(dialog)
    assert_false(dialog.visible, "Enter after the pick applies and closes the dialog")
    _check_the_step(steps, "Enter after a pick")
    assert_eq(_machine.active_tool_name, &"brush", "and the Brush is back in the hand")


func test_enter_on_a_box_with_its_outline_applies_and_leaves_the_box_as_it_was() -> void:
    var opened := _typed_and_previewed()
    var dialog := opened[0] as SaColorRangeDialog
    if dialog == null:
        return
    var box := dialog._merged_row.control as CheckButton
    var was := box.button_pressed
    box.grab_focus()
    _tap_enter(dialog)
    assert_false(dialog.visible, "Enter on Sample merged applies and closes the dialog")
    assert_eq(box.button_pressed, was, "and does not flip the box")
    _check_the_step(int(opened[1]), "Enter on a box")


func test_enter_in_the_fuzziness_field_takes_the_number_and_applies_nothing() -> void:
    var opened := _typed_and_previewed()
    var dialog := opened[0] as SaColorRangeDialog
    if dialog == null:
        return
    var steps := int(opened[1])
    assert_false(dialog.number_field_answers, "The dialog says its number field takes a number and nothing more")
    var slider := dialog._fuzziness_row.control as FactorSlider
    slider.start_editing()
    slider._line_edit.text = "12"
    _tap_enter(dialog)
    dialog.answer_for_a_number_field()
    assert_true(dialog.visible, "Enter in Fuzziness's field leaves the dialog open")
    assert_eq(dialog.chosen_fuzziness(), 12.0, "having taken the number")
    assert_eq(_steps(), steps, "and records nothing")
    assert_eq(_doc.selection.bounds, BEFORE, "with the marquee as it was")
    dialog.hide()
