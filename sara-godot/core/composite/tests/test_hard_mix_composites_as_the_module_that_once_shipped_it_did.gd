## Hard Mix is one of the skeleton's blend modes, a row of the table in
## `core/loader/skeleton_blend_modes.gd` and a formula of
## `libs/composite_blend_modes.gmacs`, and it composites what the module that
## once shipped it composited.
##
## The module's kernel is kept as a test module's own,
## `tests/fixtures/blend-kernel/modules/blend-kernel-fixture/kept_hard_mix.gmacs`, so
## the comparison is against the kernel that ran, dispatched now, rather than
## against values written down once. Both run over one grid of pairs, greys,
## colours and values above white, translucent and opaque, at two reference
## whites, and must agree within half precision's step.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

## Every value is a texel the GPU wrote and the suite read back.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const SkeletonBlendModes = preload("res://core/loader/skeleton_blend_modes.gd")
const FixtureModule = preload("res://tests/fixtures/blend-kernel/modules/blend-kernel-fixture/module.gd")

const SIZE := Vector2i(32, 32)

## 32 / 8, the [numthreads(8, 8, 1)] the composite kernels declare.
const GROUPS: int = 4

## Under a layer's opacity below one, so the opacity reaches the answer too.
const OPACITY := 0.75

## The inputs on either side of the pair: a ramp of greys from black to white,
## colours with their channels apart so no channel can stand in for another,
## and values past white up to forty times it. Each takes every other as its
## partner, and one in three is translucent.
const GREYS: Array[float] = [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0]
const COLOURS: Array[Color] = [
    Color(0.9, 0.2, 0.05),
    Color(0.1, 0.6, 0.85),
    Color(0.45, 0.55, 0.3),
    Color(1.0, 0.0, 0.5),
    Color(0.7, 0.35, 0.95),
]
const ABOVE: Array[Color] = [
    Color(1.25, 1.25, 1.25),
    Color(2.0, 0.4, 0.1),
    Color(4.0, 4.0, 4.0),
    Color(0.3, 8.0, 1.5),
    Color(40.0, 40.0, 40.0),
]


## The two kernels agree on every pair, which is the first clause of the unit
## that moved Hard Mix: the same result the module's kernel gave, within half
## precision's step, values above white included.
func test_the_built_in_hard_mix_composites_what_the_modules_kernel_did() -> void:
    var pairs := _pairs()
    assert_true(pairs.size() <= SIZE.x * SIZE.y, "every pair has a texel of its own")
    for white: float in [1.0, 2.0]:
        var built_in := _blend("composite", "hard_mix", pairs, white, OPACITY)
        var kept := _blend(FixtureModule.SHADER, FixtureModule.KERNEL, pairs, white, OPACITY)
        var worst := 0.0
        var worst_at := -1
        for i in pairs.size():
            for channel in 4:
                var step := _half_step(kept[i][channel])
                var off := absf(built_in[i][channel] - kept[i][channel]) / step
                if off > worst:
                    worst = off
                    worst_at = i
        assert_true(
            worst <= 1.0,
            (
                "At white %s Hard Mix lies within a half's step of the module's kernel, the worst %s steps at pair %s"
                % [white, worst, worst_at]
            )
        )


## The grid reached the cases that tell a Hard Mix from anything else: corners
## lit and dark under white, and a channel carrying its light above it. A grid
## that only ever lit everything would agree with a kernel that was wrong.
func test_the_grid_reaches_dark_corners_lit_ones_and_light_above_white() -> void:
    var pairs := _pairs()
    var out := _blend("composite", "hard_mix", pairs, 1.0, 1.0)
    var dark := 0
    var lit := 0
    var past := 0
    for i in pairs.size():
        if pairs[i][0].a < 1.0 or pairs[i][1].a < 1.0:
            continue
        for channel in 3:
            if is_zero_approx(out[i][channel]):
                dark += 1
            elif is_equal_approx(out[i][channel], 1.0):
                lit += 1
            elif out[i][channel] > 1.0:
                past += 1
    assert_true(dark > 0, "some opaque channels land dark, %s of them" % dark)
    assert_true(lit > 0, "some land lit at white, %s of them" % lit)
    assert_true(past > 0, "and some carry light above white, %s of them" % past)


## The mode is the skeleton's: a row of its table, filed where the module filed
## it, under its former id too, resolved in `composite` rather than in a module's
## shader.
func test_hard_mix_is_a_row_of_the_skeletons_table() -> void:
    var registries := Fixtures.make_registries()
    var registry := registries.blend_modes
    assert_true(registry.has(&"hard_mix"), "the registry holds Hard Mix with no module loaded")
    var mode := registry.get_descriptor(&"hard_mix")
    assert_eq(mode.shader_name, "composite", "in Sara's own shader")
    assert_eq(mode.owner_module, &"sara-skeleton", "registered by the skeleton")
    assert_eq(mode.display_name, "Hard Mix", "under the name it had")
    assert_eq(mode.category, &"contrast", "in the Contrast section")
    assert_eq(mode.sort_order, 95, "straight after Hard Light")
    assert_eq(mode.domain, SaBlendModeDescriptor.Domain.DISPLAY_REFERRED, "and display-referred")
    assert_eq(registry.canonical(&"pga_hard_mix"), &"hard_mix", "a picture saved under the former id opens as Hard Mix")
    assert_true(registry.resolve_kernel(&"hard_mix") >= 0, "and its kernel resolves")
    var ids: Array[StringName] = []
    for row: Array in SkeletonBlendModes.BLEND_MODES:
        ids.append(row[0])
    assert_true(ids.has(&"hard_mix"), "it is a row of the table")
    assert_false(DirAccess.dir_exists_absolute("res://modules/sara-base-modules/hard-mix"), "and the module's folder is gone")


## Every pair of the grid, as `[source, backdrop]`.
func _pairs() -> Array[Array]:
    var inputs: Array[Color] = []
    for grey in GREYS:
        inputs.append(Color(grey, grey, grey))
    inputs.append_array(COLOURS)
    inputs.append_array(ABOVE)
    var out: Array[Array] = []
    for s in inputs.size():
        for d in inputs.size():
            var source := inputs[s]
            var backdrop := inputs[d]
            source.a = 0.6 if (s + d) % 3 == 0 else 1.0
            backdrop.a = 0.8 if (s + 2 * d) % 3 == 0 else 1.0
            out.append([source, backdrop])
    return out


## The step of a half at *value*: ten bits of mantissa, and the step of the
## smallest normal half below that.
static func _half_step(value: float) -> float:
    var magnitude := maxf(absf(value), pow(2.0, -14.0))
    return pow(2.0, floorf(log(magnitude) / log(2.0)) - 10.0)


## Composites each pair of *pairs*, a source and a backdrop to a texel, through
## *kernel* of *shader* at reference white *white* under *opacity*, and answers
## the stored colour of each.
func _blend(shader: String, kernel: String, pairs: Array[Array], white: float, opacity: float) -> Array[Color]:
    var rd := GlobalShaderCompiler.get_rd()
    var src := PackedFloat32Array()
    var dst := PackedFloat32Array()
    src.resize(SIZE.x * SIZE.y * 4)
    dst.resize(SIZE.x * SIZE.y * 4)
    for i in pairs.size():
        for channel in 4:
            src[i * 4 + channel] = (pairs[i][0] as Color)[channel]
            dst[i * 4 + channel] = (pairs[i][1] as Color)[channel]
    var canvas := SaTexture.new(SIZE)
    var chunk := SaTexture.new(SIZE)
    rd.texture_update(canvas.rid, 0, dst.to_byte_array())
    rd.texture_update(chunk.rid, 0, src.to_byte_array())
    var compute := SaCompute.new(shader)
    compute.set_texture(0, canvas.rid)
    compute.set_texture(1, chunk.rid)
    compute.set_push_constant_float_array(SaCompute.pack_composite_params(Vector2.ZERO, opacity, null, 0.0, white))
    compute.dispatch_kernel(kernel, GROUPS, GROUPS, 1)
    var data := rd.texture_get_data(canvas.rid, 0).to_float32_array()
    var out: Array[Color] = []
    for i in pairs.size():
        out.append(Color(data[i * 4], data[i * 4 + 1], data[i * 4 + 2], data[i * 4 + 3]))
    return out
