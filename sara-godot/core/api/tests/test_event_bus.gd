## Unit tests for EventBus singleton.
extends "res://tests/test_framework.gd"

var last_tool_name: String = ""
var last_module_name: String = ""


func before_each() -> void:
    last_tool_name = ""
    last_module_name = ""


func test_tool_changed_signal() -> void:
    var cb := func(name: String) -> void: last_tool_name = name
    EventBus.tool_changed.connect(cb)
    EventBus.tool_changed.emit("brush")
    assert_eq(last_tool_name, "brush", "tool_changed signal should pass tool name")
    EventBus.tool_changed.disconnect(cb)


func test_module_loaded_signal() -> void:
    var cb := func(name: String) -> void: last_module_name = name
    EventBus.module_loaded.connect(cb)
    EventBus.module_loaded.emit("sara-base-modules")
    assert_eq(last_module_name, "sara-base-modules", "module_loaded should pass module name")
    EventBus.module_loaded.disconnect(cb)
