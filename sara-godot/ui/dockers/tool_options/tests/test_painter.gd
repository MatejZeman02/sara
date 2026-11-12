## A test drive of the Tool Options docker: an afternoon's painting, and what it
## found.
##
## What is here is the part a suite can hold: the shape of the Tool Options
## docker's row list, which is the one defect of the drive that lives in the code
## rather than in a scenario.
##
## The docker is a Window, so it is built detached under a plain Node and its
## `_ready` never runs, which is what `test_tool_options_docker.gd` does and
## why.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Building a surface needs a RenderingDevice, the same reason the docker's own
## suite is marked.
const REQUIRES_GPU := true


## Every row of the brush's page, in the order the docker draws them, as
## `[node name, everything the row draws, the option kind behind it]`.
##
## The kind comes from the tool's own descriptor rather than from the node,
## because two of the answers below turn on it: a toggle says its state by being
## down and an action row has no state, so neither can be asked for words.
func _brush_rows() -> Array:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    # The nine curve option rows are behind Advanced Options, which is why the
    # drive's scenarios all set it and why a docker built without it holds
    # fifteen rows rather than forty-one.
    var advanced := SaSettings.advanced_options
    SaSettings.advanced_options = true

    var host := Node.new()
    var docker := ToolOptionsDocker.new()
    host.add_child(docker)
    docker.target_tool_machine = machine
    machine.set_active_tool(&"brush")
    docker.sync_from_tool()

    var kinds: Dictionary = {}
    for spec: SaOptionSpec in machine.get_descriptor(&"brush").options:
        kinds[String(spec.key).capitalize().replace(" ", "")] = spec.kind

    var rows: Array = []
    var box := docker.find_child("Rows", true, false)
    if box != null:
        for child in box.get_children():
            var row := child as Control
            if row == null or not row.visible or row.name == "EmptyLabel":
                continue
            var stem := String(row.name).trim_suffix("Row").trim_suffix("Slider")
            rows.append([String(row.name), _row_text(row), kinds.get(stem, -1)])

    host.free()
    Fixtures.teardown(surface, machine)
    SaSettings.advanced_options = advanced
    return rows


## Everything a row draws, its label column and its control's own text, as one
## string. A slider is its own row and carries "Size: 22 px" inside itself, and
## a curve option is a label column and a button, so neither reads whole from
## one node.
func _row_text(row: Control) -> String:
    var parts: Array[String] = []
    for node in row.find_children("*", "Label", true, false):
        var label := node as Label
        if label.visible and not label.text.is_empty():
            parts.append(label.text)
    if row is Label and not (row as Label).text.is_empty():
        parts.append((row as Label).text)
    for node in row.find_children("*", "Button", true, false):
        var button := node as Button
        if button.visible and not button.text.is_empty():
            parts.append(button.text)
    if row is Button and not (row as Button).text.is_empty():
        parts.append((row as Button).text)
    return " | ".join(parts)


## What the drive photographed, inverted: no name is on the brush's page
## twice any more, across the page or inside one row.
##
## The drive found six across the page, Size, Opacity, Flow, Ratio, Softness and
## Spacing, each once as a curve option with no value on it and once as the
## slider that carries the number, with nothing on screen saying which was
## which. That page at 283 by 300 showed only the first six rows, and none of the
## six had a value. Reading a whole row rather than its label column then showed
## six more inside a single row, where a text toggle drew the word its label
## column had already drawn.
##
## The names are the first thing each row draws. What follows is its value, and
## two rows both reading "Off" is two options that are off rather than a name
## twice.
##
## The one exception once was the action row, Load Tip, whose label column and
## whose button both carried the word. That row has no label column, so the
## answer here is the empty list.
func test_no_option_name_is_on_the_brush_page_twice() -> void:
    var rows := _brush_rows()
    assert_true(rows.size() > 20, "The brush declares a long page, not a short one: %d rows" % rows.size())

    var seen: Dictionary = {}
    var twice: Array[String] = []
    for row: Array in rows:
        var parts := String(row[1]).split("|")
        var name := parts[0].split(":")[0].strip_edges()
        if name.is_empty():
            continue
        if seen.has(name) and not twice.has(name):
            twice.append(name)
        seen[name] = true
        for index in range(1, parts.size()):
            if parts[index].strip_edges() == name:
                twice.append(name + " (in its own row)")
    twice.sort()
    assert_eq(twice, [] as Array[String], "No row draws its own name twice and no name is on the page twice")


## The order is what decided whether the finding mattered: every one of
## the nine curve options is drawn before the first slider, so a docker too
## short for the whole page shows a painter nothing else. It is pinned rather
## than changed, because the order is the tool's own declaration and a value on
## those rows is what makes the order harmless.
func test_every_curve_option_is_drawn_before_the_first_slider() -> void:
    var rows := _brush_rows()
    var last_option := -1
    var first_slider := rows.size()
    for index in rows.size():
        var name := String(rows[index][0])
        if name.ends_with("OptionRow"):
            last_option = index
        elif name.ends_with("Slider") and index < first_slider:
            first_slider = index
    assert_true(last_option >= 0, "The page has curve option rows on it")
    assert_true(first_slider < rows.size(), "and slider rows too")
    assert_true(
        last_option < first_slider,
        "Every curve option is above every slider: last option %d, first slider %d" % [last_option, first_slider]
    )


## A row a painter can see has to say what
## it is set to, and the nine curve options said only their own name. The number
## they hid is the option's strength, which was in the brush editor and nowhere
## else, and is now on the row's own button beside the sensors it follows.
##
## Three kinds are exempt and the exemption is a finding rather than a hole. An
## action row holds nothing to be set to, and a toggle says its state by being
## down, which is a picture and not a word: the six text toggles now read "On"
## or "Off" because their button had a spare word to spend, and the three iconed
## ones have nowhere to put one.
##
## The third is `CURVE`, and it is the same answer at more length. The row
## is the graph, the graph is the shape, and the shape is the whole value: there
## is no short word for "descending, and steeper over the last fifth", and a
## number beside the picture would say less than the picture does. What the row
## owes a reader instead is the dump, and `ToolOptionControls.read` answers a
## curve row with its points so a capture can say which shape it got.
func test_every_row_the_docker_draws_says_what_it_is_set_to() -> void:
    var rows := _brush_rows()
    assert_true(rows.size() > 20, "The brush declares a long page, not a short one: %d rows" % rows.size())
    var said := 0
    for row: Array in rows:
        var kind: int = row[2]
        if kind == SaOptionSpec.Kind.ACTION or kind == SaOptionSpec.Kind.BOOL:
            continue
        if kind == SaOptionSpec.Kind.CURVE:
            continue
        var parts := String(row[1]).split("|")
        var name := parts[0].split(":")[0].strip_edges()
        assert_true(
            parts.size() > 1 or String(row[1]).contains(":"),
            "%s says what it is set to and not only that it is called '%s'" % [row[0], name]
        )
        said += 1
    assert_true(said > 20, "and that is most of the page, not a handful of it: %d rows" % said)


## The trail of brush presets does not take the word History: the docker a painter opens is Recent
## Presets, and every surface still called History holds the undo stack.
##
## **No docker lists the undo steps yet**, and this does not pretend one does.
## That is a feature rather than a word. What this test pins is that the
## ambiguity is gone, so the next reviewer
## reading a screenshot files against the right thing.
func test_the_only_history_left_in_sara_is_the_undo_stack() -> void:
    var docker := HistoryDocker.new()
    assert_eq(
        String(docker.title), "Recent Presets", "The preset trail says what it holds rather than taking the undo stack's word"
    )
    docker.free()
