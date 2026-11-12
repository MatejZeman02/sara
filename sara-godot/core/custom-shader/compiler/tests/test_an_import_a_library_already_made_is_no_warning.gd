## Importing a library is idempotent.
##
## Lessons 0 and 1 import both colour libraries above a kernel, and
## `linear_srgb_color_space.gmacs` imports `oklab_color_space` itself. The paste
## dropped the second import correctly and pushed a warning with a backtrace for
## it, so every run of those cells put a warning in Sara's log for code that is
## right. This suite holds the silence for a library already in the compilation,
## and the word that stays for an import that cycles.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true


func after_each() -> void:
    for name: String in ["d109_a", "d109_b"]:
        GlobalShaderCompiler.clear_virtual_include(name)


## The source a lesson cell writes, through the dialect and the paste, with the
## warnings pushed on the way.
func _paste(text: String) -> Array:
    var warnings := SaErrorCatcher.new()
    OS.add_logger(warnings)
    var glsl: String = GlobalShaderCompiler.source.glsl_of(text)
    var out: String = GlobalShaderCompiler.source.process_includes(glsl, "d109_probe.gmacs")
    OS.remove_logger(warnings)
    return [out, warnings.texts([SaErrorCatcher.WARNING])]


func _holds_each_library_once(order: String, text: String) -> void:
    var pasted := _paste(text)
    var out: String = pasted[0]
    var warnings: PackedStringArray = pasted[1]
    assert_eq(warnings.size(), 0, "%s pushes no warning: %s" % [order, warnings])
    assert_false("#include" in out, "%s leaves no directive for glslang" % order)
    assert_eq(out.count("vec3 linear_srgb_to_oklab("), 1, "%s holds the Oklab library once" % order)
    assert_eq(out.count("vec3 srgb_to_linear_srgb("), 1, "%s holds the sRGB library once" % order)


func test_srgb_then_oklab_is_no_warning() -> void:
    _holds_each_library_once("sRGB then Oklab", "import linear_srgb_color_space\nimport oklab_color_space\n")


func test_oklab_then_srgb_is_no_warning() -> void:
    _holds_each_library_once("Oklab then sRGB", "import oklab_color_space\nimport linear_srgb_color_space\n")


## A cycle is what is wrong, so it keeps its word, and still pastes each side once.
func test_an_import_cycle_still_warns() -> void:
    GlobalShaderCompiler.set_virtual_include("d109_a", '#include "d109_b"\nfloat a() { return 1.0; }')
    GlobalShaderCompiler.set_virtual_include("d109_b", '#include "d109_a"\nfloat b() { return 2.0; }')

    var pasted := _paste('#include "d109_a"\n')
    var out: String = pasted[0]
    var warnings: PackedStringArray = pasted[1]

    assert_eq(warnings.size(), 1, "The cycle is named once: %s" % [warnings])
    assert_true(warnings.size() == 1 and warnings[0].contains("Import cycle"), "as a cycle")
    assert_eq(out.count("float a()") + out.count("float b()"), 2, "and each side is pasted once")
