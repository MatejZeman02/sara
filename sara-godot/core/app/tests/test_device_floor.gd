## F4. The device floor probe: what Sara asks of a GPU, answered by the GPU
## rather than typed from memory.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true


func test_the_probed_formats_are_exactly_bytes_per_texel() -> void:
    var result := SaDeviceFloor.check()
    var probed: Array = result["formats"].keys()
    probed.sort()
    var declared: Array = SaFieldSpec.BYTES_PER_TEXEL.keys()
    declared.sort()
    assert_eq(probed, declared, "a sixth format added to BYTES_PER_TEXEL must be a sixth format the floor probes")


func test_it_asks_with_the_same_usage_bits_sa_texture_creates_with() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var format: int = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    var expected := rd.texture_is_format_supported_for_usage(format, SaTexture.USAGE_BITS)
    var result := SaDeviceFloor.check()
    assert_eq(result["formats"][format], expected, "the probe and SaTexture must ask the driver the same question")


func test_no_device_answers_none_and_raises_nothing() -> void:
    var result := SaDeviceFloor.describe(null)
    assert_eq(result, {"device": "none"}, "a null device answers none and nothing else")
    assert_eq(SaDeviceFloor.summary_for(result), "no device")


func test_every_format_is_supported_on_the_gates_device() -> void:
    var result := SaDeviceFloor.check()
    for format: int in result["formats"]:
        assert_true(result["formats"][format], "format %d is not a storage image on this device" % format)
    assert_eq(SaDeviceFloor.summary(), "met", "the gate's own device should meet the floor")


func test_the_three_limits_carry_what_sara_needs_beside_the_driver_figure() -> void:
    var result := SaDeviceFloor.check()
    var limits: Dictionary = result["limits"]
    assert_eq(limits["push_constant_bytes"]["needs"], SaDeviceFloor.NEEDS_PUSH_CONSTANT_BYTES)
    assert_eq(limits["workgroup_invocations"]["needs"], SaDeviceFloor.NEEDS_WORKGROUP_INVOCATIONS)
    assert_eq(limits["texture_size_2d"]["needs"], SaDeviceFloor.NEEDS_TEXTURE_SIZE_2D)
    for key: String in limits:
        assert_true(limits[key]["limit"] >= limits[key]["needs"], "%s falls short of what Sara asks for" % key)


func test_the_probe_neither_allocates_nor_dispatches() -> void:
    var source := _read(_source_path("core/app/sa_device_floor.gd"))
    for needle: String in ["texture_create", "texture_get_data", ".dispatch("]:
        assert_true(not source.contains(needle), "sa_device_floor.gd must never %s" % needle)


func _source_path(relative: String) -> String:
    return ProjectSettings.globalize_path("res://").path_join(relative)


func _read(absolute: String) -> String:
    var file := FileAccess.open(absolute, FileAccess.READ)
    return file.get_as_text() if file != null else ""
