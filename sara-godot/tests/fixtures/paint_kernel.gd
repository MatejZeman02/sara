## The retired paint kernel, kept for the suites that dispatch a dab by hand.
##
## `shaders/compute/paint.gmacs` was the stamp brush's engine until the brush
## took `dab.gmacs`, and since then nothing in the running app dispatched it.
## Eight suites did, because a circle with a linear ramp is the
## smallest kernel that binds a canvas, a selection mask and a sixteen float
## push constant, which is what a test of the compute wrapper, the tally, the
## timing pairs, the selection mask or the no-clamp path wants under it. It lives here so the app does not
## compile at boot a kernel
## no tool reaches, and `pack_params` lives here with it, as the stamp brush
## kept it for these suites alone.
##
## The source is a string rather than a `.gmacs` beside this file, because the
## compiler's walk indexes every `.gmacs` under `res://` at boot, `tests/`
## included, and a fixture module under `tests/fixtures/modules` is compiled
## and listed in the SPIR-V manifest the same way. `compile()` writes the text
## under `user://`, which the walk skips as the app's own directory, and
## compiles it from there once per run: the route `test_storage_formats.gd`,
## `test_workgroup_size.gd` and `test_reload_shaders.gd` take for a probe
## kernel. The kernel's own name stays `paint`, so a dispatch reads as it did.
extends RefCounted

## The shader name the suites open, `sara/paint_fixture` to the compiler, and
## the key its dispatches are tallied under with the kernel's name after it.
const NAME := "paint_fixture"

## Where `compile()` writes the source. Under `user://` so the boot walk never
## finds it, and per checkout because the gate points `user://` at `scratch/`.
static var scratch_path: String = SaDataRoot.path("paint_fixture.gmacs")

## Sixteen floats of push constant, which is what the manifest measured the
## kernel's block at and what `pack_params` fills.
const PARAMS_FLOATS := 16

const SOURCE := """# Kernel: paint
# Performs additive or destructive pixel manipulation on a single chunk.
# Uses push constants for brush dynamics (pressure, radius, color).

kernel paint

image canvas
# The document-wide selection, r32f whatever the canvas is, on the same chunk
# grid. A 1 by 1 mask is the no-selection stand-in, and the clamped read below
# is what makes it 1.0 everywhere without a flag (core/api/selection/sa_selection.gd).
image mask: r32f, readonly
params:
    vec2 brush_pos
    vec2 offset
    vec4 color
    float radius
    float hardness
    float hardness_gamma
    float flow
    float mode  # 0.0 = normal paint, 1.0 = erase
    float alpha_lock  # 0.0 = off, 1.0 = on


def paint():
    # Get absolute coordinates from tile offset
    ivec2 pixel_coords = ivec2(global_id.xy) + ivec2(offset)
    vec2 pos = vec2(pixel_coords)
    ivec2 size = image_size(canvas)

    # Protect against writing outside the texture
    if pixel_coords.x >= size.x or pixel_coords.y >= size.y:
        return

    # Calculate distance from the brush center
    float dist = distance(pos, brush_pos)

    # Draw the circle with anti-aliased edges
    if dist < radius:
        # Calculate the solid core size
        float MIN_EDGE = 2.0  # Minimum anti-aliased edge width in pixels
        float max_core = max(0.0, radius - MIN_EDGE)
        float core_radius = min(radius * hardness, max_core)

        # gradient from core to edge
        float aa_alpha = clamp((radius - dist) / (radius - core_radius), 0.0, 1.0)

        # gamma curve to shape the falloff
        aa_alpha = pow(aa_alpha, hardness_gamma)
        float src_a = aa_alpha * color.a * flow
        # Coverage scales the dab, so a feathered edge paints a feathered edge.
        src_a *= image_load(mask, min(pixel_coords, image_size(mask) - 1)).r

        vec4 original_color = image_load(canvas, pixel_coords)
        float dst_a = original_color.a

        # If alpha lock is on and destination is completely transparent, do nothing
        if alpha_lock > 0.5 and dst_a <= 0.0:
            return

        if mode > 0.5:
            # Eraser mode: reduce destination alpha
            if alpha_lock > 0.5:
                return  # Alpha lock prevents modifying alpha, so erasing does nothing
            float out_a = max(0.0, dst_a * (1.0 - src_a))
            vec3 out_rgb = original_color.rgb
            image_store(canvas, pixel_coords, vec4(out_rgb, out_a))
        else:
            # Normal paint mode: Porter-Duff Over
            float blended_a = src_a + dst_a * (1.0 - src_a)
            float out_a = (alpha_lock > 0.5) ? dst_a : blended_a
            vec3 out_rgb = vec3(0.0)

            if blended_a > 0.0:
                out_rgb = (color.rgb * src_a + original_color.rgb * dst_a * (1.0 - src_a)) / blended_a

            image_store(canvas, pixel_coords, vec4(out_rgb, out_a))
"""


## Compiles the kernel once per run. A second call finds it and does nothing,
## so every suite can ask and none has to know which ran first.
static func compile() -> void:
    if not GlobalShaderCompiler.get_kernel_names(NAME).is_empty():
        return
    var file := FileAccess.open(scratch_path, FileAccess.WRITE)
    file.store_string(SOURCE)
    file.close()
    GlobalShaderCompiler.compile_compute_shader(scratch_path)


## A compute on the kernel, compiled if this run has not yet.
static func compute() -> SaCompute:
    compile()
    return SaCompute.new(NAME)


## The kernel's sixteen floats, in the order its `params` block declares them.
## Once the stamp brush's `SaDabPacking.pack_paint_params`.
static func pack_params(
    brush_pos: Vector2,
    offset: Vector2,
    color: Color,
    radius: float,
    hardness: float,
    hardness_gamma: float,
    flow: float,
    mode: float = 0.0,
    alpha_lock: float = 0.0,
    pad1: float = 0.0,
    pad2: float = 0.0
) -> PackedFloat32Array:
    return PackedFloat32Array(
        [
            brush_pos.x,
            brush_pos.y,
            offset.x,
            offset.y,
            color.r,
            color.g,
            color.b,
            color.a,
            radius,
            hardness,
            hardness_gamma,
            flow,
            mode,
            alpha_lock,
            pad1,
            pad2
        ]
    )
