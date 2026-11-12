## The brush editor's blend row lists the modes the bar's does.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The report was that the blend mode dropdown in brush settings only has one
## option. Both halves of the finding are asserted here.
##
## **The cause** is an instance nobody handed the registry to: it holds no modes
## at all and shows `BlendModeButton.NO_MODES`, which is what a painter reads as
## a dropdown with nothing in it. It is not a registry that has not filled yet,
## which is the other possible cause and would have held some.
##
## **The fix** is the binding: the editor's instance lists what the bar's does,
## heading for heading and row for row, and shows the mode it stands for rather
## than the empty label. That is also why the row was neither hidden nor
## removed, which would be the answer if the list really was one mode.
##
## `scenarios/the-brushs-blend-mode-offers-one-mode.json` shoots the row on
## the running app, the panel before the fix and after.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StampModule = preload("res://modules/sara-base-modules/stamp-brush/module.gd")

## A bar and a brush editor both build controls for the brush's blend mode, and
## the blend modes' labels name the document's colour space.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_q6_presets")

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _bar: ToolOptionsBar = null

## The editors this suite built, freed when the test ends: a `Window` in the
## tree maps a real OS window, so these are built detached and released by hand
## the way `test_brush_editor_window.gd` releases its own.
var _windows: Array[SaBrushEditorWindow] = []


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _registries = Fixtures.make_registries(_surface)
    # The bar the way the app builds one, because the editor's binding is read
    # off a bar that has already been given the registry.
    _bar = ToolOptionsBar.new()
    _bar.target_tool_machine = _machine
    _bar._ready()
    _bar.bind_registries(_registries.blend_modes)


func after_each() -> void:
    for window: SaBrushEditorWindow in _windows:
        window.free()
    _windows.clear()
    _bar.free()
    _bar = null
    _registries = null
    ScratchFolder.clear(scratch_dir)
    Fixtures.teardown(_surface, _machine)


## The editor's window, bound the way the door binds it: the tool the bar shows
## and the specs it declares. *handed* is the door's second half, the registry
## and the document the bar's own button follows.
func _window(handed: bool = true) -> SaBrushEditorWindow:
    var tool := _machine.get_tool("brush")
    var specs: Array[SaOptionSpec] = []
    specs.assign(_machine.get_descriptor(&"brush").options)
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    var window := SaBrushEditorWindow.new()
    window.bind_tool(tool, specs, store)
    if handed:
        window.follow_blend_modes(_bar.options.binding.blend_registry, _bar._target_document())
    _windows.append(window)
    return window


## The editor's blend row: the page it is on is the one the row declares, and
## the control is found through the page's own controls rather than by node name.
func _editor_blend(window: SaBrushEditorWindow) -> BlendModeButton:
    window.show_page(window.pages.index_of(StampModule.GENERAL_PAGE))
    return window.pages.page_controls.control(ToolOptionControls.BLEND_KEY) as BlendModeButton


func _bar_blend() -> BlendModeButton:
    return _bar.control_for(ToolOptionsBar.BLEND_KEY) as BlendModeButton


# --- The cause ----------------------------------------------------------------


## The instance the note saw, before anything was handed to it. No modes at all,
## which is one option only in the sense that a row with nothing under it is.
func test_an_instance_nobody_bound_holds_no_modes() -> void:
    var button := _editor_blend(_window(false))
    assert_not_null(button, "the editor still builds the row")
    assert_eq(button.mode_ids().size(), 0, "an unbound instance lists nothing")
    assert_eq(button.text, BlendModeButton.NO_MODES, "and shows the label for having no modes")


## The bar's, which was never the one at fault: the registry's modes, more than
## one of them.
func test_the_bars_instance_lists_the_registry() -> void:
    var button := _bar_blend()
    assert_not_null(button, "the bar builds a blend row for the brush")
    assert_true(button.mode_ids().size() > 1, "not the one option the note saw")
    assert_eq(button.mode_ids().size(), _registries.blend_modes.list_ui_entries(true).size())


# --- The fix ------------------------------------------------------------------


## The comparison the Done asks for: the editor's instance lists what the bar's
## does, heading for heading and row for row.
func test_the_editors_row_lists_what_the_bars_does() -> void:
    var editor := _editor_blend(_window())
    var bar := _bar_blend()
    assert_not_null(editor, "the editor still builds the row")
    assert_eq(editor.mode_ids(), bar.mode_ids(), "the same modes in the same order")
    assert_eq(editor.section_titles(), bar.section_titles(), "under the same headings")
    for title: String in bar.section_titles():
        assert_eq(editor.section_labels(title), bar.section_labels(title), "and %s's rows are the bar's" % title)
        assert_eq(editor.section_ids(title), bar.section_ids(title), "down to the ids")


## And it shows the mode it stands for, with the document's space in plain
## Normal's label, rather than the label for having none.
func test_the_editors_row_shows_the_mode_the_bars_shows() -> void:
    var editor := _editor_blend(_window())
    var bar := _bar_blend()
    assert_eq(editor.current, bar.current, "the same mode is chosen")
    assert_eq(editor.text, bar.text, "and the same words are on the button")
    assert_true(editor.text != BlendModeButton.NO_MODES, "not the label for having no modes")


## The same list after a page is walked away from and back: the editor builds a
## fresh instance per page, so the binding has to be handed to every one of them
## and not only to the page that happened to be open when the window opened.
func test_a_page_built_later_is_handed_it_too() -> void:
    var window := _window()
    window.show_page(window.pages.index_of(StampModule.TIP_PAGE))
    var button := _editor_blend(window)
    assert_eq(button.mode_ids(), _bar_blend().mode_ids(), "the rebuilt instance lists the registry")


## The row kept its place. The note offered hiding or removing it if the list was
## genuinely one mode, and the finding is that it was not.
func test_the_row_was_not_hidden_or_removed() -> void:
    var spec := _blend_spec()
    assert_not_null(spec, "the brush still declares its blend row")
    assert_true(spec.in_editor, "and the editor still draws it")
    assert_false(spec.bar_hidden, "and the bar still keeps it")


func _blend_spec() -> SaOptionSpec:
    for spec: SaOptionSpec in StampModule.brush_options():
        if spec.key == ToolOptionControls.BLEND_KEY:
            return spec
    return null
