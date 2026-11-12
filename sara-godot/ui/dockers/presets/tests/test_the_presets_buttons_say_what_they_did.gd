## Save as..., Delete and New preset each say what they did, in the Brush Presets
## docker where they were pressed.
##
## Pressing the three with the shipped Canvas Brush loaded once showed nothing: no
## field, no question and the bar still on Canvas Brush. The scenario
## `scenarios/save-as-delete-and-new-preset-say-what-they-did.json` shows
## why. The buttons were the last rows of the scroll the docker holds its grid
## in, 3,400 pixels below its top with 52 presets, so the clicks landed on the
## Tool Options docker's sliders under it. They are pinned under the scroll now,
## Save as... opens a field of the docker's own rather than the bar's, and a line
## over them says what each did.
##
## Driven through the docker's own handlers with a real bar and a real store in
## the tree, the shape `test_a_preset_delete_asks_first.gd` builds, because the
## docker finds the bar by searching the tree.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const DockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")

const REQUIRES_GPU := true

const LOADED := "Press Loaded"

static var scratch_dir: String = SaDataRoot.path("test_n126_presets_buttons")


func before_each() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch_dir))


func after_each() -> void:
    var dir := DirAccess.open(scratch_dir)
    if dir != null:
        for file in dir.get_files():
            dir.remove(file)


func test_the_three_buttons_sit_under_the_scroll_rather_than_at_its_foot() -> void:
    var built := _build()
    if built.is_empty():
        return
    var docker: BrushPresetsDocker = built["docker"]

    var scroll := docker.find_child("Scroll", true, false)
    assert_not_null(scroll, "The grid is still in a scroll")
    for button: Button in [docker.new_button, docker.save_button, docker.delete_button]:
        assert_false(scroll.is_ancestor_of(button), "%s is outside it, so no grid is long enough to hide it" % button.name)
        assert_true(docker.find_child("ChooserFooter", true, false).is_ancestor_of(button), "and in the footer under it")
    var actions := docker.save_button.get_parent()
    assert_true(docker.said_line.get_index() < actions.get_index(), "The line is above Save as... and Delete")
    assert_true(docker.name_row.get_index() < actions.get_index(), "and so is the field, so neither moves a pressed button")
    assert_eq(actions.get_index(), actions.get_parent().get_child_count() - 1, "which are the footer's last row")
    assert_true(scroll.is_ancestor_of(docker.chooser), "The grid is what scrolls")
    assert_true(scroll.is_ancestor_of(docker.provenance_line), "with the line about its loaded preset under it")
    _tear_down(built)


func test_save_as_shows_the_dockers_own_field_prefilled_with_the_loaded_name() -> void:
    var built := _build()
    if built.is_empty():
        return
    var docker: BrushPresetsDocker = built["docker"]
    var bar: ToolOptionsBar = built["bar"]

    assert_false(docker.name_row.visible, "The field is hidden until Save as... is pressed")
    docker._on_save_pressed()
    assert_true(docker.name_row.visible, "Save as... shows the docker's field")
    assert_eq(docker.name_field.text, LOADED, "prefilled with the loaded preset's name, so saving over it is a Return")
    assert_false(bar.preset_box.preset_name_edit.visible, "and the bar's field stays shut, the press being answered here")
    assert_true(bar.preset_box.preset_menu.visible, "with the bar's button where it was")

    var state: Dictionary = docker.capture_state()
    assert_true(bool(state["naming"]), "The dump says the field is open")
    assert_eq(String(state["name_text"]), LOADED, "and what it holds")
    _tear_down(built)


func test_a_shut_docker_opens_no_field() -> void:
    var built := _build()
    if built.is_empty():
        return
    var docker: BrushPresetsDocker = built["docker"]

    docker.hide()
    assert_false(docker.open_name_field(), "A docker nobody can see asks nothing")
    assert_false(docker.name_row.visible, "and its field stays shut")

    docker.show()
    docker._on_save_pressed()
    docker.hide()
    assert_false(docker.name_row.visible, "A field left open goes with the docker")
    _tear_down(built)


func test_the_field_writes_through_the_bars_save_and_says_so() -> void:
    var built := _build()
    if built.is_empty():
        return
    var docker: BrushPresetsDocker = built["docker"]
    var bar: ToolOptionsBar = built["bar"]

    docker._on_save_pressed()
    docker.name_field.text = "Press Copy"
    docker.name_field.text_submitted.emit(docker.name_field.text)

    assert_true(bar.preset_names().has("Press Copy"), "Return writes the preset")
    assert_eq(bar.selected_preset_name(), "Press Copy", "and loads it, as the bar's field does")
    var tip := bar.preset_box.preset_menu.tooltip_text
    assert_eq(tip, "Press Copy. Shows or hides Brush Presets.", "so the bar's button names it in its tooltip")
    assert_false(docker.name_row.visible, "The field goes away")
    assert_true(docker.said_line.visible, "and the line over the buttons says what happened")
    assert_eq(docker.said_line.text, "Saved 'Press Copy'.", "in the preset's stored name")
    _tear_down(built)


func test_a_name_that_is_nothing_keeps_the_field_and_asks_for_one() -> void:
    var built := _build()
    if built.is_empty():
        return
    var docker: BrushPresetsDocker = built["docker"]
    var bar: ToolOptionsBar = built["bar"]
    var before := bar.preset_names().size()

    docker._on_save_pressed()
    assert_eq(docker.save_named("  ..  "), "", "A name of dots and spaces writes nothing")
    assert_eq(bar.preset_names().size(), before, "and no file appears")
    assert_true(docker.name_row.visible, "The field stays open for a name")
    assert_eq(docker.said_line.text, "A preset needs a name.", "and the line asks for one")
    _tear_down(built)


func test_escape_and_a_lost_keyboard_both_put_the_field_away_unsaved() -> void:
    var built := _build()
    if built.is_empty():
        return
    var docker: BrushPresetsDocker = built["docker"]
    var bar: ToolOptionsBar = built["bar"]

    docker._on_save_pressed()
    docker.name_field.text = "Press Never"
    var escape := InputEventKey.new()
    escape.keycode = KEY_ESCAPE
    escape.physical_keycode = KEY_ESCAPE
    escape.pressed = true
    docker._on_name_gui_input(escape)
    assert_false(docker.name_row.visible, "Escape that reaches the field closes it")

    # The router lets go of a focused text box on Escape before the box hears
    # the key, so in the app the close arrives as the focus leaving.
    docker._on_save_pressed()
    docker.name_field.focus_exited.emit()
    assert_false(docker.name_row.visible, "and so does the field losing the keyboard")
    assert_false(bar.preset_names().has("Press Never"), "Neither saves what was typed")
    _tear_down(built)


func test_deletes_tooltip_follows_the_loaded_preset_and_says_why_when_dimmed() -> void:
    var built := _build()
    if built.is_empty():
        return
    var docker: BrushPresetsDocker = built["docker"]
    var bar: ToolOptionsBar = built["bar"]

    assert_false(docker.delete_button.disabled, "Delete is live with a preset loaded")
    assert_eq(docker.delete_button.tooltip_text, "Delete 'Press Loaded' for good.", "and its tooltip names that preset")

    bar.save_current_as_preset("Press Other")
    bar.load_preset("Press Other")
    assert_eq(docker.delete_button.tooltip_text, "Delete 'Press Other' for good.", "A load moves the name with it")

    # The bar's own New, the defaults with no preset loaded, since the docker's
    # button opens New preset...
    bar.preset_box.new_preset()
    assert_true(docker.delete_button.disabled, "With nothing loaded Delete is dimmed")
    assert_eq(
        docker.delete_button.tooltip_text,
        "No preset is loaded, so there is nothing to delete. Select one in the grid first.",
        "and its tooltip says why"
    )
    _tear_down(built)


func test_save_as_says_what_it_will_do() -> void:
    var built := _build()
    if built.is_empty():
        return
    var docker: BrushPresetsDocker = built["docker"]

    assert_eq(
        docker.save_button.tooltip_text,
        "Save the brush as a new preset, or over this one under its name.",
        "Save as... carries the tooltip it was once without"
    )
    _tear_down(built)


## New preset... opens a dialog, and until Create the bar
## stays on the preset in hand: the press is answered by the window it opens.
func test_new_preset_opens_the_dialog_and_leaves_the_bar_on_the_loaded_preset() -> void:
    var built := _build()
    if built.is_empty():
        return
    var docker: BrushPresetsDocker = built["docker"]
    var bar: ToolOptionsBar = built["bar"]

    docker._on_new_pressed()
    var dialog := bar.preset_box.get_node_or_null(SaNewPresetDialog.NODE_NAME) as SaNewPresetDialog
    assert_not_null(dialog, "New preset... builds the dialog on the bar's preset group")
    assert_true(dialog.visible, "and opens it")
    assert_eq(bar.selected_preset_name(), LOADED, "The bar keeps the preset in hand")
    var tip := bar.preset_box.preset_menu.tooltip_text
    assert_eq(tip, "%s. Shows or hides Brush Presets." % LOADED, "and its button names it in its tooltip")
    assert_true(bool(docker.capture_state()["new_dialog"]["open"]), "which the dump reads beside the docker's own state")
    dialog.hide()
    _tear_down(built)


func test_a_delete_answered_says_what_went() -> void:
    var built := _build()
    if built.is_empty():
        return
    var docker: BrushPresetsDocker = built["docker"]
    var bar: ToolOptionsBar = built["bar"]

    docker._on_delete_answered(DockerScript.DELETE_CONFIRM, LOADED)
    assert_false(bar.preset_names().has(LOADED), "The answer deletes")
    assert_eq(docker.said_line.text, "Deleted 'Press Loaded'", "and the line over the buttons names what went")
    _tear_down(built)


## A docker, a bar with a store of its own, and one preset saved and loaded.
func _build() -> Dictionary:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This suite needs the real scene tree, which the docker searches for the bar")
    if tree == null:
        return {}

    var embedded: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "PresetsButtonsHost"
    EventBus.add_child(host)

    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")

    var bar := ToolOptionsBar.new()
    host.add_child(bar)
    bar.target_tool_machine = machine
    bar.preset_store.dir = scratch_dir
    bar._ready()
    bar.save_current_as_preset(LOADED)
    bar.load_preset(LOADED)

    var docker := DockerScript.new()
    host.add_child(docker)
    docker.show()
    docker.rebind()

    return {
        "tree": tree, "host": host, "bar": bar, "docker": docker, "surface": surface, "machine": machine, "embedded": embedded
    }


func _tear_down(built: Dictionary) -> void:
    var tree: SceneTree = built["tree"]
    var left := SaMessage.live_dialog(tree)
    if left != null:
        left.queue_free()
    (built["host"] as Node).free()
    Fixtures.teardown(built["surface"], built["machine"])
    tree.root.gui_embed_subwindows = bool(built["embedded"])
