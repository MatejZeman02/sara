## The Presets button opens the docker, and so does a right click with the brush
## tool selected.
##
## The preset buttons open a separate window rather than a dropdown menu, so the
## grid that hung under the button in a
## `PopupPanel` is gone and the Brush Presets docker is the one place presets are
## picked, saved and deleted.
##
## The docker is a `Window`, so it is built detached under a plain Node the way
## `test_presets_docker.gd` builds one and its `_ready` never runs. What a
## painter sees, and that a real right press reaches it, is
## `scenarios/presets-button-opens-the-docker.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const DockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")

const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_d8_presets")


func before_each() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch_dir))


func after_each() -> void:
    var dir := DirAccess.open(scratch_dir)
    if dir != null:
        for file in dir.get_files():
            dir.remove(file)


## The bar's popup is gone, whole: no grid, no panel, and no opener named after
## one. What the button presses now is a docker.
func test_the_bar_keeps_no_grid_of_its_own() -> void:
    var box := ToolOptionsPresets.new()

    assert_false("chooser" in box, "no grid on the bar")
    assert_false("chooser_popup" in box, "no popup to put one in")
    assert_false("save_button" in box, "and neither of the two actions under it")
    assert_false("delete_button" in box, "which went to the docker with the grid")
    assert_true(box.has_method("open_presets_docker"), "The button opens the docker instead")
    assert_false(box.has_method("open_chooser"), "and the opener named after the popup went with it")

    box.free()


## The two actions came with the grid, and they press the same ids the popup's
## own buttons pressed: the id is the programmatic door and a chord, a capture
## and a button all take one path through it.
func test_the_docker_carries_save_and_delete() -> void:
    var host := Node.new()
    var docker := DockerScript.new()
    host.add_child(docker)

    assert_not_null(docker.save_button, "Save as... is under the grid")
    assert_not_null(docker.delete_button, "and so is Delete")
    assert_eq(docker.save_button.name, StringName("ChooserSave"), "under the names the popup gave them")
    assert_eq(docker.delete_button.name, StringName("ChooserDelete"), "so a capture that named one still finds it")
    assert_true(docker.find_child("ChooserFooter", true, false).is_ancestor_of(docker.save_button), "under the grid")

    # With no bar to ask, both are dead rather than half working, which is the
    # answer `test_presets_docker.gd` pins for every other question.
    docker.sync_actions()
    assert_true(docker.save_button.disabled, "With no bar there is nothing to save from")
    assert_true(docker.delete_button.disabled, "and nothing to delete")

    var state: Dictionary = docker.capture_state()
    assert_true(bool(state["save_disabled"]), "which the dump says out loud")
    assert_true(bool(state["delete_disabled"]), "for both of them")

    host.free()


## Delete is dead with nothing loaded. The rule rather than the button, because
## the bar runs in three hosts that have no docker: a test, the info docker's
## scratchpad and the brush editor's.
func test_delete_is_dead_until_a_preset_is_loaded() -> void:
    var box := ToolOptionsPresets.new()

    # Save as... reads the tool the surface shows rather than a button, and this
    # box has no tool at all, so it is dead here for the same reason Delete is.
    # It is offered whenever a tool of some engine is in front of the painter,
    # which is `test_a_tool_that_takes_no_presets.gd`'s claim.
    assert_false(box.action_available(ToolOptionsPresets.PRESET_ID_SAVE), "Nothing takes a preset with no tool")
    assert_false(box.action_available(ToolOptionsPresets.PRESET_ID_DELETE), "Delete needs something to delete")

    box.free()


## With no docker in the tree the button says so rather than half opening one,
## which is what every host but the main window gets.
func test_a_bar_with_no_docker_says_so() -> void:
    var host := Node.new()
    EventBus.add_child(host)
    var box := ToolOptionsPresets.new()
    host.add_child(box)

    assert_false(box.open_presets_docker(), "Nothing to open")

    host.free()


## A right click with the brush reaches the docker, and with any other tool it
## reaches the context menu it always did.
##
## The brush therefore has no context menu, which is the cost of decision 9's
## answer rather than an oversight: taking the branch out is what gives it back.
func test_a_right_click_asks_the_brush_for_presets_and_everything_else_for_the_menu() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)

    var asked: Array = []
    machine.context_menu_requested.connect(func(at: Vector2) -> void: asked.append(at))

    machine.set_active_tool(&"eyedropper")
    machine.handle_input(_right_press())
    assert_eq(asked.size(), 1, "Another tool asks for its context menu")

    machine.set_active_tool(&"brush")
    machine.handle_input(_right_press())
    # No docker in this host, so `reveal` finds nothing and the menu is the
    # fallback: what is asserted is the branch, not that a docker appeared.
    assert_eq(asked.size(), 2, "and the brush falls back to it when there is no docker to open")

    Fixtures.teardown(surface, machine)


## A modified right press belongs to whatever reads the modifier: the ALT right
## drag resizes the brush and must not open a docker on the way.
func test_a_modified_right_press_opens_nothing() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)

    var asked: Array = []
    machine.context_menu_requested.connect(func(at: Vector2) -> void: asked.append(at))

    machine.set_active_tool(&"brush")
    for modifier: String in ["alt_pressed", "ctrl_pressed", "shift_pressed"]:
        var event := _right_press()
        event.set(modifier, true)
        machine.handle_input(event)
    assert_eq(asked.size(), 0, "None of the three asks for anything")

    Fixtures.teardown(surface, machine)


## A plain right press at the middle of the canvas.
func _right_press() -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_RIGHT
    event.pressed = true
    event.position = Vector2(100, 100)
    event.global_position = Vector2(100, 100)
    return event
