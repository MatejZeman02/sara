## The bar's preset button shows the whole name and reads as the toggle it
## is.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A button 96 units wide whatever it held cut a name to "Inked P", and a
## dropdown arrow promises a list where a press toggles the Brush Presets
## docker instead.
##
## The docker is a real one in the tree, with `gui_embed_subwindows` on, the way
## `test_a_second_right_press_closes_the_presets.gd` holds one, and the Window
## menu row and the chord are `MainDockers` and the command registry built over
## it, so all three doors are the app's own. What a painter sees is
## `scenarios/the-bars-preset-button-shows-the-whole-name-and-reads-as-the-toggle-it-is.json`.
##
## The name is not on the label, which is named for the presets rather than the
## active brush, so the whole name is read in the tooltip and the label stands
## still. A painter reads the name whole rather than "Inked P", and the button
## never changes width under the pointer while presets are picked.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const DockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")

## The docker draws its tiles by driving a brush, which needs a device.
const REQUIRES_GPU := true

const LONG_NAME := "Canvas Brush With Rather A Lot To Say About Itself"


## The answers `MainDockers` asks of the layout store when a row is pressed,
## stubbed so a press writes no layout file. The same stub
## `test_dockers_under_window.gd` builds.
class StubStore:
    extends DockerLayoutStore

    func save(_by_painter: bool = false) -> void:
        pass

    func fork_for_painter_edit() -> String:
        return ""

    func reapply_deferred(_win: Window, _section: String) -> void:
        pass

    func list_presets() -> Array[String]:
        return []

    func current_preset() -> String:
        return ""


# --- The name -----------------------------------------------------------------


## The two names are read whole in the tooltip, and the label says
## what a press opens whichever of them is loaded. The button asks for that
## label's width and the box around it, so the theme's cut never has to end it
## in a mark.
##
## The custom minimum is read rather than the combined one, because a control
## outside the tree never refreshes the combined size it cached.
func test_inked_pen_and_canvas_brush_are_read_whole() -> void:
    var presets := ToolOptionsPresets.new()
    for preset_name: String in ["Inked Pen", "Canvas Brush"]:
        presets.selected_preset = preset_name
        presets.sync_menu()
        var label := presets.preset_menu.text
        assert_eq(label, ToolOptionsPresets.PRESET_LABEL, "The button says Presets with %s loaded" % preset_name)
        assert_eq(
            presets.preset_menu.tooltip_text,
            "%s. Shows or hides Brush Presets." % preset_name,
            "and the tooltip carries %s whole" % preset_name,
        )
        var wide := presets.preset_menu.custom_minimum_size.x
        assert_true(
            wide >= _needs(presets.preset_menu),
            "and the button is wide enough for its label, %.0f for %.0f" % [wide, _needs(presets.preset_menu)],
        )
        assert_true(
            presets.preset_menu.custom_minimum_size.x < DockerUtils.px(ToolOptionsPresets.PRESET_CAP),
            "short of the cap, which is there for a long word in another language"
        )
    presets.free()


## The width is the label's, so a preset that is picked moves nothing else on
## the bar, which a name of its own did every time one was loaded.
func test_the_button_keeps_one_width_whatever_the_name() -> void:
    var presets := ToolOptionsPresets.new()
    presets.selected_preset = "Canvas Brush"
    presets.sync_menu()
    var wide := presets.preset_menu.custom_minimum_size.x
    presets.selected_preset = "Ink"
    presets.sync_menu()
    assert_eq(presets.preset_menu.custom_minimum_size.x, wide, "Ink takes exactly what Canvas Brush took")
    presets.selected_preset = ""
    presets.sync_menu()
    assert_eq(presets.preset_menu.custom_minimum_size.x, wide, "and so does no preset at all")
    presets.free()


## A name far past the cap leaves the button where it was, with the whole of it
## in the tooltip beside what a press does.
func test_a_name_past_the_cap_leaves_the_button_alone_and_is_whole_in_the_tooltip() -> void:
    var presets := ToolOptionsPresets.new()
    presets.selected_preset = LONG_NAME
    presets.sync_menu()
    assert_true(
        presets.preset_menu.custom_minimum_size.x < float(DockerUtils.px(ToolOptionsPresets.PRESET_CAP)),
        "The button is its label's width, short of the cap, however long the name is"
    )
    assert_true(_needs(presets.preset_menu) <= presets.preset_menu.custom_minimum_size.x, "so nothing on it is cut")
    var cut := presets.preset_menu.text_overrun_behavior
    assert_eq(cut, SaTheme.TEXT_CUT, "and a label that did not fit would be cut as every cut name is")
    assert_eq(
        presets.preset_menu.tooltip_text,
        "%s. Shows or hides Brush Presets." % LONG_NAME,
        "The tooltip names the preset and the job",
    )
    presets.free()


## The tooltip, word for word.
func test_the_tooltip_names_the_preset_and_the_job() -> void:
    var presets := ToolOptionsPresets.new()
    presets.selected_preset = "Inked Pen"
    presets.sync_menu()
    assert_eq(presets.preset_menu.tooltip_text, "Inked Pen. Shows or hides Brush Presets.", "The tooltip of the ask")
    presets.free()


# --- The toggle ---------------------------------------------------------------


## No arrow, and the toggle's boxes rather than the dropdown's.
func test_the_button_draws_no_arrow_and_is_a_toggle() -> void:
    var presets := ToolOptionsPresets.new()
    assert_null(presets.preset_menu.icon, "No arrow, because a press opens no list")
    assert_true(presets.preset_menu.toggle_mode, "A toggle")
    var pressed := presets.preset_menu.get_theme_stylebox(&"pressed") as StyleBoxFlat
    var expected := SaTheme.make_toggle_style("pressed")
    assert_not_null(pressed, "with a pressed box of its own")
    if pressed != null:
        assert_eq(pressed.bg_color, expected.bg_color, "and it is the toggle's, the accent")
    presets.free()


## Pressed exactly while the docker is open, whichever of the three doors moved
## it: the button, the Window menu row and the chord.
func test_the_button_is_pressed_exactly_while_the_docker_is_open() -> void:
    var built := _build()
    if built.is_empty():
        return
    var presets: ToolOptionsPresets = built["presets"]
    var docker: Window = built["docker"]
    var dockers: MainDockers = built["dockers"]
    var commands: SaCommandRegistry = built["commands"]
    var button := presets.preset_menu

    assert_false(docker.visible, "The docker starts shut")
    assert_false(button.button_pressed, "and the button released")

    _click(button)
    assert_true(docker.visible, "The button opens it")
    assert_true(button.button_pressed, "and reads pressed")
    _click(button)
    assert_false(docker.visible, "The button closes it")
    assert_false(button.button_pressed, "and reads released")

    dockers.toggle_docker_by_id(SaDockerIds.BRUSH_PRESETS)
    assert_true(docker.visible, "The Window menu row opens it")
    assert_true(button.button_pressed, "and the button follows")
    dockers.toggle_docker_by_id(SaDockerIds.BRUSH_PRESETS)
    assert_false(docker.visible, "The Window menu row closes it")
    assert_false(button.button_pressed, "and the button follows")

    assert_true(commands.execute(&"docker_brush_presets"), "The chord's command runs")
    assert_true(docker.visible, "and opens it")
    assert_true(button.button_pressed, "and the button follows")
    commands.execute(&"docker_brush_presets")
    assert_false(docker.visible, "The chord closes it")
    assert_false(button.button_pressed, "and the button follows")

    _click(button)
    docker.hide()
    assert_false(button.button_pressed, "A docker shut by its own close releases the button too")

    _tear_down(built)


## A press with no docker to open leaves the button released rather than
## claiming a window that is not there.
func test_a_press_with_no_docker_leaves_the_button_released() -> void:
    var host := Node.new()
    EventBus.add_child(host)
    var presets := ToolOptionsPresets.new()
    host.add_child(presets)
    _click(presets.preset_menu)
    assert_false(presets.preset_menu.button_pressed, "Nothing opened, so nothing reads pressed")
    host.free()


# --- Helpers ------------------------------------------------------------------


## The width the button's label and box ask for, measured the way it draws.
func _needs(button: Button) -> float:
    var font := button.get_theme_font(&"font")
    var text := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size(&"font_size")).x
    return text + button.get_theme_stylebox(&"normal").get_minimum_size().x


## What a click does to a toggle button: it flips, then says it was pressed.
func _click(button: Button) -> void:
    button.set_pressed_no_signal(not button.button_pressed)
    button.pressed.emit()


## A real docker, `MainDockers` over it and the app's commands bound to that,
## and the preset group, all under an autoload: the runner calls a test from its
## own `_ready` and a parent mid-`_ready` rejects `add_child`
func _build() -> Dictionary:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This suite needs the real scene tree, because the button looks for the docker under its root")
    if tree == null:
        return {}
    var embedded: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "N34PresetToggleHost"
    EventBus.add_child(host)

    var docker := DockerScript.new()
    host.add_child(docker)
    # A `Window` is visible when it is built, and every door here starts from a
    # shut docker.
    docker.hide()

    var registries := Fixtures.make_registries()
    var factory := func() -> Window: return DockerScript.new()
    registries.ui.register_docker(SaDockerIds.BRUSH_PRESETS, "Brush Presets", factory, &"docker_brush_presets")
    registries.ui.set_docker_node(SaDockerIds.BRUSH_PRESETS, docker)
    var dockers := MainDockers.new(registries.ui, StubStore.new())
    host.add_child(dockers)
    SaAppCommands.register_all(registries, dockers.toggle_docker_by_id)

    var presets := ToolOptionsPresets.new()
    host.add_child(presets)
    # What `_ready` defers, done now so the test does not wait a frame.
    presets.sync_menu()

    return {
        "tree": tree,
        "host": host,
        "docker": docker,
        "dockers": dockers,
        "commands": registries.commands,
        "presets": presets,
        "embedded": embedded,
    }


func _tear_down(built: Dictionary) -> void:
    (built["host"] as Node).free()
    (built["tree"] as SceneTree).root.gui_embed_subwindows = bool(built["embedded"])
