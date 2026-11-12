## Escape puts a transform back, through the hop nobody asserted.
##
## Pressing Escape after a drag must put the pixels back. Two halves of the path
## are pinned elsewhere and the join between them is pinned here: `test_escape_no_longer_quits` in
## `ui/shortcuts/tests/test_shortcut_router.gd` says the router is not the one taking the key,
## and `test_escape_puts_the_pixels_back` in `tests/test_transform_move.gd` says
## `SaTransform` restores when it is asked. What is asserted here is that
## `ToolMachine.handle_key_event` passes Escape on to the active tool, which is
## the only door either Enter or Escape has: the canvas takes no focus, so no
## `gui_input` reaches a tool.
##
## The picture is `scenarios/escape-puts-transform-back.json`, where the post-Escape shot
## differs from the pre-drag shot by two pixels of the walking outline and
## nothing else.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


func _key(keycode: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = true
    return event


## A transform tool over a selection, dragged by 200 by 100 and let go, which is
## the state under test: moved, not committed.
func _dragged() -> Array:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var machine := Fixtures.make_bound_machine(surface)
    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i(1, 1))
    document.selection.select_rect(Rect2i(400, 384, 500, 400))
    machine.set_active_tool(&"transform")
    var tool := machine.active_tool
    surface.view.mouse_position = Vector2(650, 584)
    tool.handle_input(_button(true))
    surface.view.mouse_position = Vector2(850, 684)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    return [surface, machine, tool]


## The hop. Escape given to the machine reaches the tool and puts the move back,
## and the machine does not consume it, so a chord that happens to be Escape
## still travels.
func test_the_machine_passes_escape_to_the_tool_that_is_moving() -> void:
    var parts := _dragged()
    var machine: ToolMachine = parts[1]
    var tool: StateTransformScript = parts[2]
    assert_true(tool.is_moving(), "The piece is in the air before the key")

    var consumed: bool = machine.handle_key_event(_key(KEY_ESCAPE))

    assert_false(tool.is_moving(), "Escape through the machine puts it back")
    assert_eq(tool.pending_box(), Rect2i(400, 384, 500, 400), "and the box is the selection's own again")
    assert_false(consumed, "The machine reports it did not consume the key")
    Fixtures.teardown(parts[0], parts[1])


## Enter is the only commit, which is the other half of the claim: Escape must not
## bake and nothing else may either.
func test_enter_through_the_machine_is_what_commits() -> void:
    var parts := _dragged()
    var machine: ToolMachine = parts[1]
    var tool: StateTransformScript = parts[2]

    machine.handle_key_event(_key(KEY_ENTER))

    assert_false(tool.is_moving(), "Enter puts the piece down")
    # 424 wide rather than 500: the box lands at x 600 on a 1024 wide canvas, so
    # the commit clips it to what is left, which is what a commit should do.
    assert_eq(tool.pending_box(), Rect2i(600, 484, 424, 400), "where the drag left it, which Escape would not have")
    Fixtures.teardown(parts[0], parts[1])


## Switching tools puts the move back rather than committing, which the state's
## own header promises and which the scenario photographs.
func test_switching_tools_puts_the_move_back() -> void:
    var parts := _dragged()
    var machine: ToolMachine = parts[1]
    var tool: StateTransformScript = parts[2]
    assert_true(tool.is_moving(), "in the air")

    machine.set_active_tool(&"brush")

    assert_false(tool.is_moving(), "and a tool change puts it down where it came from")
    assert_eq(tool.pending_box(), Rect2i(400, 384, 500, 400), "rather than where the drag left it")
    Fixtures.teardown(parts[0], parts[1])
