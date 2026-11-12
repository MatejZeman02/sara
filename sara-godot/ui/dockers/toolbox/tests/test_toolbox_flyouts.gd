## The toolbox draws one button per tool group, with the rest behind a flyout.
## A group is a group id.
##
## The toolbar docker offers vertical or horizontal tool icons with group
## flyouts. `SaToolDescriptor.category` had been there
## since the registry was, with the built-ins declaring five between them, so the
## grouping was in the tree and nothing read it. These assertions are what stops
## it going unread again.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")


func _toolbox() -> ToolBoxDocker:
    var docker := ToolBoxDockerScript.new() as ToolBoxDocker
    docker.name = "ToolBoxDocker"
    docker.rebuild_from_registry(Fixtures.make_tool_registry())
    return docker


## The grouping is the registry's. A test that wrote the names out would pass
## the day a tool joined a group and the toolbox stopped matching it. A button is a `toolbox_group` two tools
## share, or a tool alone.
func test_the_buttons_are_the_groups_the_registry_declares() -> void:
    var registry := Fixtures.make_tool_registry()
    var docker := _toolbox()

    var keys := {}
    for descriptor: SaToolDescriptor in registry.list_tools():
        var own := descriptor.toolbox_group
        keys[own if own != &"" else StringName("tool:%s" % descriptor.id)] = true
    assert_eq(docker._buttons.size(), keys.size(), "one button per group the registry reports")
    assert_true(docker._buttons.size() < registry.list_ids().size(), "and fewer buttons than tools, or the flyout buys nothing")
    docker.free()


## Hard rule 6 read forward: every tool reaches a button and is offered by it.
func test_every_registered_tool_is_offered_by_exactly_one_button() -> void:
    var registry := Fixtures.make_tool_registry()
    var docker := _toolbox()

    for descriptor: SaToolDescriptor in registry.list_tools():
        var id := String(descriptor.id)
        var button := docker.button_for_tool(id)
        assert_not_null(button, "%s has a button" % id)
        assert_true(docker.tools_in_category_of(id).has(id), "and that button offers it")
        var owners := 0
        for other: StringName in registry.list_ids():
            if docker.tools_in_category_of(String(other)).has(id):
                owners += 1
        assert_true(owners > 0, "%s is offered somewhere" % id)
    docker.free()


## A category of one is a plain button, which is the clause that keeps the
## corner mark a promise rather than decoration.
func test_a_category_of_one_has_no_flyout() -> void:
    var docker := _toolbox()

    assert_false(docker.open_flyout(&"sample"), "the eyedropper is alone in its category and opens nothing")
    var mark := docker.button_for_tool("eyedropper").get_node_or_null("FlyoutMark") as Control
    assert_not_null(mark, "the mark exists on every button")
    assert_false(mark.visible, "and is hidden where there is nothing under it")

    assert_true(docker.open_flyout(&"fill"), "the fill and the gradient do open one")
    var paint_mark := docker.button_for_tool("bucket_fill").get_node_or_null("FlyoutMark") as Control
    assert_true(paint_mark.visible, "and say so in the corner")
    docker.free()


## The mark drew nothing at all in the first version, at zero by zero, because
## `set_anchors_preset` moves the anchors and leaves the offsets. Pinned as a
## size rather than as a call, since the next person to touch it will change
## the call.
func test_the_flyout_mark_has_a_size_to_draw_in() -> void:
    var docker := _toolbox()
    var mark := docker.button_for_tool("brush").get_node_or_null("FlyoutMark") as Control
    assert_not_null(mark, "the brush's button carries a mark")
    assert_true(mark.get_combined_minimum_size().x > 0.0, "which is wider than nothing")
    assert_eq(mark.mouse_filter, Control.MOUSE_FILTER_IGNORE, "and does not eat the press that opens the flyout")
    docker.free()


## Picking from the flyout moves the face, so the next plain press repeats the
## tool the painter last chose rather than the first of the category.
func test_picking_from_the_flyout_becomes_the_buttons_face() -> void:
    var docker := _toolbox()
    assert_true(docker.open_flyout(&"fill"), "the fills' flyout opens")

    var row := docker._flyout_ids.find("gradient")
    assert_true(row >= 0, "the gradient is one of its rows")
    docker._on_flyout_id_pressed(row)

    var report := docker.toolbox_report()
    var faces := {}
    for entry: Dictionary in report["buttons"]:
        if entry.has("category"):
            faces[entry["category"]] = entry["face"]
    assert_eq(faces.get("fill"), "gradient", "and the button now shows it")
    docker.free()


## A tool chosen by its chord has to move the face too, or pressing the button
## after pressing B paints with whatever it was showing before.
func test_a_tool_activated_elsewhere_moves_its_own_face() -> void:
    var docker := _toolbox()
    docker._on_event_tool_changed("ellipse_select")

    var button := docker.button_for_tool("ellipse_select")
    assert_true(button.button_pressed, "the select button is the lit one")
    var report := docker.toolbox_report()
    for entry: Dictionary in report["buttons"]:
        if entry.get("category") == "select":
            assert_eq(entry["face"], "ellipse_select", "and shows the ellipse")
    docker.free()


## The stored layout entries and the tool ids disagree in both directions, and
## reading either alone silently hid a tool from its own visibility switch.
## "Bucket Fill Tool" is the id and "Magic Wand Tool" is the label.
## The two moved to `SaToolBoxGrid` with the rest of the layout arithmetic,
## and no longer need a docker to be asked.
func test_both_spellings_of_a_layout_entry_find_their_tool() -> void:
    var registry := Fixtures.make_tool_registry()

    var fill := registry.get_descriptor(&"bucket_fill")
    var wand := registry.get_descriptor(&"wand")
    assert_true(SaToolBoxGrid.entry_matches("Bucket Fill Tool", fill), "the fill is found by its id, its label is Fill")
    assert_true(SaToolBoxGrid.entry_matches("Magic Wand Tool", wand), "the wand by its label, since its id is wand")
    assert_false(SaToolBoxGrid.entry_matches("Magic Wand Tool", fill), "and neither answers for the other")
    assert_eq(SaToolBoxGrid.layout_entry_for(wand), "Magic Wand Tool", "the entry the settings hold, not one made up here")
