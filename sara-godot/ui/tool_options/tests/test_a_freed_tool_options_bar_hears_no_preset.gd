## A tool options bar that is gone hears no preset loaded.
## `ToolOptionControls` connects to `EventBus.preset_loaded`, and the connection
## must not outlive its host, because a bar freed with its controls left a handler
## that tested a freed slider on every preset loaded after it. The connection
## lives as long as the host is in the tree.
extends "res://tests/test_framework.gd"


## A tool whose settings hold one float, so the controls have a slider to hold
## a default for.
class FlowSettings:
    extends Resource

    @export var flow: float = 0.5


class FlowTool:
    extends ToolState

    var settings: Resource = FlowSettings.new()


var _host: Control = null


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


## How many of `EventBus.preset_loaded`'s connections reach *controls*.
func _connections_to(controls: ToolOptionControls) -> int:
    var count := 0
    for connection: Dictionary in EventBus.preset_loaded.get_connections():
        var callable: Callable = connection["callable"]
        if callable.get_object() == controls:
            count += 1
    return count


## A host in the tree with controls built over it and a slider shown for a tool
## whose flow is *flow*.
func _controls_in_the_tree(tool: FlowTool) -> ToolOptionControls:
    _host = Control.new()
    EventBus.add_child(_host)
    var controls := ToolOptionControls.new(_host)
    var descriptor := SaToolDescriptor.new()
    descriptor.id = &"d107_tool"
    descriptor.options.assign([SaOptionSpec.make_float(&"flow", "Flow", 0.0, 1.0, 0.01)] as Array[SaOptionSpec])
    controls.build_for(descriptor)
    controls.sync(tool, &"d107_tool", 1.0)
    return controls


func test_a_host_in_the_tree_hears_a_preset() -> void:
    var tool := FlowTool.new()
    var controls := _controls_in_the_tree(tool)
    assert_eq(_connections_to(controls), 1, "The controls over a host in the tree are connected once")
    tool.settings.flow = 0.8
    EventBus.preset_loaded.emit("probe")
    var slider := controls.control(&"flow") as FactorSlider
    assert_almost_eq(slider.default_value, 0.8, 0.0001, "and the preset's value is what Backspace puts back")


## The ask: a bar is freed, a preset is loaded, and no error is pushed.
func test_a_freed_host_leaves_no_connection_and_no_error() -> void:
    var controls := _controls_in_the_tree(FlowTool.new())
    _host.free()
    _host = null
    assert_eq(_connections_to(controls), 0, "The freed host's controls hold no connection to the preset signal")

    var errors := SaErrorCatcher.new()
    OS.add_logger(errors)
    EventBus.preset_loaded.emit("probe")
    OS.remove_logger(errors)
    var caught := errors.described([SaErrorCatcher.ERROR, SaErrorCatcher.SCRIPT])
    assert_eq(caught, PackedStringArray(), "and a preset loaded afterwards pushes no error")


## The ask as the finding states it, with the bar itself: it builds its controls
## in `_init`, before it is in the tree, and is freed with its sliders.
func test_a_freed_bar_hears_no_preset_loaded_after_it() -> void:
    var bar := ToolOptionsBar.new()
    EventBus.add_child(bar)
    var controls := bar.options
    assert_eq(_connections_to(controls), 1, "The bar's controls listen once the bar is in the tree")
    bar.free()
    assert_eq(_connections_to(controls), 0, "and not once it is freed")

    var errors := SaErrorCatcher.new()
    OS.add_logger(errors)
    EventBus.preset_loaded.emit("probe")
    OS.remove_logger(errors)
    var caught := errors.described([SaErrorCatcher.ERROR, SaErrorCatcher.SCRIPT])
    assert_eq(caught, PackedStringArray(), "so a preset loaded afterwards pushes no error")


## A host that leaves the tree stops listening, and one that comes back listens
## again, which is what a docker moved to a floating window does.
func test_a_host_that_leaves_the_tree_stops_listening_and_hears_again_on_return() -> void:
    var controls := _controls_in_the_tree(FlowTool.new())
    EventBus.remove_child(_host)
    assert_eq(_connections_to(controls), 0, "A host out of the tree is not connected")
    EventBus.add_child(_host)
    assert_eq(_connections_to(controls), 1, "and is connected once when it is back")


## A host built outside the tree, the way the bar is built in `_init`, listens
## from the moment it enters and not before.
func test_a_host_built_outside_the_tree_listens_from_the_moment_it_enters() -> void:
    _host = Control.new()
    var controls := ToolOptionControls.new(_host)
    assert_eq(_connections_to(controls), 0, "A host that is not in the tree is not connected")
    EventBus.add_child(_host)
    assert_eq(_connections_to(controls), 1, "It is connected once it enters")
