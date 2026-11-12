## The base module's filters and the Filter menu's sections come out of a fresh
## registry in the order they were registered in before the registrations moved
## to `filter_registrations.gd`, so moving them changed nothing a painter sees.
##
## The lists below are the ones the suite held as the block stood in
## `module.gd`. A row that adds a filter adds its line here beside its line in
## the registration list.
extends "res://tests/test_framework.gd"

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")

const FILTERS: Array[String] = [
    "brightness_contrast",
    "exposure",
    "hue_saturation_lightness",
    "color_balance",
    "levels",
    "equalize",
    "curves",
    "palette",
    "gradient_map",
    "white_point",
    "red_eye_removal",
    "invert",
    "desaturate",
    "add_noise",
    "drifting_noise",
    "denoise",
    "wavelet_denoise",
    "hot_pixels",
    "sharpen",
    "high_pass",
    "local_contrast",
    "normal_map",
    "bump_map",
    "wrap_offset",
    "wobble",
    "mirror",
    "gaussian_blur",
    "box_blur",
    "low_pass",
    "motion_blur",
    "lens_blur",
    "bloom",
    "threshold",
    "edge_detection",
    "laplacian",
    "dither",
    "pixelate",
    "vignette",
    "posterise",
    "chromatic_aberration",
    "lut",
    "tonemap",
    "lens_correction",
]

## Id, label and place, in the order the menu lists them.
const SECTIONS: Array[String] = [
    "tone:Tone:100",
    "color:Colour:200",
    "3d:3D:300",
    "blur:Blur:400",
    "sharpen:Sharpen:500",
    "distort:Distort:600",
    "noise:Noise:700",
    "pixelate:Pixelate:800",
    "stylize:Stylize:900",
    "other:Other:1000",
]


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    var mod := BaseModule.new()
    mod.register(registries.context.for_module(mod.get_id()))
    return registries


func test_the_filters_come_out_in_the_order_they_always_did() -> void:
    var registries := _registries()
    var keys: Array[String] = []
    for key: StringName in registries.filters.list_keys():
        keys.append(String(key).trim_prefix("sara-base-modules."))
    assert_eq(keys, FILTERS, "every filter id, in registration order")


func test_the_sections_come_out_in_the_order_they_always_did() -> void:
    var registries := _registries()
    var words: Array[String] = []
    for section: SaFilterRegistry.Section in registries.filters.list_sections():
        words.append("%s:%s:%d" % [section.id, section.label, section.place])
    assert_eq(words, SECTIONS, "every section id with its label and place, in the menu's order")
