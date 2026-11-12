## What the pointer is while a note is being taken.
##
## The note box is an embedded window drawn over the canvas, and the canvas went
## on claiming the pointer underneath it: the brush ring was drawn behind the box
## with the OS cursor hidden for it, so a box dragged over the canvas left the
## painter with nothing to point with. The mode now overrules the tool for as
## long as it is on.
##
## Beside `test_note_mode.gd` rather than in it, because that suite is the
## headless half of the mode, the text an entry carries, and a machine needs a
## rendering device. `scenarios/note-cursor.json` is the proof on the running
## app, this is the part a suite can hold.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice, for the easel behind the surface.
const REQUIRES_GPU := true


func test_the_note_mode_takes_the_ring_off_the_tool() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var was := ToolMachine.pointer_holder

    machine.set_active_tool(&"brush")
    machine.refresh_cursor()
    assert_true(surface.cursor_ring_radius > 0.0, "The brush asks for a ring when nothing is being noted")

    ToolMachine.pointer_holder = SaNoteMode.POINTER_HOLDER
    machine.refresh_cursor()
    assert_true(surface.cursor_ring_radius < 0.0, "and asks for none while a note is being taken")

    ToolMachine.pointer_holder = &""
    machine.refresh_cursor()
    assert_true(surface.cursor_ring_radius > 0.0, "and gets it back when the mode closes")

    ToolMachine.pointer_holder = was
    Fixtures.teardown(surface, machine)


## The poll in `_process` is what would otherwise put the ring back a frame after
## the mode took it away, because it compares the tool's wanted radius against
## the one the surface carries. Both readings have to agree, or the OS cursor
## flickers for as long as the mode is on.
func test_the_polled_radius_agrees_with_the_published_one() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    var was := ToolMachine.pointer_holder

    machine.set_active_tool(&"brush")
    ToolMachine.pointer_holder = SaNoteMode.POINTER_HOLDER
    machine.refresh_cursor()
    assert_eq(machine._wanted_ring_radius(), surface.cursor_ring_radius, "The poll must not see a radius the publish did not")

    ToolMachine.pointer_holder = was
    Fixtures.teardown(surface, machine)


## The machine sits under `tools` and cannot name the mode, so
## the mode writes the machine's own member, and the flag the router reads moves
## with it.
func test_the_mode_writes_the_machines_member_and_clears_it() -> void:
    var was := ToolMachine.pointer_holder
    var mode := SaNoteMode.new()

    mode._hold_pointer(true)
    assert_eq(ToolMachine.pointer_holder, SaNoteMode.POINTER_HOLDER, "Entering names the mode as the pointer's holder")
    assert_eq(ToolMachine.pointer_holder_shape, SaNoteMode.CURSOR_SHAPE, "with the question mark as the shape to show")
    assert_true(SaNoteMode.taking_note, "and the router's flag says the same")

    mode._hold_pointer(false)
    assert_eq(ToolMachine.pointer_holder, &"", "Leaving hands the pointer back to the tool")
    assert_false(SaNoteMode.taking_note, "in both places")

    ToolMachine.pointer_holder = was
    mode.free()
