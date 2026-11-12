## A tool's own block reaches the dump, whatever it is called.
##
## A tool answers
## `ToolState.capture_report` with its blocks and the report merges what every
## registered tool says, so no file under `ui/` names a module class to
## photograph one. The dump then listed the blocks it wanted by name,
## `"crop": tools.get("crop", {})` and six more of the same shape, and a block
## under any other key was collected and thrown away. A patch tool answered a
## `patch` block that reached no capture, and a third-party tool was in the same
## position, which makes it a breach of hard rule 6 (built-ins go through the public door)
## rather than a missing line.
##
## The fix is a place for the rest rather than a merge over the top, so the seven
## named lines keep the places a reader diffing two runs walks down. The running
## app proves the wiring, in
## `scenarios/a-tools-own-dump-block-cannot-reach-the-dump.json`.
extends "res://tests/test_framework.gd"

const StateReport = preload("res://harness/report/sa_state_report.gd")


## A tool the skeleton has never heard of, answering a block under a name nothing
## in `ui/` mentions. Two blocks, because a tool may answer with more than one and
## the crop answers with none at all when it is not the active tool.
class StrangerTool:
    extends ToolState

    var _blocks: Dictionary = {}

    func _init(blocks: Dictionary) -> void:
        _blocks = blocks

    func capture_report(tool_name: StringName, active: bool) -> Dictionary:
        var out: Dictionary = {}
        for block_name: Variant in _blocks:
            out[block_name] = {"tool": String(tool_name), "active": active, "value": _blocks[block_name]}
        return out


## The defect itself, in the shape the dump meets it: a block whose name is not
## one of the seven survives, and the seven do not, because the dump reads those
## out on lines of their own.
func test_a_block_the_dump_does_not_name_is_the_one_that_is_kept() -> void:
    var blocks := {
        "crop": {"pending_rect": "kept by the crop line"},
        "patch": {"selection": true},
        "sparkle": {"from": "a module nobody here has heard of"},
    }

    var unnamed := StateReport._unnamed_tool_blocks(blocks)

    assert_eq(unnamed.keys(), ["patch", "sparkle"], "Everything the dump does not name by hand, in the order the tools answered")
    assert_false(unnamed.has("crop"), "and not the seven, which would then stand in the dump twice")
    assert_true(bool(unnamed["patch"]["selection"]), "The block arrives whole, not as its name")


## The other half of naming them: a tool that picks a name the run's own blocks
## already use is not silently dropped. `history` is the undo stack's block and
## has nothing to do with a tool, so a tool answering `history` belongs under
## `tools` rather than nowhere, which is what the list rather than `dump.has()`
## buys.
func test_a_tool_that_collides_with_a_run_block_still_arrives() -> void:
    var unnamed := StateReport._unnamed_tool_blocks({"history": {"mine": true}})
    assert_true(unnamed.has("history"), "A tool's `history` is kept, under `tools`, where it cannot be mistaken for the run's")


## Empty in, empty out, because a machine with no tool on it is what a dump taken
## before the canvas exists sees.
func test_no_tool_blocks_is_an_empty_block_rather_than_a_missing_one() -> void:
    assert_true(StateReport._unnamed_tool_blocks({}).is_empty(), "No blocks answered is an empty `tools`")


## End to end over a real machine: a tool nothing in the skeleton names is
## registered, and what a dump would carry has its block. The machine is asked
## rather than the window, which is the split that lets a suite do this
## without a canvas.
func test_a_registered_stranger_reaches_what_the_dump_would_carry() -> void:
    var machine := ToolMachine.new()
    machine.name = "ToolMachine"
    machine._ready()
    machine.register_tool(&"sparkler", StrangerTool.new({"sparkle": 7}))

    var blocks := StateReport._blocks_of(machine)
    var unnamed := StateReport._unnamed_tool_blocks(blocks)

    assert_true(unnamed.has("sparkle"), "The stranger's block is in what the dump would carry")
    assert_eq(String(unnamed["sparkle"]["tool"]), "sparkler", "under the name the machine registered it as")
    assert_true(bool(unnamed["sparkle"]["active"]), "and told it was the active tool, because it is the only one")

    machine.free()


## A machine that is not there answers nothing rather than throwing, because a
## dump is taken at moments when the canvas is not built yet.
func test_no_machine_answers_no_blocks() -> void:
    assert_true(StateReport._blocks_of(null).is_empty(), "No machine is no blocks")


## The list and the lines it is a list of, kept in step. Adding a
## `tools.get("x", {})` line without adding `x` here puts that block in the dump
## twice, and removing one without removing the name loses it, which is the same defect again.
func test_the_named_list_is_exactly_the_lines_the_dump_reads_by_hand() -> void:
    var source := FileAccess.get_file_as_string("res://harness/report/sa_state_report.gd")
    assert_false(source.is_empty(), "The report's own source is readable")

    var expression := RegEx.new()
    expression.compile('tools\\.get\\("([a-z_]+)"')
    var found: Array[String] = []
    for hit: RegExMatch in expression.search_all(source):
        found.append(hit.get_string(1))

    assert_eq(found, Array(StateReport.NAMED_TOOL_BLOCKS), "Every block read out by hand is named, in the order it is read")
