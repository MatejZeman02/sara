## The skeleton asks a tool's descriptor rather than naming the brush.
##
## Hard rule 6: "A door only the built-ins can walk through is not a door."
## The tool machine opened the presets on a right press only while the tool's
## id was `brush`, fell back to `brush` when a hand-back had nowhere to go, and
## the Info docker read the pressure off `get_tool("brush")` alone. So a
## module's own pen could list presets and not open them, and showed an empty
## Pressure row and "no brush" on the Device row.
##
## A stranger registers its pen through `SaContext.register_tool`, the door a
## third-party module uses, with the new members set, and this suite asks the
## same three questions of it. The brush's own toggle is held by
## `test_a_second_right_press_closes_the_presets.gd`, left unedited.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const DockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")
const InfoDockerScript = preload("res://ui/dockers/panels/info_docker.gd")

const REQUIRES_GPU := true

const STRANGER_ID := &"stranger_pen"
const STRANGER_MODULE := &"stranger"


## A pen that is nobody's built-in. It writes the pressure it reads to the
## member `ToolState` declares and does nothing else.
class StrangerPen:
    extends ToolState

    func handle_input(event: InputEvent) -> void:
        var motion := event as InputEventMouseMotion
        if motion != null:
            last_pressure = motion.pressure


## A right press over the canvas under the stranger's pen opens the presets,
## and a second shuts them, with no context menu asked for.
func test_a_strangers_pen_takes_the_right_press() -> void:
    var built := _build(true)
    if built.is_empty():
        return
    var machine: ToolMachine = built["machine"]
    var docker: Window = built["docker"]
    var asked: Array = []
    machine.context_menu_requested.connect(func(at: Vector2) -> void: asked.append(at))

    machine.set_active_tool(STRANGER_ID)
    assert_eq(machine.active_tool_name, STRANGER_ID, "The stranger's pen is the active tool")
    assert_false(docker.visible, "The docker starts shut")
    machine.handle_input(_right_press())
    assert_true(docker.visible, "The stranger's right press opens the presets")
    machine.handle_input(_right_press())
    assert_false(docker.visible, "and a second shuts them")
    assert_eq(asked.size(), 0, "Neither fell through to the context menu")

    _tear_down(built)


## The member is what opens them, not the tool being a stranger's: without it
## the press is the context menu it always was.
func test_without_the_member_the_press_is_the_context_menu() -> void:
    var built := _build(false)
    if built.is_empty():
        return
    var machine: ToolMachine = built["machine"]
    var docker: Window = built["docker"]
    var asked: Array = []
    machine.context_menu_requested.connect(func(at: Vector2) -> void: asked.append(at))

    machine.set_active_tool(STRANGER_ID)
    machine.handle_input(_right_press())
    assert_false(docker.visible, "A pen that does not ask for the gesture leaves the docker shut")
    assert_eq(asked.size(), 1, "and asks for its context menu")

    _tear_down(built)


## The Info docker reads the pressure of whatever tool is active when its
## descriptor says it reads one, and the device off the pointer policy.
func test_the_info_docker_reads_the_strangers_pressure() -> void:
    var built := _build(true)
    if built.is_empty():
        return
    var machine: ToolMachine = built["machine"]
    machine.set_active_tool(STRANGER_ID)
    var motion := InputEventMouseMotion.new()
    motion.position = Vector2(100, 100)
    motion.pressure = 0.37
    machine.handle_input(motion)
    assert_almost_eq(machine.active_tool.last_pressure, 0.37, 0.001, "The stranger's pen read the pressure")

    var info: InfoDocker = InfoDockerScript.new()
    info.target_tool_machine = machine
    info._section_boxes["Input"]._input_rows(machine)
    var pressure: Label = info._section_boxes["Input"].rows["Pressure"][1]
    var device: Label = info._section_boxes["Input"].rows["Device"][1]
    assert_eq(pressure.text, "0.37", "The Pressure row shows the stranger's pressure")
    assert_true(pressure.visible, "and is shown")
    assert_false(device.text == "no brush", "The Device row does not ask for a brush")
    assert_true(device.visible, "and is shown")

    # The fill paints and reads no pressure, so its row is empty rather than a
    # number nobody wrote.
    machine.set_active_tool(&"bucket_fill")
    info._section_boxes["Input"]._input_rows(machine)
    assert_false(pressure.visible, "A tool that reads no pressure leaves the row empty")
    info.free()

    _tear_down(built)


## A hand-back with nowhere to go lands on the tool that declares itself the
## fallback, which the stamp brush does for its brush and nothing else.
func test_a_hand_back_lands_on_the_declared_fallback() -> void:
    var built := _build(true)
    if built.is_empty():
        return
    var machine: ToolMachine = built["machine"]
    assert_eq(machine.fallback_tool_name(), &"brush", "The stamp brush's brush declares itself the fallback")
    machine.set_active_tool(STRANGER_ID)
    machine.previous_tool_name = &""
    machine.return_to_previous_tool()
    assert_eq(machine.active_tool_name, &"brush", "and a hand-back with nothing before it goes there")
    _tear_down(built)


## A build whose tools declare no fallback lands on the first tool the machine
## was handed, rather than on a tool nobody registered.
func test_with_no_fallback_declared_the_first_tool_is_it() -> void:
    var registry := SaToolRegistry.new()
    _door(registry).register_tool(_stranger_descriptor(false))
    var other := SaToolDescriptor.create(&"stranger_other", StrangerPen)
    _door(registry).register_tool(other)
    var surface := Fixtures.make_surface()
    var machine := ToolMachine.new()
    machine.name = "ToolMachine"
    machine._ready()
    machine.bind(surface, registry)
    assert_eq(machine.fallback_tool_name(), STRANGER_ID, "The first tool the machine was handed")
    machine.set_active_tool(&"stranger_other")
    machine.previous_tool_name = &""
    machine.return_to_previous_tool()
    assert_eq(machine.active_tool_name, STRANGER_ID, "is where a hand-back with nothing before it goes")
    Fixtures.teardown(surface, machine)


func _stranger_descriptor(takes_presets: bool) -> SaToolDescriptor:
    var descriptor := SaToolDescriptor.create(STRANGER_ID, StrangerPen)
    descriptor.display_name = "Stranger's pen"
    descriptor.is_painting = true
    descriptor.opens_docker_on_right_click = takes_presets
    descriptor.reads_pressure = true
    return descriptor


## The door a third-party module is handed, scoped to the stranger.
func _door(registry: SaToolRegistry) -> SaContext:
    var ctx := SaContext.create(
        registry, SaBlendModeRegistry.new(), SaCommandRegistry.new(), SaLayerTypeRegistry.new(), SaUIRegistry.new()
    )
    return ctx.for_module(STRANGER_MODULE)


## The built-in tools and the stranger's pen, a machine bound to them and a
## presets docker, both in the tree under an autoload for the reason b4 gives:
## the handler finds the docker under `get_tree().root` by name.
func _build(takes_presets: bool) -> Dictionary:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This suite needs the real scene tree, because the handler looks under its root")
    if tree == null:
        return {}

    var registry := Fixtures.make_tool_registry()
    var registered := _door(registry).register_tool(_stranger_descriptor(takes_presets))
    assert_true(registered, "The stranger's pen registers through the door")

    var embedded: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "D20StrangerTestHost"
    EventBus.add_child(host)

    var surface := Fixtures.make_surface()
    var machine := ToolMachine.new()
    machine.name = "ToolMachine"
    machine._ready()
    machine.bind(surface, registry)
    host.add_child(machine)

    var docker := DockerScript.new()
    host.add_child(docker)
    docker.hide()

    return {"tree": tree, "host": host, "machine": machine, "docker": docker, "surface": surface, "embedded": embedded}


func _tear_down(built: Dictionary) -> void:
    var host: Node = built["host"]
    var machine: ToolMachine = built["machine"]
    host.remove_child(machine)
    host.free()
    Fixtures.teardown(built["surface"], machine)
    (built["tree"] as SceneTree).root.gui_embed_subwindows = bool(built["embedded"])


func _right_press() -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_RIGHT
    event.pressed = true
    event.position = Vector2(100, 100)
    event.global_position = Vector2(100, 100)
    return event
