## The ellipse selection has a button of its own in the toolbox.
##
## The marquee must not hide its ellipse behind a shape row the bar hides by
## default, or a painter who opens the selection group finds one Marquee and no
## ellipse anywhere. These hold the three halves of the claim: the toolbox lists Ellipse Select after
## Marquee, each tool's drag
## makes its own shape, and neither shows a row that would make the other.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")

## A drag selects on the GPU, and the coverage is read back from it.
const REQUIRES_GPU := true

## The two shapes and the lasso's, which would show any of them that leaked
## onto the bar.
const SELECTION_TOOLS: Array[StringName] = [&"marquee", &"ellipse_select", &"lasso"]

var _order: Array = []
var _groups_raw: Variant = null


func before_each() -> void:
    _order = SaSettings.get_layout_order(SaToolBoxGrid.CATEGORY)
    _groups_raw = SaSettings.get_docker_option(SaToolBoxGrid.CATEGORY, SaToolBoxGroups.GROUPS_KEY)


## The stored-groups case writes the run's profile, so it is put back.
func after_each() -> void:
    SaSettings.set_docker_option(SaToolBoxGrid.CATEGORY, SaToolBoxGroups.GROUPS_KEY, _groups_raw)
    SaSettings.set_layout_order(SaToolBoxGrid.CATEGORY, _order)


func _coverage_of(doc: SaDocument, x: int, y: int) -> float:
    var chunk: SaChunk = doc.selection.chunks.get(Vector2i((Vector2(x, y) / SaChunk.SIZE).floor()), null)
    if chunk == null:
        return 0.0
    var texture := chunk.field(SaSelection.FIELD)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return bytes.decode_float(((y % SaChunk.SIZE) * texture.size.x + x % SaChunk.SIZE) * 4)


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


## Drags *tool_id* from (100, 100) to (300, 200) on a fresh document and hands
## back the document, the machine and the surface for the caller to read and
## tear down.
func _drag(tool_id: StringName) -> Array:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(tool_id)
    var tool := machine.active_tool
    surface.view.mouse_position = Vector2(100, 100)
    tool.handle_input(_button(true))
    surface.view.mouse_position = Vector2(300, 200)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    return [surface.get_document(), machine, surface]


func test_the_toolbox_lists_ellipse_select_after_marquee() -> void:
    var registry := Fixtures.make_tool_registry()
    var descriptor := registry.get_descriptor(&"ellipse_select")
    assert_not_null(descriptor, "Ellipse Select is a registered tool")
    assert_eq(descriptor.display_name, "Ellipse Select", "under the name the toolbox shows")
    assert_eq(descriptor.category, &"select", "in the selection group")
    assert_eq(descriptor.activate_action, &"tool_ellipse_select", "with an action the painter can bind")
    assert_true(InputMap.has_action(&"tool_ellipse_select"), "which the input map holds")
    assert_not_null(SaUI.get_icon(descriptor.icon_name), "and an icon of its own")
    assert_true(descriptor.icon_name != registry.get_descriptor(&"marquee").icon_name, "not the marquee's")

    var docker := ToolBoxDockerScript.new() as ToolBoxDocker
    docker.name = "ToolBoxDocker"
    docker.rebuild_from_registry(registry)
    var members := docker.tools_in_category_of("marquee")
    var after := members.find("marquee") + 1
    assert_eq(members.find("ellipse_select"), after, "The toolbox lists it right after Marquee: %s" % [members])
    docker.free()


## A profile that stored its groups before the tool existed gets it beside the
## Marquee too, rather than after the Patch at the group's end.
func test_a_stored_group_takes_it_after_marquee() -> void:
    var descriptors := Fixtures.make_tool_registry().list_descriptors()
    var without: Array = []
    for group: Array in SaToolBoxGroups.from_registry(descriptors):
        var copy := group.duplicate()
        copy.erase("ellipse_select")
        without.append(copy)
    SaToolBoxGroups.save(without, descriptors)

    for group: Array in SaToolBoxGroups.stored(descriptors):
        if group.has("marquee"):
            var after := group.find("marquee") + 1
            assert_eq(group.find("ellipse_select"), after, "The stored group takes it after Marquee: %s" % [group])


func test_a_drag_with_ellipse_select_selects_an_ellipse() -> void:
    var parts := _drag(&"ellipse_select")
    var doc: SaDocument = parts[0]
    assert_eq(doc.selection.bounds, Rect2i(100, 100, 200, 100), "The ellipse fills the box dragged")
    assert_almost_eq(_coverage_of(doc, 200, 150), 1.0, 0.001, "and holds its centre")
    assert_almost_eq(_coverage_of(doc, 102, 102), 0.0, 0.001, "and not the box's corner")
    Fixtures.teardown(parts[2], parts[1])


func test_a_drag_with_marquee_selects_a_rectangle() -> void:
    var parts := _drag(&"marquee")
    var doc: SaDocument = parts[0]
    assert_eq(doc.selection.bounds, Rect2i(100, 100, 200, 100), "The rectangle is the box dragged")
    assert_almost_eq(_coverage_of(doc, 200, 150), 1.0, 0.001, "and holds its centre")
    assert_almost_eq(_coverage_of(doc, 102, 102), 1.0, 0.001, "and the box's corner")
    Fixtures.teardown(parts[2], parts[1])


## Neither tool declares a shape row, so neither the bar, nor Tool Options,
## nor the canvas's right-click menu, which all build from the descriptor, can
## show one.
func test_neither_tool_shows_a_shape_option() -> void:
    var registry := Fixtures.make_tool_registry()
    for id: StringName in [&"marquee", &"ellipse_select"]:
        var keys: Array = []
        for spec: SaOptionSpec in registry.get_descriptor(id).options:
            keys.append(spec.key)
        var want: Array = [&"selection_mode", &"feather"]
        if id == &"ellipse_select":
            # The ellipse has the lasso's Anti-aliasing.
            want.append(&"ellipse_anti_alias")
        assert_eq(keys, want, "%s declares the mode and the feather and no shape" % id)
    for id: StringName in SELECTION_TOOLS:
        for spec: SaOptionSpec in registry.get_descriptor(id).options:
            assert_true(spec.key != &"marquee_shape", "%s shows no marquee shape" % id)
