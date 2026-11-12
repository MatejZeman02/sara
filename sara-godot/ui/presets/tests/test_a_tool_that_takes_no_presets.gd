## A tool whose settings declares no preset engine takes no presets: nothing is
## dimmed against it and a save writes no file.
##
## The gradient showed it. `SaPresetMeta.engine_of` answers the id a settings
## resource is told apart by, which falls back to the script's global name, so
## `SaGradientEnds` read as an engine called `Sa Gradient Ends`: every cell in the
## grid was dimmed under a class name in words no painter has seen, and a save
## with the gradient picked left a preset of that engine in the painter's folder,
## loadable by no tool.
##
## The two readings this holds are the bar's, `ToolOptionsPresets.preset_engine`,
## which the presets docker dims by and the save path writes by, so the dim and
## the save cannot answer differently.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const GradientEndsScript = preload("res://modules/sara-base-modules/base/gradient/sa_gradient_ends.gd")
const StampSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

static var scratch_dir: String = SaDataRoot.path("test_a_tool_that_takes_no_presets")


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    for box: ToolOptionsPresets in _boxes:
        box.free()
    _boxes.clear()
    ScratchFolder.clear(scratch_dir)


## The gradient's ends declare no engine, so the tool takes none, and the reading
## is empty rather than the name of a class.
func test_a_tool_that_declares_no_engine_takes_no_presets() -> void:
    var box := _box(GradientEndsScript.new())
    assert_eq(box.preset_engine(), &"", "The ends declare no engine, so the tool takes none")
    assert_false(box.action_available(ToolOptionsPresets.PRESET_ID_SAVE), "and Save as... is not offered")


## A settings script that declares one is read exactly as before, which is the
## rule and the reason the guard is about a missing engine rather than about a
## tool that is not the brush.
func test_a_declared_engine_is_read() -> void:
    var box := _box(StampSettingsScript.new())
    assert_eq(box.preset_engine(), &"stamp", "The stamp brush's settings declares its engine")
    assert_true(box.action_available(ToolOptionsPresets.PRESET_ID_SAVE), "so a save is offered")


## The descriptor's own word wins over the settings, which is the order the
## docker's dim has always read the two in.
func test_the_descriptors_word_wins_over_the_settings() -> void:
    var box := _box(StampSettingsScript.new())
    box.descriptor_source = _descriptor(&"noise")
    assert_eq(box.preset_engine(), &"noise", "The descriptor the surface hands over is what the tool takes")


## A save with the gradient picked answers an empty name and leaves no file
## behind, so the grid keeps the 23 cells it had rather than gaining a 24th
## nothing can load.
func test_a_save_with_no_engine_writes_nothing() -> void:
    var box := _box(GradientEndsScript.new())
    assert_eq(box.save_current_as_preset("gradient"), "", "Nothing is stored")
    assert_false(FileAccess.file_exists(scratch_dir.path_join("gradient.tres")), "and no file lands")


## The same save against the stamp brush still writes, so what the guard reads is
## the engine and not a preset path that quietly stopped storing.
func test_a_save_with_an_engine_still_writes() -> void:
    var box := _box(StampSettingsScript.new())
    assert_eq(box.save_current_as_preset("stamp"), "stamp", "A tool of an engine saves as it did")
    assert_true(FileAccess.file_exists(scratch_dir.path_join("stamp.tres")), "and the file is there")


## The boxes built by one test, so a failing assertion leaves no node behind.
var _boxes: Array[ToolOptionsPresets] = []


## A preset group in front of *settings*, with its store pointed at the scratch
## directory rather than at the painter's own preset folder.
func _box(settings: Resource) -> ToolOptionsPresets:
    var box := ToolOptionsPresets.new()
    box.preset_store.dir = scratch_dir
    box.settings_source = func() -> Resource: return settings
    _boxes.append(box)
    return box


## A surface that hands the group a descriptor of its own, which is what the
## tool options bar does for the tool it shows.
func _descriptor(engine: StringName) -> Callable:
    return func() -> SaToolDescriptor:
        var descriptor := SaToolDescriptor.create(&"fixture", null)
        descriptor.preset_engine = engine
        return descriptor
