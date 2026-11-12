## An action row in the Tool Options docker says its name once.
##
## `CropApplyRow` once said the same text twice: a label column reading "Crop"
## beside a button reading "Crop". The
## label column is gone from an action row, which is the shape
## `ui/brush_editor/page_layout.gd` and `ui/page/sa_page_build.gd` had already
## settled on for the same specs.
##
## The sweep is over every registered tool rather than over the crop, because
## five action specs are declared across three tools and the crop is only
## one of them. A pair that matches fails here whichever tool declares
## it, including one a module adds later.
##
## The docker is a Window, so it is built detached under a plain Node and its
## `_ready` never runs, which is what `test_tool_options_docker.gd` does and why.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A surface builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true


## A docker with every tool's rows built, Advanced Options on so a row hidden
## behind that flag is built too.
class Rows:
    var surface: SaSurface
    var machine: ToolMachine
    var host: Node
    var docker: ToolOptionsDocker
    var advanced: bool

    func _init() -> void:
        surface = Fixtures.make_surface()
        machine = Fixtures.make_bound_machine(surface)
        advanced = SaSettings.advanced_options
        SaSettings.advanced_options = true
        host = Node.new()
        docker = ToolOptionsDocker.new()
        host.add_child(docker)
        docker.target_tool_machine = machine

    func close() -> void:
        host.free()
        Fixtures.teardown(surface, machine)
        SaSettings.advanced_options = advanced

    ## Every ACTION spec of every registered tool, each with the tool that
    ## declares it, so a failure names both.
    func actions() -> Array:
        var out: Array = []
        for descriptor: SaToolDescriptor in machine.registry.list_descriptors():
            machine.set_active_tool(descriptor.id)
            docker.sync_from_tool()
            for spec: SaOptionSpec in descriptor.options:
                if spec.kind == SaOptionSpec.Kind.ACTION:
                    out.append({"tool": String(descriptor.id), "spec": spec, "row": row_of(spec.key)})
        return out

    func row_of(key: StringName) -> Control:
        return docker.find_child(String(key).capitalize().replace(" ", "") + "Row", true, false) as Control


## The property wanted, over every action row there is: whatever the
## label column says, it is not what the button says.
func test_no_action_row_draws_the_same_text_twice() -> void:
    var rows := Rows.new()
    var found := rows.actions()
    assert_true(found.size() >= 4, "the tools declare action rows to check: %d" % found.size())
    for entry: Dictionary in found:
        var spec: SaOptionSpec = entry["spec"]
        var row: Control = entry["row"]
        assert_not_null(row, "%s's '%s' row is built" % [entry["tool"], spec.key])
        if row == null:
            continue
        var button := rows.docker.options.control(spec.key) as Button
        assert_not_null(button, "and its control is a button")
        var label := row.find_child("Label", true, false) as Label
        var said := label.text if label != null else ""
        assert_true(
            said != button.text, "%s's '%s' says '%s' beside a button saying '%s'" % [entry["tool"], spec.key, said, button.text]
        )
    rows.close()


## And the way it is not drawn twice: the row has no label column at all, and
## the button keeps the option's own word rather than a verb invented here.
func test_an_action_row_is_the_button_and_the_button_keeps_the_label() -> void:
    var rows := Rows.new()
    for entry: Dictionary in rows.actions():
        var spec: SaOptionSpec = entry["spec"]
        var row: Control = entry["row"]
        if row == null:
            continue
        assert_null(row.find_child("Label", true, false), "%s's '%s' row has no label column" % [entry["tool"], spec.key])
        var button := rows.docker.options.control(spec.key) as Button
        assert_eq(button.text, spec.label, "and the button carries the option's own label")
    rows.close()


## Every other kind keeps its label column, so the change is the action's alone
## and not a docker that stopped labelling its rows.
func test_the_rows_that_are_not_actions_keep_their_label_column() -> void:
    var rows := Rows.new()
    rows.machine.set_active_tool(&"brush")
    rows.docker.sync_from_tool()
    var labelled := 0
    for spec: SaOptionSpec in rows.machine.get_descriptor(&"brush").options:
        if spec.kind == SaOptionSpec.Kind.ACTION:
            continue
        if spec.kind == SaOptionSpec.Kind.FLOAT or spec.kind == SaOptionSpec.Kind.INT:
            continue
        var row := rows.row_of(spec.key)
        if row == null:
            continue
        assert_not_null(row.find_child("Label", true, false), "the brush's '%s' row keeps its label" % spec.key)
        labelled += 1
    assert_true(labelled > 3, "and there are rows of that kind to check: %d" % labelled)
    rows.close()


## The dump's half. An action row answers with its button's word for its value,
## so a shot of the crop tool does not come back with both of the row's texts
## empty.
func test_the_dump_reads_the_word_on_an_action_row() -> void:
    var rows := Rows.new()
    rows.machine.set_active_tool(&"crop")
    rows.docker.sync_from_tool()
    var row := rows.row_of(&"crop_apply")
    assert_not_null(row, "the crop tool has its Crop row")
    if row != null:
        assert_eq(ToolOptionsDocker.row_value(row), "Crop", "and the dump reads the word off its button")
    rows.close()
