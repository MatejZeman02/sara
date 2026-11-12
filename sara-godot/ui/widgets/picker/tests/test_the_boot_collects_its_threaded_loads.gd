## A capture that quits leaked seven objects, and so did a
## painter's quit, because both leave by the same path.
##
## Five were the tokens of the threaded loads `SaBoot` asks for the packaged
## module scripts. A request holds its token until `load_threaded_get` collects
## it, and the module loader read the scripts with a bare `load`, which left
## every token to Godot's exit. The other two were Godot's own, one per
## `.gdshader` the colour picker's shapes preloaded on the boot's worker, because
## a nested load leaves one.
## What the running app does is held by
## `scenarios/a-capture-that-quits-leaks-no-object.json`, whose run log has no
## leak line, and `sara_shot.py` reports one when it does.
extends "res://tests/test_framework.gd"

const PICKER_SHAPE := "res://ui/widgets/picker/sa_picker_shape.gd"


func test_the_loader_collects_the_request_the_boot_made() -> void:
    var paths := ModuleLoader.packaged_script_paths()
    assert_true(paths.size() > 0, "Sara ships modules")
    var path := paths[0]
    assert_eq(ResourceLoader.load_threaded_request(path, "", false), OK, "the request the boot makes")
    var script := ModuleLoader._load_module_script(path, false)
    assert_not_null(script, "the loader hands back the script")
    assert_eq(
        ResourceLoader.load_threaded_get_status(path),
        ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
        "and no request stands for it after, so no token waits for the exit"
    )
    assert_eq(script, load(path), "the script is the cached one a bare load would have given")


func test_a_path_nobody_requested_loads_as_it_did() -> void:
    var path := ModuleLoader.packaged_script_paths()[0]
    assert_eq(ResourceLoader.load_threaded_get_status(path), ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "no request")
    assert_eq(ModuleLoader._load_module_script(path, false), load(path), "a bare load's answer")


func test_the_picker_shape_preloads_no_shader() -> void:
    var text := FileAccess.get_file_as_string(PICKER_SHAPE)
    assert_false(text.contains('preload("res://shaders/'), "a preload here is a nested load on the boot's worker")
    var shape := SaPickerShape.new()
    assert_eq(shape._ring_mat.shader.resource_path, SaPickerShape.OKHSV_SHADER_PATH, "the ring still draws the OKHSV shader")
    assert_eq(shape._hue_bar_mat.shader.resource_path, SaPickerShape.HSV_SHADER_PATH, "the hue bar the HSV one")
    shape.set_kind(SaPickerShape.Kind.HSV_SQUARE)
    assert_eq(shape._area_mat.shader.resource_path, SaPickerShape.HSV_SHADER_PATH, "a classic shape switches to HSV")
    shape.set_kind(SaPickerShape.Kind.WHEEL)
    assert_eq(shape._area_mat.shader.resource_path, SaPickerShape.OKHSV_SHADER_PATH, "and back")
    shape.free()
