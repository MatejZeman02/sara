## The groups a dispatch counts are counted off the size the kernel declared.
##
## `[numthreads(x, y, z)]` was parsed, written into the `local_size` line and
## forgotten, so `SaCompute.run()` divided the region by the constant eight. Every
## kernel Sara ships today is 8 by 8, which is why nothing was wrong, and the two
## buffer probes of `test_storage_formats.gd` are already `64, 1, 1`: such a
## kernel over sixty-four pixels was dispatched as eight groups of sixty-four,
## eight times the invocations for the same work and a whole-canvas pass in all
## but name (hard rule 2). The dialect's `@workgroup_size(x, y)` hands the same
## choice to a student.
##
## A group count is not visible from GDScript, so the probe writes
## `gl_NumWorkGroups` into a buffer and counts its own invocations with an atomic,
## which is the dispatch reporting its own shape.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## Written to `user://` by the test and compiled from there, so no probe kernel
## ships in the tree or in the startup report, the shape `test_storage_formats.gd`
## established. One preamble, one wide kernel and one square one, so the two are
## the same dispatch asked of two declarations.
const PROBE_NAME := "sa_workgroup_probe"
static var scratch_probe_path: String = SaDataRoot.path("sa_workgroup_probe.gmacs")
const PROBE_SOURCE := """
#kernel wide_probe
#kernel square_probe

layout( std430, set = 0, binding = 0 ) buffer Counts { uint values[4]; } counts;

[numthreads( 64, 1, 1 )] void wide_probe() {
    counts.values[0] = gl_NumWorkGroups.x;
    counts.values[1] = gl_NumWorkGroups.y;
    atomicAdd( counts.values[2], 1u );
}

[numthreads( 8, 8, 1 )] void square_probe() {
    counts.values[0] = gl_NumWorkGroups.x;
    counts.values[1] = gl_NumWorkGroups.y;
    atomicAdd( counts.values[2], 1u );
}
"""


func _compiled() -> void:
    if GlobalShaderCompiler.get_kernel_names(PROBE_NAME).is_empty():
        var file := FileAccess.open(scratch_probe_path, FileAccess.WRITE)
        file.store_string(PROBE_SOURCE)
        file.close()
        GlobalShaderCompiler.compile_compute_shader(scratch_probe_path)


## The four counters at zero, so an atomic that never ran reads as zero rather
## than as whatever the last dispatch left.
func _counters() -> SaCompute.Buffer:
    var data := PackedInt32Array()
    data.resize(4)
    data.fill(0)
    return SaCompute.Buffer.new(data.to_byte_array())


## What the counters hold after a run: [groups x, groups y, invocations].
func _run(kernel_name: String, region: Rect2i) -> Array:
    _compiled()
    var counts := _counters()
    var compute := SaCompute.new(PROBE_NAME)
    compute.run(kernel_name, {"counts": counts}, {}, region)
    var back := counts.read().to_int32_array()
    return [back[0], back[1], back[2]]


## The compiler answers the numbers the kernel wrote, rather than the eight every
## caller assumed.
func test_the_declared_workgroup_size_is_read_back() -> void:
    _compiled()

    assert_eq(GlobalShaderCompiler.workgroup_size(PROBE_NAME, "wide_probe"), [64, 1, 1], "The wide kernel is 64 by 1")
    assert_eq(GlobalShaderCompiler.workgroup_size(PROBE_NAME, "square_probe"), [8, 8, 1], "and the square one 8 by 8")


## A kernel nothing compiled cannot be dispatched, so the fallback is an answer
## about a kernel that is not there rather than a guess a dispatch acts on.
func test_an_unknown_kernel_answers_the_eight_every_caller_assumed() -> void:
    assert_eq(GlobalShaderCompiler.workgroup_size(PROBE_NAME, "not_a_kernel"), [8, 8, 1], "An unknown kernel is 8 by 8")
    assert_eq(GlobalShaderCompiler.workgroup_size("not_a_shader", "wide_probe"), [8, 8, 1], "and so is an unknown shader")


## The defect itself: sixty-four pixels of a `64, 1, 1` kernel is one group.
##
## Dividing by eight made it eight, and the seven extra groups each ran sixty-four
## invocations off the end of the work.
func test_a_wide_kernel_over_its_own_width_dispatches_one_group() -> void:
    var counted := _run("wide_probe", Rect2i(0, 0, 64, 1))

    assert_eq(counted[0], 1, "One group along x, not the eight a division by eight gives")
    assert_eq(counted[1], 1, "and one along y")
    assert_eq(counted[2], 64, "so sixty-four invocations for sixty-four pixels, not five hundred and twelve")


## The fifty-six kernels that are 8 by 8 must count exactly as they did.
func test_a_square_kernel_counts_as_it_always_did() -> void:
    var counted := _run("square_probe", Rect2i(0, 0, 16, 16))

    assert_eq(counted[0], 2, "Two groups of eight across")
    assert_eq(counted[1], 2, "and two down")
    assert_eq(counted[2], 256, "which is the sixteen by sixteen region exactly")


## A region narrower than one group is still one group, not none.
##
## `int(3 / 64)` is 0 and RenderingDevice refuses a zero group count rather than
## reading it as no work, which is the crash `groups_for()` carries the same
## `maxi` against.
func test_a_region_narrower_than_a_group_is_still_one_group() -> void:
    var counted := _run("wide_probe", Rect2i(0, 0, 3, 1))

    assert_eq(counted[0], 1, "One group covers it")
    assert_eq(counted[2], 64, "and the sixty-one invocations past the end are the group's own width")
