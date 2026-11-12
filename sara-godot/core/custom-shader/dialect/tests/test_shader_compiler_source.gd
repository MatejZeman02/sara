## GlobalShaderCompiler's source front end: comments, kernels, formats, and the
## index and cache around them.
##
## Everything the front end does is a pure string transform. The transforms live
## in `sa_kernel_source.gd` beside the dialect, reached by path the way the
## compiler reaches it, and the storage format substitution is asked of the
## autoload's `source`, which owns the supported set.
##
## The front end is worth testing on its own because its mistakes are silent.
## A miscounted kernel does not fail to compile, it compiles the wrong kernel:
## `get_kernel_index()` is a position in this list, so anything that shifts the
## list swaps one blend mode for another and the picture is merely wrong.
##
## Two siblings hold the rest of the same compiler, split off because a
## test case is a public method and gdlint caps a class at thirty-two:
## `test_shader_compiler_includes.gd` for the paste and the line map, which are
## one reading, and `test_shader_compiler_layout.gd` for the push constant block.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const KernelSource := preload("res://core/custom-shader/dialect/sa_kernel_source.gd")

# --- Comments and kernel extraction ---------------------------------------------


func test_kernels_come_back_in_source_order() -> void:
    var kernels := KernelSource.extract_kernels("#kernel alpha\n#kernel beta\n#kernel gamma\n")

    assert_eq(kernels, ["alpha", "beta", "gamma"], "Kernel order is the index order callers rely on")


## The reason comments are stripped before anything is parsed. A commented-out
## kernel that still counted would shift every index after it by one, and the
## symptom is a blend mode quietly doing another mode's arithmetic.
func test_a_commented_out_kernel_is_not_extracted() -> void:
    var source := "#kernel alpha\n// #kernel disabled\n#kernel beta\n"

    var raw := KernelSource.extract_kernels(source)
    var cleaned := KernelSource.extract_kernels(KernelSource.remove_comments(source))

    assert_eq(raw.size(), 3, "Without stripping comments the disabled kernel is counted")
    assert_eq(cleaned, ["alpha", "beta"], "Stripping comments first is what keeps the indices honest")


func test_a_block_comment_hides_a_kernel_too() -> void:
    var source := "#kernel alpha\n/* #kernel disabled\n   still disabled */\n#kernel beta\n"

    var cleaned := KernelSource.extract_kernels(KernelSource.remove_comments(source))

    assert_eq(cleaned, ["alpha", "beta"], "A block comment spanning lines hides what is inside it")


func test_a_file_with_no_kernels_yields_none() -> void:
    assert_eq(KernelSource.extract_kernels("float helper() { return 1.0; }"), [], "A library declares no kernels")


# --- numthreads -----------------------------------------------------------------


func test_numthreads_is_parsed_off_the_matching_kernel() -> void:
    var code := "[numthreads(8, 8, 1)]\nvoid paint(uvec3 id) {}\n[numthreads(16, 4, 2)]\nvoid blur(uvec3 id) {}\n"

    assert_eq(KernelSource.extract_numthreads("paint", code), ["8", "8", "1"], "paint's own sizes")
    assert_eq(KernelSource.extract_numthreads("blur", code), ["16", "4", "2"], "blur's own sizes")


func test_numthreads_tolerates_the_whitespace_a_human_writes() -> void:
    var code := "[numthreads(  32,2 ,  1 )]\n   void  paint  (uvec3 id) {}\n"

    assert_eq(KernelSource.extract_numthreads("paint", code), ["32", "2", "1"], "Spacing is not meaning")


# --- Kernel signature rewriting -------------------------------------------------


func test_the_selected_kernel_becomes_main() -> void:
    var code := "#kernel paint\n[numthreads(8, 8, 1)]\nvoid paint(uvec3 id) { work(); }\n"

    var rewritten := KernelSource.replace_kernel_signature("paint", code)

    assert_true("void main(" in rewritten, "GLSL needs an entry point called main")
    assert_false("#kernel" in rewritten, "The #kernel directive is not GLSL")


## Every other kernel stays in the source as an ordinary function. Its
## [numthreads] attribute is not GLSL, so leaving it there is a syntax error.
func test_the_other_kernels_lose_their_numthreads_attribute() -> void:
    var code := "[numthreads(8, 8, 1)]\nvoid paint(uvec3 id) {}\n[numthreads(16, 16, 1)]\nvoid blur(uvec3 id) {}\n"

    var rewritten := KernelSource.replace_kernel_signature("paint", code)

    assert_false("numthreads" in rewritten, "No numthreads attribute may survive into GLSL")
    assert_true("void blur(" in rewritten, "The other kernel stays, as a plain function")


func test_the_local_size_layout_carries_the_parsed_sizes() -> void:
    var assembled := KernelSource.assemble_glsl(["8", "4", "1"], "void main() {}")

    assert_true(assembled.begins_with("#version 450"), "The version directive has to come first")
    assert_true("local_size_x = 8, local_size_y = 4, local_size_z = 1" in assembled, "The parsed sizes reach the layout")


# --- Storage format substitution ------------------------------------------------


func test_the_storage_format_token_becomes_a_glsl_qualifier() -> void:
    var source := "layout(SA_STORAGE_FORMAT, binding = 0) uniform image2D dst;"

    var f32 := GlobalShaderCompiler.source.substitute_storage_formats(source, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, {})
    var f16 := GlobalShaderCompiler.source.substitute_storage_formats(source, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, {})

    assert_true("layout(rgba32f," in f32, "F32 compiles to the rgba32f qualifier")
    assert_true("layout(rgba16f," in f16, "F16 compiles to the rgba16f qualifier")
    assert_false("SA_STORAGE_FORMAT" in f32, "No token may survive into GLSL")


func test_every_supported_format_has_a_qualifier() -> void:
    for format: int in GlobalShaderCompiler.STORAGE_FORMAT_NAMES:
        assert_true(GlobalShaderCompiler.supports_storage_format(format), "A named format is a supported one")
    assert_true(GlobalShaderCompiler.supports_storage_format(RenderingDevice.DATA_FORMAT_R32_SFLOAT), "A one-channel field too")
    assert_true(GlobalShaderCompiler.supports_storage_format(RenderingDevice.DATA_FORMAT_R16_SFLOAT), "at either depth")


# --- Discovery and hot reload ---------------------------------------------------


func test_a_shader_name_is_the_filename_without_directory_or_extension() -> void:
    assert_eq(GlobalShaderCompiler.index.get_shader_name("res://shaders/compute/composite.gmacs"), "composite", "Bare name")


## The scan used to walk the whole project, which here is 2695 files of which
## 2319 are the engine's import cache and the vendored gdtoolkit env.
##
## Cost is the smaller half. `.godot` holds *copies* of imported resources, and
## `_find_include_file` matches an include by `ends_with` across every
## discovered path, so a duplicate `.gmacs` in there is a second candidate and
## which one wins is directory order.
func test_the_scan_skips_the_engine_cache_and_the_vendored_env() -> void:
    for path: String in GlobalShaderCompiler.index.compute_shader_file_paths:
        for skipped: String in GlobalShaderCompiler.index.SCAN_SKIP_DIRS:
            assert_false("/%s/" % skipped in path, "%s should not have been walked (found %s)" % [skipped, path])


func test_the_scan_found_the_shaders_that_do_exist() -> void:
    assert_false(GlobalShaderCompiler.index.compute_shader_file_paths.is_empty(), "Skipping directories must not skip everything")
    for path: String in GlobalShaderCompiler.index.compute_shader_file_paths:
        assert_true(FileAccess.file_exists(path), "%s should be a real file" % path)


## The hot-reload scan compares timestamps before it reads anything, so a file
## whose time is unknown reads as changed. Recording it at load is what stops
## the first scan re-reading every shader for nothing.
func test_loading_a_shader_records_its_modification_time() -> void:
    var path: String = GlobalShaderCompiler.index.compute_shader_file_paths[0]
    GlobalShaderCompiler.source.shader_mtimes.erase(path)

    GlobalShaderCompiler.source.load_shader_file(path)

    assert_true(GlobalShaderCompiler.source.shader_mtimes.has(path), "The time is recorded alongside the source")
    assert_eq(
        GlobalShaderCompiler.source.shader_mtimes[path], FileAccess.get_modified_time(path), "and it is the file's actual time"
    )


# --- The SPIR-V cache -----------------------------------------------------------


## The SPIR-V cache is keyed on the exact source, so a hit is a hit and an edit
## is a miss.
##
## glslang is the startup cost, 130 ms across 24 kernels before this existed, of
## which 67 ms was whichever kernel happened to compile first and paid for the
## warm-up. Reusing the bytes takes a warm start to about 10 ms. That only holds
## while the key is exact: a key that collided across two different sources would
## hand a kernel someone else's machine code, which is not a failure that reports
## itself.
func test_the_spirv_cache_is_keyed_on_the_exact_source() -> void:
    var source := "#version 450\nvoid main() {}\n"

    var key := SaSpirvCache.key_for(source)
    assert_eq(key, SaSpirvCache.key_for(source), "The same source is the same key")
    assert_true(key != SaSpirvCache.key_for(source + "\n"), "One more newline is a different key")
    assert_eq(key.length(), 64, "A sha256 in hex, so the path is a fixed length whatever the shader")

    # A miss reads as "not cached" rather than as an error, which is what lets a
    # first run and a read-only cache directory behave identically.
    assert_null(SaSpirvCache.load_spirv("0".repeat(64)), "A key nothing was stored under misses")


## Every kernel Sara ships is in the cache after a normal startup, and each one
## loads back as bytes the driver accepts.
func test_the_cache_holds_what_was_compiled_this_run() -> void:
    var compiler := GlobalShaderCompiler
    var names := compiler.get_kernel_names("composite")
    assert_true(names.size() >= 20, "The composite kernels are the ones worth caching")

    var dir := DirAccess.open(SaSpirvCache.cache_dir())
    assert_not_null(dir, "Startup created the cache directory")
    if dir == null:
        return
    var entries := 0
    for file_name in dir.get_files():
        if file_name.ends_with(".spv"):
            entries += 1
    assert_true(entries >= names.size(), "with at least one entry per kernel compiled")
    assert_true(entries <= SaSpirvCache.CACHE_MAX, "and pruned to the cap, so it cannot grow without bound")


## The cap holds without anyone calling `prune`, which is the point.
##
## The prune used to be reached only through `SaShaderIndex.report_compilation`,
## which the boot header calls, and a headless run builds no boot header. So the
## gate, which is the thing that writes most of these entries, pruned nothing:
## a clone with a long history of shader edits behind it ends every run further
## over the cap, and the assertion above it goes red on a checkout nobody has
## touched.
##
## This writes entries of its own, straight to disk rather than through `store`,
## which is the case a counter cannot see and the reason there is not one: two
## Godot processes sharing a checkout's `user://` do the same thing. Then it
## writes one more through the door every compile uses. It costs whatever real
## entries the prune drops, which is a recompile on the next run and nothing
## else, and that is the cap doing its job rather than a side effect.
func test_a_write_over_the_cap_prunes_without_a_boot_header() -> void:
    DirAccess.make_dir_recursive_absolute(SaSpirvCache.cache_dir())
    var mine: Array[String] = []
    var every_write_landed := true
    while SaSpirvCache.count() <= SaSpirvCache.CACHE_MAX and mine.size() <= SaSpirvCache.CACHE_MAX:
        var key := "f60test%s" % mine.size()
        var file := FileAccess.open(SaSpirvCache.path_for(key), FileAccess.WRITE)
        if file == null:
            every_write_landed = false
            break
        file.store_buffer(PackedByteArray([0, 0, 0, 0]))
        file.close()
        mine.append(key)
    # One assertion for the whole fill rather than one per entry. How many
    # entries the fill needs depends on how full this machine's cache already
    # was, so an assertion inside the loop made the suite's assertion count a
    # property of the checkout rather than of the code: three runs of an
    # unchanged tree reported 212, 214 and 216. The count is the one
    # number a person compares across a refactoring to see that no test moved,
    # and this suite's could not be compared at all. What is proved is the same,
    # that every write the fill needed landed.
    assert_true(every_write_landed, "The cache directory is writable")
    if not every_write_landed:
        return
    assert_true(SaSpirvCache.count() > SaSpirvCache.CACHE_MAX, "The directory is over the cap to start with")

    var spirv := RDShaderSPIRV.new()
    spirv.bytecode_compute = PackedByteArray([1, 2, 3, 4])
    SaSpirvCache.store("f60testfinal", spirv)

    assert_true(
        SaSpirvCache.count() <= SaSpirvCache.CACHE_MAX, "and one more write takes it back to the cap, with nothing else called"
    )
    for key in mine:
        SaSpirvCache.discard(key)
    SaSpirvCache.discard("f60testfinal")


## An overwrite is not a new entry, so `store` skips the listing there and the
## directory cannot move. The pair is here because the two halves of the write
## path, fresh and not, are the two things the cap depends on being told apart.
func test_writing_the_same_key_twice_is_one_entry() -> void:
    var spirv := RDShaderSPIRV.new()
    spirv.bytecode_compute = PackedByteArray([1, 2, 3, 4])
    var before := SaSpirvCache.count()
    SaSpirvCache.store("f60testtwice", spirv)
    var once := SaSpirvCache.count()
    SaSpirvCache.store("f60testtwice", spirv)

    assert_eq(SaSpirvCache.count(), once, "The second write replaced the first")
    SaSpirvCache.discard("f60testtwice")
    assert_eq(SaSpirvCache.count(), before, "and discarding it leaves the directory where it started")
