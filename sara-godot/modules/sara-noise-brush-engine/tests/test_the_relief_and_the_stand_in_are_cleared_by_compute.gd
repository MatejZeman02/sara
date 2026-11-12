## The relief and the Picture's stand-in are cleared by compute.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A transfer clear is not ordered against the compute that follows it
## and two textures were cleared by one and read by a dispatch in the same
## frame: the relief's
## `heights` and `texture`, and the noise brush's one texel stand-in for a
## Picture that could not be made. The suite holds each site to the `blank`
## kernel twice over. In the source, the function that makes the texture
## calls no transfer clear and dispatches `blank_region`, and a transfer clear
## planted in a copy is caught. In the running app, making the texture
## dispatches the kernel and the texture reads back at its blank.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const NoiseFieldBindingScript = preload("res://modules/sara-noise-brush-engine/dab_list/noise_field_binding.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")

const RELIEF_PATH := "res://core/composite/relief/sa_relief.gd"
const FIELDS_PATH := "res://modules/sara-noise-brush-engine/dab_list/noise_field_binding.gd"
const BLANK := "blank/blank_region"

## Each site, as the file and the functions that make its textures.
const SITES: Array[Dictionary] = [
    {"path": RELIEF_PATH, "functions": ["_allocate", "_blank_whole"]},
    {"path": FIELDS_PATH, "functions": ["bind", "_solid_stand_in"]},
]


## The body of *function* in *text*, from its `func` line to the next line
## indented no deeper than it, or empty when there is none.
static func body_of(text: String, function: String) -> String:
    var lines := text.split("\n")
    var start := -1
    var indent := 0
    for i in lines.size():
        var stripped := lines[i].strip_edges(true, false)
        if stripped.begins_with("func %s(" % function) or stripped.begins_with("static func %s(" % function):
            start = i
            indent = lines[i].length() - stripped.length()
            break
    if start < 0:
        return ""
    var taken := PackedStringArray([lines[start]])
    for i in range(start + 1, lines.size()):
        var line := lines[i]
        var stripped := line.strip_edges(true, false)
        if not stripped.is_empty() and line.length() - stripped.length() <= indent:
            break
        taken.append(line)
    return "\n".join(taken)


## What is wrong with *functions* of *text* as a clear, one line a fault: a
## transfer clear anywhere in them, or no `blank_region` dispatch at all.
static func faults(text: String, functions: Array) -> PackedStringArray:
    var found := PackedStringArray()
    var joined := ""
    for function: String in functions:
        var body := body_of(text, function)
        if body.is_empty():
            found.append("%s: no such function" % function)
            continue
        joined += body + "\n"
        for line in body.split("\n"):
            var code := line.split("#")[0]
            if code.contains(".clear(") or code.contains("texture_clear("):
                found.append("%s: a transfer clear, %s" % [function, line.strip_edges()])
    if not joined.contains('"blank_region"'):
        found.append("no blank_region dispatch in %s" % ", ".join(functions))
    return found


func _read(path: String) -> String:
    return FileAccess.get_file_as_string(path)


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


func _blanks() -> int:
    return int(SaCompute.kernel_counters().get(BLANK, {}).get("dispatches", 0))


func test_each_site_clears_by_compute_and_never_by_a_transfer() -> void:
    for site: Dictionary in SITES:
        var text := _read(site["path"])
        assert_false(text.is_empty(), "%s reads" % site["path"])
        assert_eq(faults(text, site["functions"]), PackedStringArray(), "%s blanks by compute" % site["path"])


func test_a_planted_transfer_clear_is_caught() -> void:
    for site: Dictionary in SITES:
        var text := _read(site["path"])
        var first: String = site["functions"][0]
        var body := body_of(text, first)
        var head := body.split("\n")[0]
        var planted := text.replace(head, head + "\n        heights.clear(Color(0, 0, 0, 0))")
        assert_eq(faults(planted, site["functions"]).size(), 1, "A transfer clear planted in %s is caught" % first)
        var dispatches := text.replace('"blank_region"', '"clear_chunk"')
        assert_eq(faults(dispatches, site["functions"]).size(), 1, "and so is a site that no longer blanks")


func test_the_relief_is_blanked_by_the_kernel_where_nothing_else_writes() -> void:
    var registries := Fixtures.make_registries()
    var easel := SaEasel.create_default(Vector2i(768, 768))
    easel.compositor.set_registry(registries.blend_modes)
    var doc := easel.document
    easel.process_pending_composite()
    var layer := doc.active_layer
    SaHeightOps.new(doc).gain(layer)
    var height := layer.get_or_create_field(Vector2i(1, 1), SaFieldSpec.HEIGHT)
    var bytes := PackedByteArray()
    bytes.resize(height.size.x * height.size.y * 2)
    for i in height.size.x * height.size.y:
        bytes.encode_half(i * 2, 1.0)
    GlobalShaderCompiler.get_rd().texture_update(height.rid, 0, bytes)
    SaCompute.reset_counters()
    doc.invalidate_chunks([Vector2i(1, 1)])
    easel.process_pending_composite()
    var relief := easel.relief
    assert_not_null(relief.texture, "A raised cell allocates the relief")
    if relief.texture != null:
        assert_eq(_blanks(), 2, "and both of its textures are blanked by the kernel, once each")
        var far := Vector2i(700, 20)
        assert_eq(_texel(relief.heights, far).r, 0.0, "a cell nothing raised holds no height")
        assert_eq(_texel(relief.texture, far), Color(0, 0, 1, 0), "and a flat normal")
        var rim := Vector2i(1, 1) * SaLayer.CHUNK_SIZE - Vector2i(2, 2)
        assert_eq(_texel(relief.texture, rim).b, 1.0, "beyond the rim the normal pass wrote, the blank stands")
    SaCompute.reset_counters()
    doc.invalidate_chunks([Vector2i(1, 1)])
    easel.process_pending_composite()
    assert_eq(_blanks(), 0, "A second resolve blanks nothing")
    easel.free()


func test_the_stand_in_is_blanked_by_the_kernel_and_reads_solid() -> void:
    var surface := Fixtures.make_surface()
    var binding: RefCounted = NoiseFieldBindingScript.new()
    var compute := SaCompute.new(StateNoiseBrushScript.KERNEL)
    SaCompute.reset_counters()
    binding.bind(compute)
    assert_eq(_blanks(), 1, "With no picture, the stand-in is made and blanked by the kernel")
    var stand_in: SaTexture = binding._stand_in
    assert_not_null(stand_in, "and bound")
    if stand_in != null:
        assert_eq(_texel(stand_in, Vector2i.ZERO).r, 1.0, "at one, so the stroke paints as if solid")
    SaCompute.reset_counters()
    binding.bind(compute)
    assert_eq(_blanks(), 0, "and a second bind keeps it")
    Fixtures.teardown(surface)
