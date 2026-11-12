## The toolbox report carries each button's tooltip, chord and all.
##
## A tooltip is the one thing neither a shot nor a dump could show, so the rule
## that a tool's name is drawn with its shortcut in brackets sat ungraded
## while `_tooltip_for` had been composing exactly
## that since it was written. `toolbox_report` gave every button its name, its
## rect, its category, its face, its members and its flyout mark, and no tooltip,
## and `probe` had none either, so there was no route to one from a run at all.
##
## The report composes the text through `_button_tooltip` rather than reading
## the button's own `tooltip_text`, which is the half `_refresh_tooltip` exists
## for: the stored text is rebuilt on hover and on a rebuild, so after a rebind
## it is stale until a pointer visits the button, and a dump has no pointer.
##
## A grouped button's tooltip goes on to name the tools a right press opens
## as well, so the chord is graded as the text's opening, before
## the full stop that sentence starts after.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")

## The tool whose chord this grades. Its category holds more than one tool, so
## the button it is drawn on is a face rather than a plain button, which is the
## harder of the two cases.
const PAINT := "brush"


func _toolbox() -> ToolBoxDocker:
    var docker := ToolBoxDockerScript.new() as ToolBoxDocker
    docker.name = "ToolBoxDocker"
    docker.rebuild_from_registry(Fixtures.make_tool_registry())
    return docker


## The button entry of *report* whose category draws *tool_id*, or an empty
## dictionary. By category rather than by index, because the grid's order is the
## registry's and a tool moving category must not silently regrade this.
func _entry_for(docker: ToolBoxDocker, report: Dictionary, tool_id: String) -> Dictionary:
    var button := docker.button_for_tool(tool_id)
    if button == null:
        return {}
    for entry: Dictionary in report.get("buttons", []):
        if String(entry.get("name", "")) == String(button.name):
            return entry
    return {}


## The face and its chord, which is the tooltip up to the full stop a grouped
## button's sentence about its flyout starts after.
static func _face_of(tooltip: String) -> String:
    return tooltip.get_slice(". ", 0)


func test_every_button_in_the_report_carries_a_tooltip() -> void:
    var docker := _toolbox()
    var report := docker.toolbox_report()

    assert_true(report.get("present", false), "the report is about a built docker")
    var buttons: Array = report.get("buttons", [])
    assert_true(buttons.size() > 0, "and it drew some buttons")
    for entry: Dictionary in buttons:
        assert_true(entry.has("tooltip"), "%s carries a tooltip key" % entry.get("name", "?"))
        assert_true(String(entry["tooltip"]) != "", "%s's tooltip says something" % entry.get("name", "?"))
    docker.free()


func test_the_tooltip_is_the_tool_name_with_its_chord_in_brackets() -> void:
    var docker := _toolbox()
    var descriptor := Fixtures.make_tool_registry().get_descriptor(StringName(PAINT))
    var action := descriptor.activate_action
    assert_true(InputMap.has_action(action), "the paint tool has an activate action to read")

    var entry := _entry_for(docker, docker.toolbox_report(), PAINT)
    var chord := SaCommandRegistry.format_events(InputMap.action_get_events(action), 1)
    var face := _face_of(String(entry.get("tooltip", "")))
    assert_eq(face, "%s (%s)" % [descriptor.display_name, chord], "name, then the chord in brackets")
    assert_true(chord != "", "and the chord is a key rather than nothing, which is what makes the brackets worth reading")
    docker.free()


func test_a_rebind_moves_the_reported_tooltip_without_a_pointer() -> void:
    ## The half `_refresh_tooltip` exists for, read from a dump instead of from a
    ## hover. A report that read `tooltip_text` off the button would answer with
    ## the old chord here, because nothing has entered the button since.
    var docker := _toolbox()
    var action := Fixtures.make_tool_registry().get_descriptor(StringName(PAINT)).activate_action
    var before: Array[InputEvent] = InputMap.action_get_events(action)
    var was := String(_entry_for(docker, docker.toolbox_report(), PAINT).get("tooltip", ""))

    var rebound := InputEventKey.new()
    rebound.physical_keycode = KEY_F9
    InputMap.action_erase_events(action)
    InputMap.action_add_event(action, rebound)
    var now := String(_entry_for(docker, docker.toolbox_report(), PAINT).get("tooltip", ""))

    InputMap.action_erase_events(action)
    for event: InputEvent in before:
        InputMap.action_add_event(action, event)

    assert_true(now != was, "the reported tooltip followed the rebind")
    assert_true(_face_of(now).ends_with("(F9)"), "and it reads the new chord: %s" % now)
    docker.free()


func test_a_tool_with_no_action_reads_its_name_alone() -> void:
    ## Brackets with nothing in them would read as a tool whose chord is unset,
    ## which is the wrong claim about a tool that never asked for one.
    var docker := _toolbox()
    var descriptor := Fixtures.make_tool_registry().get_descriptor(StringName(PAINT))
    var action := descriptor.activate_action
    var before: Array[InputEvent] = InputMap.action_get_events(action)

    InputMap.action_erase_events(action)
    var bare := String(_entry_for(docker, docker.toolbox_report(), PAINT).get("tooltip", ""))

    InputMap.action_erase_events(action)
    for event: InputEvent in before:
        InputMap.action_add_event(action, event)

    assert_eq(_face_of(bare), descriptor.display_name, "no chord, no brackets")
    docker.free()
